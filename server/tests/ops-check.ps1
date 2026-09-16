# ops-check.ps1 —— 轻舟后台「社团管理」运维页 端到端验证（读直读库文件 + 写走 club-server 真实 API）
#
# 覆盖：
#   1) 运维页静态入口（SPA fallback：/ 与 /club 都返回 index.html）
#   2) 后台自己的 RBAC：登录、/api/me 的 can_ops、无 token → 401、user 角色 → 403
#   3) **HTTP 状态码口径**：成功 200、拒绝 401/403（上游那处"成功响应带 404"已在我们的入口修掉）
#   4) 只读视图：/api/club/{overview,members,depts,tasks,plans,links,audit,config,server-health}
#   5) **安全闸门**：/api/club/** 的响应体里**不得**出现 pw_hash / pw_salt / pw_iter（口令材料）
#   6) 写路径（浏览器式直连 club-server，带 Origin 走真 CORS）：注册 → 分配 → 重置口令 →
#      轮换注册口令 → 停用；每一步都用只读视图回读，证明"读的是同一个库文件"
#   7) 审计日志：club-server 的敏感操作确实落到 <数据目录>/audit.log，运维页能解析出来
#   8) 备份：把社团库 + 审计日志复制到 <后台数据目录>/club-backups/
#   9) 两个进程都能优雅关闭
#
# 为什么要单独一套：它是**跨两个进程**的验证（运维台只读、club-server 写），
# admin-check.ps1 只覆盖后台自身（RBAC + JSON 数据层）。
#
# 隔离性：本脚本**不动**你正在用的 build\admin\admin.env —— 它先备份、写入自己的一份
# （端口 3099 / club-server 18081 / 数据目录 ops-e2e-data），结束时再还原。
# 因此可以和一个正在跑的 admin.exe（3000）并存。
#
# 前置：先编译两份产物
#   cd server
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target admin
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\ops-check.ps1

$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $PSScriptRoot              # server\
$build = Join-Path $root "build"
$admin = Join-Path $build "admin"
$clubExe  = Join-Path $build "club-server.exe"
$adminExe = Join-Path $admin "admin.exe"

foreach ($p in @($clubExe, $adminExe)) {
    if (-not (Test-Path $p)) {
        Write-Host "找不到 $p"
        Write-Host "先跑：.\build.ps1  与  .\build.ps1 -Target admin"
        exit 2
    }
}

$clubPort  = 18081
$opsPort   = 3099
$clubDir   = "ops-e2e-data"        # 相对 build\
$clubBase  = "http://127.0.0.1:$clubPort"
$opsBase   = "http://127.0.0.1:$opsPort"
$phone     = "13900000001"
$pw        = "ClubPass2026"
$envFile   = Join-Path $admin "admin.env"
$envBackup = Join-Path $admin "admin.env.ops-check.bak"

