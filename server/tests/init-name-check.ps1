# init-name-check.ps1 —— `init-admin` 的**会长姓名**选项回归闸门（2026-09-17 新增）
#
# 为什么单列一个文件：这条功能的形状是被一个**硬约束**逼出来的 —— 中文命令行参数会让
# 仓颉在进 main 之前就崩（`IllegalArgumentException: Invalid unicode scalar value.`，
# 见 docs/API-NOTES.md 坑 11），所以中文姓名只能走 `--name-file <UTF-8 文件>`。
# 一个"绕开 argv"的输入通道值得有自己的一组闸门：文件带 BOM / 带结尾换行 / 空文件 /
# 只有 BOM / 文件不存在 / 两个选项同时给 / 不认识的参数 …
#
# 隔离性：全部在 build\init-name-check\ 下跑，跑完删掉；**不碰你的正式数据**。
# cwd 也切到那个临时目录，所以第 6 条（用默认目录 data）不会误建 build\data。
#
# 用法（在 server\ 下）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\init-name-check.ps1

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$root  = Split-Path -Parent $here                 # server\
$build = Join-Path $root "build"
$exe   = Join-Path $build "club-server.exe"
if (-not (Test-Path $exe)) {
    Write-Host "找不到 $exe"
    Write-Host "先跑：.\build.ps1"
    exit 2
}

$work = Join-Path $build "init-name-check"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null

$pass = 0; $fail = 0
function Check([string]$name, [bool]$cond, [string]$extra = "") {
    if ($cond) { Write-Host "  ok    $name"; $script:pass++ }
    else       { Write-Host "  FAIL  $name  $extra"; $script:fail++ }
}

