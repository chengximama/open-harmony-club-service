# admin-check.ps1 —— 轻舟后台管理界面（examples\admin.cj + 我们的 JSON 数据层）端到端验证
#
# 覆盖：
#   1) 自包含产物：build\admin\admin.exe + admin-web\dist + admin.env
#   2) 静态托管 + SPA（/ 返回 index.html，assets 可取）
#   3) /api/login 签发 JWT；/api/me /api/dashboard 带 token 可用
#   4) 鉴权 + RBAC：/api/users 无 token 被拒，带 admin token 放行
#   5) 数据层是 **JSON 文件**（不是 CangDB）：首启建库 + 种子 + 原子写
#   6) 优雅关闭：POST /admin/shutdown 后进程自行退出
#
# 关于 HTTP 状态码（重要）：
#   上游统一响应壳把业务码放在 **body 的 code 字段**（0=成功），HTTP 状态不承载业务语义；
#   admin-web 前端也是 `fetch(...).json()` 后只看 `code`，不看 status。
#   又因为 passOnNotFound 的路由在 miss 时会先把 ctx.status 设成 404，而后匹配上的处理器
#   用 respondOk/respondErr 时并不会重设 status —— 所以**成功响应也可能带 404**。
#   这是上游 e072980（当前 HEAD）本身的行为，不是我们的改动：已逐字节比对
#   third_party\qingzhou\src\{api,router,auth}.cj 与上游一致。
#   因此本脚本对 /api/* 断言 **body.code**（业务语义），只对 /health、静态资源断言 HTTP 200
#   （上游在这两处显式设置了 status）。见 docs/API-NOTES.md「坑 34」。
#
# 用法（cwd 任意）：powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\admin-check.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot          # server\
$dir  = Join-Path $root "build\admin"
$exe  = Join-Path $dir "admin.exe"

if (-not (Test-Path $exe)) {
    Write-Host "找不到 $exe —— 先跑：powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Target admin"
    exit 2
}

# 从 admin.env 读取端口与数据文件（与 admin.cj 的 loadConfigFile 同源）
$envFile = Join-Path $dir "admin.env"
$port = 3000
$dbRel = "admin-data/rbac.json"
foreach ($line in Get-Content $envFile -Encoding UTF8) {
    $t = $line.Trim()
    if ($t -match '^port\s*=\s*(\d+)')    { $port  = [int]$Matches[1] }
    if ($t -match '^db\s*=\s*(.+)$')      { $dbRel = $Matches[1].Trim() }
}
$base = "http://127.0.0.1:$port"

$pass = 0; $fail = 0
function Check([string]$name, [bool]$cond, [string]$extra = "") {
    if ($cond) { Write-Host "  ok    $name"; $script:pass++ }
    else       { Write-Host "  FAIL  $name  $extra"; $script:fail++ }
}

