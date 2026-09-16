# ops-check.ps1 —— 轻舟后台「社团管理」运维页 端到端验证
#   （读直读库文件；写以**专用运维账号**的身份走 club-server 真实 API）
#
# 覆盖：
#   1) 运维页静态入口（SPA fallback：/ 与 /club 都返回 index.html）
#   2) 后台自己的 RBAC：登录、/api/me 的 can_ops、无 token → 401、user 角色 → 403
#   3) **HTTP 状态码口径**：成功 200、拒绝 401/403（上游"成功响应带 404"已在我们入口修掉）
#   4) 只读视图：/api/club/{overview,members,depts,tasks,plans,links,audit,config,server-health}
#   5) **安全闸门**：运维接口的响应体里**不得**出现 pw_hash / pw_salt / pw_iter
#   6) **运维身份**：admin.env 的 club_user/club_pass（club-server 的 role = ops）由后台代持，
#      /api/club/session 换出令牌；**页面不需要任何社团账号口令**
#   7) 运维权限：能做「会长专属」的部门增删改与换注册口令、能处置会长；
#      **唯一的减法 = 移交会长**（403 FORBIDDEN_ROLE）；ops 不可由 API 分配
#   8) 写路径回读：注册 → 分配（含 lead/vice_lead 角色中文标签）→ 重置口令 →
#      轮换注册口令 → 新增部门 → 停用；每步都用只读视图回读，证明读的是同一个库文件
#   9) **职责分离**：club-server 的审计里这些动作的 actor 是**运维**，不是会长
#  10) 备份：社团库 + 审计日志复制到 <后台数据目录>/club-backups/
#  11) 两个进程都能优雅关闭
#
# 隔离性：本脚本**不动**你正在用的 build\admin\admin.env —— 先备份、写入自己的一份
# （端口 3099 / club-server 18081 / 数据目录 ops-e2e-data / 自己的运维账号），结束再还原。
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
$presPhone = "13900000001"
$presPw    = "ClubPass2026"
$opsPhone  = "13900000009"         # 专用运维账号（role = ops）
$opsPw     = "OpsPass2026"
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

Write-Host "=== 轻舟后台 · 社团管理运维页 端到端（专用运维账号） ==="
Write-Host "  运维台 $opsBase    club-server $clubBase    数据 $clubDir"
Write-Host "  运维账号 $opsPhone（role = ops）"
Write-Host ""

# ---------- 夹具：干净的社团库 + 会长 + 运维账号 + 自己的 admin.env ----------
$clubAbs = Join-Path $build $clubDir
if (Test-Path $clubAbs) { Remove-Item $clubAbs -Recurse -Force }
# ⚠ 数据目录是**相对 cwd** 的（README 六条坑之一）：必须在 build\ 下执行，
#   否则库会落到 server\ops-e2e-data，服务端从 build\ 启动时读不到（本轮真踩过一次）。
Push-Location $build
$initOut  = & $clubExe init-admin $presPhone $presPw $clubDir 2>&1
$initOut2 = & $clubExe init-admin "13900000008" $presPw $clubDir 2>&1   # 非空库：应被拒绝
$opsOut   = & $clubExe init-ops $opsPhone $opsPw $clubDir 2>&1
$opsOut2  = & $clubExe init-ops $opsPhone $opsPw $clubDir 2>&1          # 幂等：重设口令
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
    "club_port=$clubPort",
    "club_user=$opsPhone",
    "club_pass=$opsPw"
)
[System.IO.File]::WriteAllLines($envFile, $envLines, [System.Text.UTF8Encoding]::new($false))
Remove-Item (Join-Path $admin "admin-data\ops-e2e-rbac.json") -Force -ErrorAction SilentlyContinue