# 在 $work 下跑 exe（数据目录相对 cwd；exe 用绝对路径，DLL 挨着 exe 由系统加载）
function Run([string[]]$cmdArgs) {
    Push-Location $work
    try {
        $out = & $exe @cmdArgs 2>&1
        return @{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
    } finally { Pop-Location }
}

# 首任会长的姓名（按 role 取，别依赖成员在 JSON 里的顺序）
function NameOf([string]$dir) {
    $f = Join-Path $work "$dir\db.json"
    if (-not (Test-Path $f)) { return "<没有库>" }
    $j = [IO.File]::ReadAllText($f, [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    $p = $j.members.PSObject.Properties | Where-Object { $_.Value.role -eq 'president' } | Select-Object -First 1
    if ($null -eq $p) { return "<没有会长>" }
    return $p.Value.name
}

function WriteNameFile([string]$text, [string]$file, [bool]$bom, [string]$suffix = "") {
    [IO.File]::WriteAllText((Join-Path $work $file), $text + $suffix, [Text.UTF8Encoding]::new($bom))
}

Write-Host "=== init-admin 会长姓名选项 ==="
Write-Host "  exe $exe"
Write-Host "  临时目录 build\init-name-check\（跑完删除）"
Write-Host ""

# ---------- 1) 老行为：不给姓名选项 ----------
Write-Host "[1] 不给姓名选项 -> 默认「会长」（三参数老用法行为不变）"
$r = Run @('init-admin', '13700000001', 'TestPass2026', 't-default')
Check "退出码 0" ($r.Code -eq 0) "out=$($r.Out)"
Check "姓名默认是「会长」" ((NameOf 't-default') -eq '会长') "name=[$(NameOf 't-default')]"
Check "输出里带上了姓名" ($r.Out -match '已创建首任会长：会长') "out=$($r.Out)"
Check "注册口令那行没被破坏（ops-check 靠它取值）" ($r.Out -match '当前注册口令：[A-Z0-9]+') "out=$($r.Out)"

# ---------- 2) --name（仅 ASCII） ----------
Write-Host ""
Write-Host "[2] --name LiSi（ASCII 姓名直接给）"
$r = Run @('init-admin', '13700000002', 'TestPass2026', 't-ascii', '--name', 'LiSi')
Check "退出码 0" ($r.Code -eq 0) "out=$($r.Out)"
Check "姓名 = LiSi" ((NameOf 't-ascii') -eq 'LiSi') "name=[$(NameOf 't-ascii')]"

# ---------- 3) --name-file（中文走这条） ----------
Write-Host ""
Write-Host "[3] --name-file（中文姓名必须走这里）"
WriteNameFile '张三' 'n3.txt' $false
$r = Run @('init-admin', '13700000003', 'TestPass2026', 't-zh', '--name-file', 'n3.txt')
Check "退出码 0" ($r.Code -eq 0) "out=$($r.Out)"
Check "中文姓名完整写入（UTF-8 往返没坏）" ((NameOf 't-zh') -eq '张三') "name=[$(NameOf 't-zh')]"
Check "输出里的姓名也是中文（终端能看见）" ($r.Out -match '已创建首任会长：张三') "out=$($r.Out)"

# ---------- 4) 文件带 BOM ----------
Write-Host ""
Write-Host "[4] 姓名文件带 UTF-8 BOM（PowerShell Set-Content -Encoding UTF8 的产物）"
WriteNameFile '李四' 'n4.txt' $true
$r = Run @('init-admin', '13700000004', 'TestPass2026', 't-bom', '--name-file', 'n4.txt')
Check "退出码 0" ($r.Code -eq 0) "out=$($r.Out)"
Check "BOM 被剥掉（姓名前没有多余字符）" ((NameOf 't-bom') -eq '李四') "name=[$(NameOf 't-bom')]"

# ---------- 5) 首尾空白 / 结尾换行 ----------
Write-Host ""
Write-Host "[5] 姓名文件带首尾空格与结尾换行 -> 裁掉"
WriteNameFile '  王五  ' 'n5.txt' $false "`r`n"
$r = Run @('init-admin', '13700000005', 'TestPass2026', 't-trim', '--name-file', 'n5.txt')
Check "退出码 0" ($r.Code -eq 0) "out=$($r.Out)"
Check "姓名 = 王五（首尾空白与 CRLF 都裁掉）" ((NameOf 't-trim') -eq '王五') "name=[$(NameOf 't-trim')]"

# ---------- 6) 省掉数据目录、直接给选项 ----------
Write-Host ""
Write-Host "[6] 省掉数据目录直接给选项 -> 用默认目录 data，且不能把选项当成目录名"
$r = Run @('init-admin', '13700000006', 'TestPass2026', '--name-file', 'n3.txt')
Check "退出码 0" ($r.Code -eq 0) "out=$($r.Out)"
Check "写进了默认目录 data\" ((NameOf 'data') -eq '张三') "name=[$(NameOf 'data')]"
Check "没有建出名为 --name-file 的目录" (-not (Test-Path (Join-Path $work '--name-file')))

# ---------- 7) 错误用法与错误输入：都要明确报错 ----------
Write-Host ""
Write-Host "[7] 错误用法 / 错误输入 -> 明确报错，不静默忽略"
[IO.File]::WriteAllText((Join-Path $work 'empty.txt'), "", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $work 'bomonly.txt'), "", [Text.UTF8Encoding]::new($true))

$bad = @(
    @{ n = '不认识的参数';        a = @('init-admin', '13700000007', 'TestPass2026', 't-e1', '--nmae', 'X'); m = '不认识的参数' },
    @{ n = '--name 后面缺值';     a = @('init-admin', '13700000007', 'TestPass2026', 't-e2', '--name');       m = '--name 后面要跟姓名' },
    @{ n = '--name-file 缺值';    a = @('init-admin', '13700000007', 'TestPass2026', 't-e3', '--name-file');  m = '--name-file 后面要跟文件路径' },
    @{ n = '两个选项同时给';      a = @('init-admin', '13700000007', 'TestPass2026', 't-e4', '--name', 'A', '--name-file', 'n3.txt'); m = '只能给一个' },
    @{ n = '文件不存在';          a = @('init-admin', '13700000007', 'TestPass2026', 't-e5', '--name-file', 'nope.txt');  m = '读不到姓名文件' },
    @{ n = '空文件';              a = @('init-admin', '13700000007', 'TestPass2026', 't-e6', '--name-file', 'empty.txt'); m = '姓名文件是空的' },
    @{ n = '只有 BOM 的文件';     a = @('init-admin', '13700000007', 'TestPass2026', 't-e7', '--name-file', 'bomonly.txt'); m = '姓名文件是空的' }
)
foreach ($c in $bad) {
    $r = Run $c.a
    Check "$($c.n) -> 退出码 1" ($r.Code -eq 1) "code=$($r.Code) out=$($r.Out)"
    Check "$($c.n) -> 提示说明了原因" ($r.Out -match [regex]::Escape($c.m)) "out=$($r.Out)"
    Check "$($c.n) -> **没有**建出库（不能半途写库）" (-not (Test-Path (Join-Path $work ($c.a[3] + '\db.json'))))
}

# ---------- 8) 空库才有资格：非空库仍然拒绝 ----------
Write-Host ""
Write-Host "[8] 非空库仍拒绝（加姓名选项不能绕过这条）"
$r = Run @('init-admin', '13700000008', 'TestPass2026', 't-default', '--name', 'Other')
Check "退出码 1" ($r.Code -eq 1) "out=$($r.Out)"
Check "提示「已存在会长账号」" ($r.Out -match '已存在会长账号') "out=$($r.Out)"
Check "原会长的姓名没被改掉" ((NameOf 't-default') -eq '会长') "name=[$(NameOf 't-default')]"

# ---------- 收尾 ----------
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "======================================"
Write-Host "会长姓名选项： PASS $pass / FAIL $fail"
Write-Host "======================================"
if ($fail -gt 0) { exit 1 }
exit 0