# 统一请求：成功与失败（4xx/5xx）都必须能拿到 body。
# 为什么不用 Invoke-WebRequest：PS 5.1 里 4xx/5xx 会抛异常，从 $_.Exception.Response
# 读出来的流**已经是空的**（实测 body 恒为空串，会把"业务码是 0"误判成"没响应"）。
# 这里直接用 System.Net.WebRequest，成功/失败都走同一条读流路径。
function Hit($method, $path, $json, $token) {
    $h = @{}
    if ($token) { $h['Authorization'] = "Bearer $token" }
    $req = [System.Net.WebRequest]::Create("$base$path")
    $req.Proxy = $null                      # 本地回环不走系统代理
    $req.Method = $method
    $req.Timeout = 15000
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

# 取统一响应壳里的业务码；取不到返回 -999（便于和 0/401 区分）
function BizCode($r) {
    $m = [regex]::Match($r.Body, '"code"\s*:\s*(-?\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return -999
}

Write-Host "=== 轻舟后台管理界面 · 端到端（JSON 数据层） ==="
Write-Host "  目录 $dir"
Write-Host "  端口 $port   数据 $dbRel"
Write-Host ""

# 干净起见：清掉上一次的数据，验证"首次启动自动建库"
$dbAbs = Join-Path $dir ($dbRel -replace '/', '\')
if (Test-Path $dbAbs) { Remove-Item $dbAbs -Force }
if (Test-Path "$dbAbs.tmp") { Remove-Item "$dbAbs.tmp" -Force }

$p = Start-Process -FilePath $exe -WorkingDirectory $dir -PassThru -WindowStyle Hidden `
     -RedirectStandardOutput (Join-Path $dir "admin.out.log") -RedirectStandardError (Join-Path $dir "admin.err.log")
$ready = $false
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 200
    if ($p.HasExited) { break }
    try { if ((Invoke-WebRequest "$base/health" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { $ready = $true; break } } catch { }
}
try {
    Check "服务就绪（/health）" $ready
    if (-not $ready) { Get-Content (Join-Path $dir "admin.err.log") -ErrorAction SilentlyContinue | Select-Object -First 10; throw "未就绪" }

    # ---- 运维路由（上游在这里显式设了 status，可以断言 HTTP 200）----
    $r = Hit "GET" "/health" $null $null
    Check "GET /health -> HTTP 200 且 status=ok" (($r.Status -eq 200) -and ($r.Body -match '"status"\s*:\s*"ok"')) "status=$($r.Status) body=$($r.Body)"

    # ---- 静态前端（SPA）----
    $r = Hit "GET" "/" $null $null
    Check "GET / -> HTTP 200 返回前端页面" ($r.Status -eq 200) "status=$($r.Status)"
    Check "页面是 Vue 构建产物（含 assets 引用）" ($r.Body -match 'assets/index-') "len=$($r.Body.Length)"
    $m = [regex]::Match($r.Body, '/assets/[^"]+\.js')
    if ($m.Success) {
        $r2 = Hit "GET" $m.Value $null $null
        Check "静态资源可取（$($m.Value)）" ($r2.Status -eq 200) "status=$($r2.Status)"
    } else { Check "静态资源可取" $false "首页里没解析到 /assets/*.js" }

    # ---- 登录（种子账号）----
    # N-29（2026-09-17）：后台口令不再写死。首次建库时 admin.exe 会随机生成并**追加**到
    # admin.env 的 admin_pass / user_pass，所以必须在**面板启动之后**重新读一次；
    # 老库（建库时就用了 admin123 那种公开默认值）则回退到旧值，保证本脚本两种库都能跑。
    $adminPw = "admin123"
    $userPw  = "user123"
    foreach ($line in (Get-Content $envFile -Encoding UTF8)) {
        $t = $line.Trim()
        if ($t -match '^admin_pass\s*=\s*(\S+)') { $adminPw = $Matches[1] }
        if ($t -match '^user_pass\s*=\s*(\S+)')  { $userPw  = $Matches[1] }
    }
    $r = Hit "POST" "/api/login" (ConvertTo-Json @{ username = "admin"; password = $adminPw } -Compress) $null
    Check "POST /api/login -> code=0" ((BizCode $r) -eq 0) "code=$(BizCode $r) body=$($r.Body)"
    $token = $null
    if ($r.Body -match '"token"\s*:\s*"([^"]+)"') { $token = $Matches[1] }
    Check "拿到 JWT token" ($null -ne $token -and $token.Length -gt 40) "token=$($token)"
    Check "token 形如 JWT（三段点分）" ($token -split '\.').Count -eq 3

    $r = Hit "POST" "/api/login" '{"username":"admin","password":"wrong-password"}' $null
    Check "密码错误 -> code=401" ((BizCode $r) -eq 401) "code=$(BizCode $r) body=$($r.Body)"

    # ---- 登录即可访问 ----
    $r = Hit "GET" "/api/me" $null $token
    Check "GET /api/me（带 token）-> code=0 且 username=admin" (((BizCode $r) -eq 0) -and ($r.Body -match '"username"\s*:\s*"admin"')) "code=$(BizCode $r) body=$($r.Body)"
    $r = Hit "GET" "/api/dashboard" $null $token
    Check "GET /api/dashboard -> code=0 且含 stats" (((BizCode $r) -eq 0) -and ($r.Body -match 'stats')) "code=$(BizCode $r) body=$($r.Body)"

    # ---- 鉴权 + RBAC ----
    $r = Hit "GET" "/api/users" $null $null
    Check "GET /api/users 无 token -> code=401（鉴权生效）" ((BizCode $r) -eq 401) "code=$(BizCode $r) body=$($r.Body)"
    $r = Hit "GET" "/api/users" $null "not-a-jwt"
    Check "GET /api/users 伪造 token -> code=401" ((BizCode $r) -eq 401) "code=$(BizCode $r) body=$($r.Body)"
    $r = Hit "GET" "/api/users" $null $token
    Check "GET /api/users 带 admin token -> code=0（RBAC 放行）" (((BizCode $r) -eq 0) -and ($r.Body -match '"username"\s*:\s*"admin"')) "code=$(BizCode $r) body=$($r.Body)"
    $r = Hit "GET" "/api/roles" $null $token
    Check "GET /api/roles -> code=0 且含 admin/user" (((BizCode $r) -eq 0) -and ($r.Body -match 'admin') -and ($r.Body -match 'user')) "code=$(BizCode $r) body=$($r.Body)"
    $r = Hit "GET" "/api/perms" $null $token
    Check "GET /api/perms -> code=0 且含 user:list" (((BizCode $r) -eq 0) -and ($r.Body -match 'user:list')) "code=$(BizCode $r) body=$($r.Body)"

    # ---- 写路径：建用户 -> 出现在列表里 -> 删除 -> 从列表消失 ----
    $r = Hit "POST" "/api/users" '{"username":"e2e-tmp","password":"e2e-tmp-pw","roleId":2}' $token
    Check "POST /api/users -> code=0（写路径可用）" ((BizCode $r) -eq 0) "code=$(BizCode $r) body=$($r.Body)"
    $newId = $null
    if ($r.Body -match '"id"\s*:\s*(\d+)') { $newId = $Matches[1] }
    $r = Hit "GET" "/api/users" $null $token
    Check "新建用户出现在列表里" ($r.Body -match 'e2e-tmp') "body=$($r.Body)"
    if ($null -ne $newId) {
        $r = Hit "DELETE" "/api/users/$newId" $null $token
        Check "DELETE /api/users/:id -> code=0" ((BizCode $r) -eq 0) "code=$(BizCode $r) body=$($r.Body)"
        $r = Hit "GET" "/api/users" $null $token
        Check "删除后不再出现在列表里" (-not ($r.Body -match 'e2e-tmp')) "body=$($r.Body)"
    } else { Check "DELETE /api/users/:id -> code=0" $false "没有解析到新建用户的 id" }

    # ---- 数据层：必须是 JSON 文件（不是 CangDB）----
    Check "数据文件已生成（$dbRel）" (Test-Path $dbAbs)
    if (Test-Path $dbAbs) {
        $json = Get-Content $dbAbs -Raw -Encoding UTF8
        Check "数据文件是 **JSON**（可被 ConvertFrom-Json 解析）" ($null -ne ($json | ConvertFrom-Json))
        Check "JSON 里含种子账号 admin" ($json -match '"username"\s*:\s*"admin"')
        Check "JSON 里含 6 个权限" (([regex]::Matches($json, '"code"\s*:')).Count -eq 6) "code 数=$(([regex]::Matches($json, '"code"\s*:')).Count)"
        Check "落盘方式是原子写（无残留 .tmp）" (-not (Test-Path "$dbAbs.tmp"))
    }

    # ---- 优雅关闭（需 admin 角色）----
    $r = Hit "POST" "/admin/shutdown" '{}' $token
    Check "POST /admin/shutdown -> code=0" ((BizCode $r) -eq 0) "code=$(BizCode $r) body=$($r.Body)"
    $exited = $false
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 250; if ($p.HasExited) { $exited = $true; break } }
    Check "进程自行退出（优雅关闭走完）" $exited
    $log = Get-Content (Join-Path $dir "admin.out.log") -ErrorAction SilentlyContinue
    Check "日志出现 graceful shutdown complete" (($log -join "`n") -match 'graceful shutdown complete')
    $err = Get-Content (Join-Path $dir "admin.err.log") -ErrorAction SilentlyContinue
    Check "stderr 无异常" ([string]::IsNullOrWhiteSpace(($err -join ""))) "err=$($err -join ' ')"
} finally {
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
}

Write-Host ""
Write-Host ("后台验证： PASS {0} / FAIL {1}" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0