$clubProc = $null; $adminProc = $null
try {
    Check "init-admin 建库并给出注册口令" ($registerCode.Length -ge 4) "code=[$registerCode]"
    Check "init-admin 对非空库幂等拒绝（不覆盖数据）" (($initOut2 -join "`n") -match '已存在会长账号') "out=$($initOut2 -join ' ')"
    Check "init-ops 创建专用运维账号" (($opsOut -join "`n") -match '已创建运维账号') "out=$($opsOut -join ' ')"
    Check "init-ops 幂等（重设口令 + 校准角色）" (($opsOut2 -join "`n") -match '已重设运维账号口令') "out=$($opsOut2 -join ' ')"

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
    Check "概览：1 个会长 / 4 个部门 / 库文件存在" (($null -ne $ov) -and ($ov.members.total -eq 2) -and ($ov.members.president -eq 1) -and ($ov.depts -eq 4) -and $ov.db_exists) "ov=$($r.Body)"
    Check "概览：注册口令可读（运维需要发口令）" (($null -ne $ov) -and $ov.register.has_code) "register=$($ov.register | ConvertTo-Json -Compress)"

    $r = Hit "GET" "/api/club/config" $null $token $null
    Check "GET /api/club/config -> 200 且给出 club-server 地址、数据目录、运维账号" `
        (($r.Status -eq 200) -and ($r.Body -match [regex]::Escape($clubBase)) -and ($r.Body -match [regex]::Escape($clubDir)) -and ($r.Body -match '"ops_account_configured"\s*:\s*true')) "body=$($r.Body)"

    $r = Hit "GET" "/api/club/members" $null $token $null
    Check "GET /api/club/members -> 200（会长 + 运维 共 2 人）" (($r.Status -eq 200) -and ($r.Body -match '"total"\s*:\s*2')) "body=$($r.Body)"
    Check "名录视图**不含** pw_hash / pw_salt / pw_iter" (-not ($r.Body -match 'pw_hash|pw_salt|pw_iter')) "泄露？$($r.Body)"
    Check "运维账号在名录里能认出（role = ops）" ($r.Body -match '"role"\s*:\s*"ops"') "body=$($r.Body)"
    $r = Hit "GET" "/api/club/depts" $null $token $null
    Check "GET /api/club/depts -> 200 且主席团 1 人" (($r.Status -eq 200) -and ($r.Body -match '主席团') -and ($r.Body -match '"active_members"\s*:\s*1')) "body=$($r.Body)"
    foreach ($ep in '/api/club/tasks', '/api/club/plans', '/api/club/links', '/api/club/audit?limit=50') {
        $r = Hit "GET" $ep $null $token $null
        Check "GET $ep -> code=0" ((BizCode $r) -eq 0) "status=$($r.Status) body=$($r.Body)"
    }
    $r = Hit "GET" "/api/club/server-health" $null $token $null
    Check "GET /api/club/server-health -> up=true（后台侧探测 club-server）" (($r.Status -eq 200) -and ($r.Body -match '"up"\s*:\s*true')) "body=$($r.Body)"

    # ---------- 4) 运维会话：后台代持专用运维账号，页面不接触任何社团口令 ----------
    $r = Hit "GET" "/api/club/session" $null $token $null
    $sess = $null
    if ((BizCode $r) -eq 0) { $sess = ($r.Body | ConvertFrom-Json).data }
    Check "GET /api/club/session -> 已配置运维账号" (($r.Status -eq 200) -and $sess.configured) "body=$($r.Body)"
    Check "运维会话身份 = 专用运维账号（role = ops，标签「运维」）" `
        (($sess.identity.role -eq 'ops') -and ($sess.identity.role_label -eq '运维') -and ($sess.identity.phone -eq $opsPhone)) "identity=$($sess.identity | ConvertTo-Json -Compress)"
    $ctoken = $sess.token
    Check "拿到 club-server 运维令牌（无需任何社团账号口令）" ($null -ne $ctoken -and $ctoken.Length -gt 40) "token=$ctoken"

    $r = Club "GET" "/api/v1/auth/me" $null $ctoken
    Check "该令牌在 club-server 侧确实是 ops 身份" (($r.Status -eq 200) -and ($r.Body -match '"role"\s*:\s*"ops"')) "body=$($r.Body)"

    # ---------- 5) 写路径（全部以运维身份） ----------
    $r = Hit "OPTIONS" "$clubBase/api/v1/members/2/assign" $null $null "http://127.0.0.1:$opsPort" $true
    Check "club-server CORS 预检 -> 204（浏览器直连的前提）" ($r.Status -eq 204) "status=$($r.Status)"

    $r = Club "POST" "/api/v1/auth/register" ("{""register_code"":""$registerCode"",""phone"":""13900000002"",""name"":""运维测试"",""password"":""TestPass2026"",""dept_id"":2}") $null
    Check "注册一个待分配成员 -> ok=true" (($r.Status -eq 201) -and ($r.Body -match '"ok"\s*:\s*true')) "body=$($r.Body)"

    $r = Hit "GET" "/api/club/members?status=pending" $null $token $null
    $pend = ($r.Body | ConvertFrom-Json).data.items
    Check "运维页立刻看到这条待分配（读的是同一个库文件）" (($r.Body -match '运维测试') -and ($r.Body -match '课题部')) "body=$($r.Body)"
    $mid = 0
    if ($null -ne $pend -and $pend.Count -ge 1) { $mid = $pend[0].id }

    $r = Club "POST" "/api/v1/members/$mid/assign" '{"role":"ops","dept_id":2}' $ctoken
    Check "ops 不可由 API 分配（只能用 init-ops 创建）" (($r.Body -match '"ok"\s*:\s*false') -and ($r.Body -match 'VALIDATION_FAILED')) "body=$($r.Body)"

    $r = Club "POST" "/api/v1/members/$mid/assign" '{"role":"lead","dept_id":2}' $ctoken
    Check "分配为部长（role = lead）-> ok=true" (($r.Status -eq 200) -and ($r.Body -match '"ok"\s*:\s*true')) "body=$($r.Body)"
    $r = Hit "GET" "/api/club/members?q=运维测试" $null $token $null
    Check "角色中文标签正确（lead → 部长；代号写错会显示空白）" ($r.Body -match '"role_label"\s*:\s*"部长"') "body=$($r.Body)"

    $r = Hit "GET" "/api/club/overview" $null $token $null
    Check "写入后概览随之变化（active=3 / pending=0）" (($r.Body -match '"active"\s*:\s*3') -and ($r.Body -match '"pending"\s*:\s*0')) "body=$($r.Body)"

    $r = Club "POST" "/api/v1/members/1/reset-password" '{}' $ctoken
    Check "运维可重置**会长**的口令（会长忘口令是典型运维场景）" (($r.Status -eq 200) -and ($r.Body -match 'temporary_password"\s*:\s*"[^"]+')) "body=$($r.Body)"

    $r = Club "POST" "/api/v1/register-config/rotate" '{}' $ctoken
    $newCode = ""
    if ($r.Body -match '"code"\s*:\s*"([A-Z0-9]+)"') { $newCode = $Matches[1] }
    Check "运维可换注册口令（副会长做不到，会长/运维才行）" ($newCode.Length -ge 4 -and $newCode -ne $registerCode) "old=$registerCode new=$newCode"
    Check "换口令的 updated_by 是运维（职责分离可见）" ($r.Body -match '"name"\s*:\s*"运维"') "body=$($r.Body)"

    $r = Club "POST" "/api/v1/depts" '{"name":"用户运营部","sort":9}' $ctoken
    Check "运维可新增部门（部门增删改：会长与运维独占）" (($r.Status -eq 201) -and ($r.Body -match '"ok"\s*:\s*true')) "status=$($r.Status) body=$($r.Body)"

    $r = Club "POST" "/api/v1/members/1/transfer-presidency" '{"self_role":"vice_president"}' $ctoken
    Check "运维**不能**移交会长（这一档唯一的减法）" (($r.Status -eq 403) -and ($r.Body -match 'FORBIDDEN_ROLE')) "status=$($r.Status) body=$($r.Body)"

    $r = Club "POST" "/api/v1/members/$mid/disable" '{}' $ctoken
    Check "停用成员 -> ok=true" (($r.Status -eq 200) -and ($r.Body -match '"ok"\s*:\s*true')) "body=$($r.Body)"
    $r = Hit "GET" "/api/club/members?status=disabled" $null $token $null
    Check "运维页读到 disabled 名单" ($r.Body -match '运维测试') "body=$($r.Body)"

    # ---------- 6) 审计：动作 + **actor 是运维**（职责分离） ----------
    $r = Hit "GET" "/api/club/audit?limit=50" $null $token $null
    $au = ($r.Body | ConvertFrom-Json).data
    Check "审计日志解析出敏感操作（assign / reset-password / rotate / create-dept / disable）" `
        (($au.shown -ge 5) -and ($r.Body -match 'assign-member') -and ($r.Body -match 'reset-password') -and ($r.Body -match 'rotate-register-code')) "shown=$($au.shown)"
    Check "审计里 actor 是**运维**而不是会长（职责分离）" `
        (($au.items | Where-Object { $_.actor_name -eq '运维' } | Measure-Object).Count -ge 3) "actors=$(($au.items | ForEach-Object { $_.actor_name }) -join ',')"
    Check "审计行解析成功（parsed 全 true）" (-not ($r.Body -match '"parsed"\s*:\s*false')) ""

    # ---------- 7) 备份 ----------
    $r = Hit "POST" "/api/club/backup" '{}' $token $null
    $bk = $null
    if ((BizCode $r) -eq 0) { $bk = ($r.Body | ConvertFrom-Json).data }
    Check "备份 -> code=0 且文件真的落盘" (($null -ne $bk) -and ($bk.files.Count -ge 1) -and (Test-Path (Join-Path $admin ($bk.files[0] -replace '/', '\')))) "body=$($r.Body)"

    # ---------- 8) 优雅关闭 ----------
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