$pass = 0; $fail = 0
function Check([string]$name, [bool]$cond, [string]$extra = "") {
    if ($cond) { Write-Host "  ok    $name"; $script:pass++ }
    else       { Write-Host "  FAIL  $name  $extra"; $script:fail++ }
}
function BizCode($r) {
    $m = [regex]::Match($r.Body, '"code"\s*:\s*(-?\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return -999
}
# 统一请求：成功与失败都要能拿到 body（PS 5.1 从 $_.Exception.Response 读流恒为空串）
function Hit($method, $path, $json, $token, $origin, $preflight) {
    $h = @{}
    if ($token)  { $h['Authorization'] = "Bearer $token" }
    if ($origin) { $h['Origin'] = $origin }
    if ($preflight) {
        # CORS 预检的判定条件是"有 Access-Control-Request-Method 头"，少了它框架不会当预检处理
        $h['Access-Control-Request-Method']  = $method
        $h['Access-Control-Request-Headers'] = 'authorization,content-type'
    }
    # path 允许是绝对 URL（脚本里打 club-server 时用），否则按运维台地址拼
    $url = if ($path -like 'http*') { $path } else { "$opsBase$path" }
    $req = [System.Net.WebRequest]::Create($url)
    $req.Proxy = $null
    $req.Method = $method
    $req.Timeout = 30000
    foreach ($k in $h.Keys) { $req.Headers[$k] = $h[$k] }
    if ($json) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $req.ContentType = 'application/json; charset=utf-8'
        $req.ContentLength = $bytes.Length
        $s = $req.GetRequestStream(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
    }
    try { $resp = $req.GetResponse() } catch [System.Net.WebException] { $resp = $_.Exception.Response }
    if ($null -eq $resp) { return @{ Status = 0; Body = "" } }
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
    $text = $reader.ReadToEnd(); $reader.Close(); $resp.Close()
    return @{ Status = [int]$resp.StatusCode; Body = $text }
}
# 打 club-server（浏览器视角：带 Origin）
function Club($method, $path, $json, $token) {
    return Hit $method ($clubBase + $path) $json $token "http://127.0.0.1:$opsPort"
}

Write-Host "=== 轻舟后台 · 社团管理运维页 端到端 ==="
Write-Host "  运维台 $opsBase    club-server $clubBase    数据 $clubDir"
Write-Host ""

# ---------- 夹具：干净的社团库 + 自己的 admin.env ----------
$clubAbs = Join-Path $build $clubDir
if (Test-Path $clubAbs) { Remove-Item $clubAbs -Recurse -Force }
# ⚠ 数据目录是**相对 cwd** 的（README 六条坑之一）：必须在 build\ 下执行，
#   否则库会落到 server\ops-e2e-data，服务端从 build\ 启动时读不到（本轮真踩过一次）。
Push-Location $build
$initOut  = & $clubExe init-admin $phone $pw $clubDir 2>&1
$initOut2 = & $clubExe init-admin "13900000009" $pw $clubDir 2>&1   # 非空库：应被拒绝
Pop-Location
$registerCode = ""
if (($initOut -join "`n") -match '当前注册口令：([A-Z0-9]+)') { $registerCode = $Matches[1] }
if (Test-Path $envFile) { Copy-Item $envFile $envBackup -Force }
$envLines = @(
    "port=$opsPort",
    "db=admin-data/ops-e2e-rbac.json",
    "secret=ops-check-0123456789abcdef0123456789abcdef",
    "ttl=7200",
    "club_data=../$clubDir",
    "club_api=$clubBase",
    "club_port=$clubPort"
)
[System.IO.File]::WriteAllLines($envFile, $envLines, [System.Text.UTF8Encoding]::new($false))
Remove-Item (Join-Path $admin "admin-data\ops-e2e-rbac.json") -Force -ErrorAction SilentlyContinue

$clubProc = $null; $adminProc = $null
try {
    Check "init-admin 建库并给出注册口令" ($registerCode.Length -ge 4) "code=[$registerCode]"
    Check "init-admin 对非空库幂等拒绝（不覆盖数据）" (($initOut2 -join "`n") -match '已存在会长账号') "out=$($initOut2 -join ' ')"

    $clubProc = Start-Process -FilePath $clubExe -ArgumentList 'serve', "$clubPort", $clubDir `
        -WorkingDirectory $build -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $build "ops-e2e-club.out.log") -RedirectStandardError (Join-Path $build "ops-e2e-club.err.log")
    $adminProc = Start-Process -FilePath $adminExe -WorkingDirectory $admin -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $admin "ops-e2e.out.log") -RedirectStandardError (Join-Path $admin "ops-e2e.err.log")

    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $a = (Invoke-WebRequest "$opsBase/health" -UseBasicParsing -TimeoutSec 2).StatusCode
            $b = (Invoke-WebRequest "$clubBase/health" -UseBasicParsing -TimeoutSec 2).StatusCode
            if ($a -eq 200 -and $b -eq 200) { $ready = $true; break }
        } catch { }
    }
    Check "两个服务都就绪（运维台 + club-server）" $ready
    if (-not $ready) { throw "未就绪" }

    # ---------- 1) 静态入口 ----------
    $r = Hit "GET" "/club" $null $null $null
    Check "GET /club -> 200 且是前端页面（SPA fallback）" (($r.Status -eq 200) -and ($r.Body -match 'assets/index-')) "status=$($r.Status)"
    $r = Hit "GET" "/" $null $null $null
    Check "GET / -> 200" ($r.Status -eq 200) "status=$($r.Status)"

    # ---------- 2) 后台 RBAC ----------
    $r = Hit "POST" "/api/login" '{"username":"admin","password":"admin123"}' $null $null
    Check "后台登录 -> code=0" ((BizCode $r) -eq 0) "body=$($r.Body)"
    $token = $null
    if ($r.Body -match '"token"\s*:\s*"([^"]+)"') { $token = $Matches[1] }
    Check "拿到后台 token" ($null -ne $token -and $token.Length -gt 40)
    $r = Hit "GET" "/api/me" $null $token $null
    Check "GET /api/me -> HTTP 200 且 can_ops=true" (($r.Status -eq 200) -and ($r.Body -match '"can_ops"\s*:\s*true')) "status=$($r.Status) body=$($r.Body)"

    $r = Hit "GET" "/api/club/overview" $null $null $null
    Check "运维接口无 token -> HTTP 401 且 code=401" (($r.Status -eq 401) -and ((BizCode $r) -eq 401)) "status=$($r.Status) body=$($r.Body)"

    $r = Hit "POST" "/api/login" '{"username":"user","password":"user123"}' $null $null
    $tokenUser = $null
    if ($r.Body -match '"token"\s*:\s*"([^"]+)"') { $tokenUser = $Matches[1] }
    $r = Hit "GET" "/api/club/overview" $null $tokenUser $null
    Check "运维接口 user 角色 -> HTTP 403 且 code=403" (($r.Status -eq 403) -and ((BizCode $r) -eq 403)) "status=$($r.Status) body=$($r.Body)"

    # ---------- 3) 只读视图 ----------
    $r = Hit "GET" "/api/club/overview" $null $token $null
    Check "GET /api/club/overview -> HTTP 200（不是上游那个 404）" ($r.Status -eq 200) "status=$($r.Status)"
    $ov = $null
    if ((BizCode $r) -eq 0) { $ov = ($r.Body | ConvertFrom-Json).data }
    Check "概览：1 个会长 / 4 个部门 / 库文件存在" (($null -ne $ov) -and ($ov.members.total -eq 1) -and ($ov.members.president -eq 1) -and ($ov.depts -eq 4) -and $ov.db_exists) "ov=$($r.Body)"
    Check "概览：注册口令可读（运维需要发口令）" (($null -ne $ov) -and $ov.register.has_code) "register=$($ov.register | ConvertTo-Json -Compress)"

    $r = Hit "GET" "/api/club/config" $null $token $null
    Check "GET /api/club/config -> 200 且给出 club-server 地址与数据目录" (($r.Status -eq 200) -and ($r.Body -match [regex]::Escape($clubBase)) -and ($r.Body -match [regex]::Escape($clubDir))) "body=$($r.Body)"

    $r = Hit "GET" "/api/club/members" $null $token $null
    Check "GET /api/club/members -> 200 且 1 条" (($r.Status -eq 200) -and ($r.Body -match '"total"\s*:\s*1')) "body=$($r.Body)"
    # 安全闸门：只读视图绝不能带口令材料（store.cj 的 memberToJson 会带，所以这里另写了白名单视图）
    Check "名录视图**不含** pw_hash / pw_salt / pw_iter" (-not ($r.Body -match 'pw_hash|pw_salt|pw_iter')) "泄露？$($r.Body)"
    $r = Hit "GET" "/api/club/depts" $null $token $null
    Check "GET /api/club/depts -> 200 且主席团 1 人" (($r.Status -eq 200) -and ($r.Body -match '主席团') -and ($r.Body -match '"active_members"\s*:\s*1')) "body=$($r.Body)"
    foreach ($ep in '/api/club/tasks', '/api/club/plans', '/api/club/links', '/api/club/audit?limit=50') {
        $r = Hit "GET" $ep $null $token $null
        Check "GET $ep -> code=0" ((BizCode $r) -eq 0) "status=$($r.Status) body=$($r.Body)"
    }

    $r = Hit "GET" "/api/club/server-health" $null $token $null
    Check "GET /api/club/server-health -> up=true（后台侧探测 club-server）" (($r.Status -eq 200) -and ($r.Body -match '"up"\s*:\s*true')) "body=$($r.Body)"

    # ---------- 4) 写路径：浏览器式直连 club-server ----------
    $r = Hit "OPTIONS" "$clubBase/api/v1/members/2/assign" $null $null "http://127.0.0.1:$opsPort" $true
    Check "club-server CORS 预检 -> 204（浏览器直连的前提）" ($r.Status -eq 204) "status=$($r.Status)"

    $r = Club "POST" "/api/v1/auth/login" ("{""phone"":""$phone"",""password"":""$pw""}") $null
    Check "会长登录 club-server（带 Origin）-> ok=true" (($r.Status -eq 200) -and ($r.Body -match '"ok"\s*:\s*true')) "body=$($r.Body)"
    $ctoken = ($r.Body | ConvertFrom-Json).data.token
    $crole  = ($r.Body | ConvertFrom-Json).data.member.role
    Check "登录身份是会长" ($crole -eq 'president') "role=$crole"

    $r = Club "POST" "/api/v1/auth/register" ("{""register_code"":""$registerCode"",""phone"":""13900000002"",""name"":""运维测试"",""password"":""TestPass2026"",""dept_id"":2}") $null
    Check "注册一个待分配成员 -> ok=true" (($r.Status -eq 201) -and ($r.Body -match '"ok"\s*:\s*true')) "body=$($r.Body)"

    $r = Hit "GET" "/api/club/members?status=pending" $null $token $null
    $pend = ($r.Body | ConvertFrom-Json).data.items
    Check "运维页立刻看到这条待分配（读的是同一个库文件）" (($r.Body -match '运维测试') -and ($r.Body -match '课题部')) "body=$($r.Body)"
    $mid = 0
    if ($null -ne $pend -and $pend.Count -ge 1) { $mid = $pend[0].id }

    $r = Club "POST" "/api/v1/members/$mid/assign" '{"role":"president","dept_id":2}' $ctoken
    Check "非法写被 club-server 拒绝（会长只能移交，不能 assign）" ($r.Body -match '"ok"\s*:\s*false') "body=$($r.Body)"

    $r = Club "POST" "/api/v1/members/$mid/assign" '{"role":"member","dept_id":2}' $ctoken
    Check "分配成员 -> ok=true" (($r.Status -eq 200) -and ($r.Body -match '"ok"\s*:\s*true')) "body=$($r.Body)"
    $r = Hit "GET" "/api/club/overview" $null $token $null
    Check "写入后概览随之变化（active=2 / pending=0）" (($r.Body -match '"active"\s*:\s*2') -and ($r.Body -match '"pending"\s*:\s*0')) "body=$($r.Body)"

    $r = Club "POST" "/api/v1/members/$mid/reset-password" '{}' $ctoken
    Check "重置口令 -> 返回临时口令" (($r.Status -eq 200) -and ($r.Body -match 'temporary_password"\s*:\s*"[^"]+')) "body=$($r.Body)"

    $r = Club "POST" "/api/v1/register-config/rotate" '{}' $ctoken
    $newCode = ""
    if ($r.Body -match '"code"\s*:\s*"([A-Z0-9]+)"') { $newCode = $Matches[1] }
    Check "轮换注册口令 -> 新口令与旧的不同" ($newCode.Length -ge 4 -and $newCode -ne $registerCode) "old=$registerCode new=$newCode"

    $r = Hit "GET" "/api/club/audit?limit=50" $null $token $null
    $au = ($r.Body | ConvertFrom-Json).data
    Check "审计日志能解析出敏感操作（assign / reset-password / rotate）" `
        (($au.shown -ge 3) -and ($r.Body -match 'assign-member') -and ($r.Body -match 'reset-password') -and ($r.Body -match 'rotate-register-code')) "shown=$($au.shown) body=$($r.Body.Substring(0, [Math]::Min(400, $r.Body.Length)))"
    Check "审计行解析成功（parsed 全 true）" (-not ($r.Body -match '"parsed"\s*:\s*false')) "body=$($r.Body.Substring(0, [Math]::Min(400, $r.Body.Length)))"

    $r = Club "POST" "/api/v1/members/$mid/disable" '{}' $ctoken
    Check "停用成员 -> ok=true" (($r.Status -eq 200) -and ($r.Body -match '"ok"\s*:\s*true')) "body=$($r.Body)"
    $r = Hit "GET" "/api/club/members?status=disabled" $null $token $null
    Check "运维页读到 disabled 名单" ($r.Body -match '运维测试') "body=$($r.Body)"

    # ---------- 5) 备份 ----------
    $r = Hit "POST" "/api/club/backup" '{}' $token $null
    $bk = $null
    if ((BizCode $r) -eq 0) { $bk = ($r.Body | ConvertFrom-Json).data }
    Check "备份 -> code=0 且文件真的落盘" (($null -ne $bk) -and ($bk.files.Count -ge 1) -and (Test-Path (Join-Path $admin ($bk.files[0] -replace '/', '\')))) "body=$($r.Body)"

    # ---------- 6) 优雅关闭 ----------
    # 这条同时是**回归闸门**：原先 handleShutdown 立刻 spawn shutdown()，
    # 会先于本响应写出把服务 close 掉 → 客户端拿到 200 + **空 body**（实测 8 次里 6 次）。
    # 现在关停线程先 sleep 1 秒再关（见 server/src/main.cj 的注释）。
    $r = Club "POST" "/admin/shutdown" '{}' $ctoken
    Check "club-server 优雅关闭 -> HTTP 200 且回执 ok=true" (($r.Status -eq 200) -and ($r.Body -match '"ok"\s*:\s*true')) "status=$($r.Status) body=[$($r.Body)]"
    $r = Hit "POST" "/admin/shutdown" '{}' $token $null
    Check "运维台优雅关闭 -> code=0" ((BizCode $r) -eq 0) "body=$($r.Body)"
    $clubGone = $false; $adminGone = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        if ($clubProc.HasExited)  { $clubGone = $true }
        if ($adminProc.HasExited) { $adminGone = $true }
        if ($clubGone -and $adminGone) { break }
    }
    Check "两个进程都自行退出" ($clubGone -and $adminGone) "club=$clubGone admin=$adminGone"
    $log = Get-Content (Join-Path $admin "ops-e2e.out.log") -ErrorAction SilentlyContinue
    Check "运维台日志出现 graceful shutdown complete" (($log -join "`n") -match 'graceful shutdown complete')
    $err = Get-Content (Join-Path $admin "ops-e2e.err.log") -ErrorAction SilentlyContinue
    Check "运维台 stderr 无异常" ([string]::IsNullOrWhiteSpace(($err -join ""))) "err=$($err -join ' ')"
} finally {
    if ($null -ne $clubProc  -and -not $clubProc.HasExited)  { Stop-Process -Id $clubProc.Id  -Force }
    if ($null -ne $adminProc -and -not $adminProc.HasExited) { Stop-Process -Id $adminProc.Id -Force }
    # 还原你自己的 admin.env（本脚本只是借它跑一遍）
    if (Test-Path $envBackup) { Move-Item $envBackup $envFile -Force }
}

Write-Host ""
Write-Host ("运维页验证： PASS {0} / FAIL {1}" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0