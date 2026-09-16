# 社团管理工具 · 服务端构建脚本
#
# 编译路径（已在 ..\docs\HANDOFF.md §2 / 上层的 cangjie-upstream\qingzhou-tls-verification.md §1.2 实测过）：
#   cjc 1.1.3 + stdx 1.1.3.1（静态）+ **仓库内置的**轻舟源码，**同一次调用、同一个包**。
#
# 轻舟已内置在 third_party\qingzhou（2026-09-15 迁移，对应 docs/code-review.md 的 N-20）：
#   原先按**机器本地路径** E:\cangjie\qingzhou 取框架源码，且只查"在不在"、不查版本 ——
#   换台机器（或本地对轻舟 pull 一次）就会编到另一个版本的框架，**照样 BUILD SUCCESSFUL**，
#   而 server\src\fw_rbac*.cj 是跟着上游文件走的适配，于是变成"框架换了、适配没换"的静默漂移。
#   现在：源码在仓库里、版本记在 third_party\qingzhou\UPSTREAM_COMMIT（**唯一出处**）、
#   内容由 MANIFEST.sha256 逐字节校验；内置框架被改动/增删会**当场拒绝构建**。
#
# 为什么不用 cjpm：轻舟自己的 examples/*.cj 都写 `package qingzhou`，
# 框架既定用法就是与框架源码一起编译（build.sh 也是这么做的）。
#
# 用法：
#   .\build.ps1                      校验内置框架 + 编译 + 复制依赖 DLL 到 build\
#   .\build.ps1 -NoDll               只编译（本机已装好 DLL 时更快）
#   .\build.ps1 -SkipFrameworkCheck  跳过内置框架的内容校验（**仅**在有意改动内置框架时用）
#
# 换一台机器：cjc 与 stdx 的位置**不再写死**，脚本自动探测（显式传参 > 环境变量 > 常见位置 > PATH）：
#   .\build.ps1 -CangjieHome <SDK目录> -Stdx <...\windows_x86_64_cjnative\static\stdx>
#   或设环境变量 CANGJIE_HOME / CANGJIE_STDX
#   （**不需要**仓库外的轻舟：框架已内置在 third_party\qingzhou）

param(
    [string]$CangjieHome = "",
    [string]$Stdx        = "",
    [string]$Vendor      = "",
    [string]$OpenSslDir  = "",
    [switch]$NoDll,
    [switch]$SkipFrameworkCheck
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$src  = Join-Path $root "src"
$out  = Join-Path $root "build"
if ([string]::IsNullOrEmpty($Vendor)) { $Vendor = Join-Path $root "third_party\qingzhou" }
New-Item -ItemType Directory -Force -Path $out | Out-Null

# ── 工具链解析（2026-09-16：为了「换一台机器也能编」） ────────────────────
# 原先这两个路径写死成本机的 D:\Cangjie 与 E:\cangjie\stdx\...，别人 clone 下来必然报
# 「找不到编译器」/「找不到 stdx」。现在按下面的顺序找，并把**解法**写在报错里。
function Resolve-CangjieHome([string]$explicit) {
    $cands = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrEmpty($explicit)) { [void]$cands.Add($explicit) }
    if ($env:CANGJIE_HOME) { [void]$cands.Add($env:CANGJIE_HOME) }
    # 注意顺序：**常见安装位置优先于 PATH**。本机 PATH 上的 cjc 是 cjenv 的 1.0.5 shim，
    # 若优先取它，就会与 stdx 1.1.3.1 串台（症状是 LLVM ERROR: Broken module found，见下方注释）。
    # 所以 PATH 只作最后兜底。
    foreach ($d in @("D:\Cangjie", "C:\Cangjie", "E:\Cangjie",
                     (Join-Path $env:USERPROFILE "Cangjie"),
                     (Join-Path $env:ProgramFiles "Cangjie"))) { [void]$cands.Add($d) }
    $onPath = Get-Command cjc -ErrorAction SilentlyContinue
    if ($null -ne $onPath) { [void]$cands.Add((Split-Path (Split-Path $onPath.Source) -Parent)) }
    # 先把"真实存在"的候选按优先级收集起来
    $found = New-Object System.Collections.ArrayList
    foreach ($c in $cands) {
        if (-not [string]::IsNullOrEmpty($c) -and (Test-Path (Join-Path $c "bin\cjc.exe"))) {
            $rp = (Resolve-Path $c).Path
            if (-not $found.Contains($rp)) { [void]$found.Add($rp) }
        }
    }
    # 再**按版本挑**：优先本项目基线的 1.1.x。
    # 为什么不能只看位置：cjenv 会把全局 CANGJIE_HOME 改写成它自己的 SDK（本机是 1.0.5），
    # 而 PATH 上的 cjc 也可能是那个 shim —— 拿它去配 stdx 1.1.3.1 会串台
    # （症状 LLVM ERROR: Broken module found，见下面钉死工具链那段注释）。
    foreach ($c in $found) {
        $v = (& (Join-Path $c "bin\cjc.exe") --version 2>&1 | Select-Object -First 1)
        if ("$v" -match '1\.1\.') { return $c }
    }
    if ($found.Count -gt 0) { return $found[0] }
    return ""
}

function Resolve-Stdx([string]$explicit, [string]$sdkHome) {
    $cands = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrEmpty($explicit)) { [void]$cands.Add($explicit) }
    if ($env:CANGJIE_STDX) { [void]$cands.Add($env:CANGJIE_STDX) }
    $roots = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrEmpty($sdkHome)) {
        [void]$roots.Add((Split-Path $sdkHome -Parent))
        [void]$roots.Add($sdkHome)
    }
    foreach ($r in @("E:\cangjie", "D:\cangjie", "C:\cangjie", (Join-Path $env:USERPROFILE "cangjie"))) { [void]$roots.Add($r) }
    foreach ($c in $cands) { if (Test-Path $c) { return (Resolve-Path $c).Path } }
    foreach ($r in $roots) {
        foreach ($sub in @("stdx\windows_x86_64_cjnative\static\stdx", "stdx\static\stdx")) {
            $p = Join-Path $r $sub
            if (Test-Path $p) { return (Resolve-Path $p).Path }
        }
    }
    return ""
}

# 显式传参传错时**不能静默忽略**：否则用户以为自己在用指定 SDK，实际用的是探测到的另一个。
$explicitHome = $CangjieHome
$explicitStdx = $Stdx
$CangjieHome = Resolve-CangjieHome $CangjieHome
if (-not [string]::IsNullOrEmpty($explicitHome) -and
    -not (Test-Path (Join-Path $explicitHome "bin\cjc.exe"))) {
    Write-Warning "-CangjieHome 指定的目录里没有 bin\cjc.exe：$explicitHome（已忽略，改用自动探测结果）"
}
if ([string]::IsNullOrEmpty($CangjieHome)) {
    throw ("找不到仓颉 SDK（cjc.exe）—— 这是**编译**服务端的前提。`n" +
           "  ① 只想要能跑的服务端（不编译）：拿一份**部署包**即可 —— `n" +
           "     server\dist\club-server\ 里的 exe + 4 个 DLL + 启动脚本，同平台直接可运行；`n" +
           "     或在本机已有构建的机器上跑 build-package.ps1 生成后拷过去。`n" +
           "  ② 要自己编译：装好「仓颉 SDK + stdx」两个包（本机是 cjc 1.1.3 / stdx 1.1.3.1，`n" +
           "     版本见 README『环境事实』），然后任选其一告诉我路径：`n" +
           "     · .\build.ps1 -CangjieHome <SDK目录> -Stdx <stdx目录>`n" +
           "     · 设环境变量 CANGJIE_HOME 与 CANGJIE_STDX`n" +
           "     · 把 cjc.exe 放进 PATH`n" +
           "  下载：https://cangjie-lang.cn/download")
}
$Stdx = Resolve-Stdx $Stdx $CangjieHome
if (-not [string]::IsNullOrEmpty($explicitStdx) -and -not (Test-Path $explicitStdx)) {
    Write-Warning "-Stdx 指定的目录不存在：$explicitStdx（已忽略，改用自动探测结果）"
}
if ([string]::IsNullOrEmpty($Stdx)) {
    throw ("找不到 stdx 的静态库（libstdx*.a）。`n" +
           "  cjc 与 stdx 是**两个包**：装了编译器还要单独装 stdx（本机在 E:\cangjie\stdx\...）。`n" +
           "  找到后：.\build.ps1 -Stdx <...\windows_x86_64_cjnative\static\stdx>，或设 `$env:CANGJIE_STDX。")
}
Write-Host "[build] 工具链：cjc=$CangjieHome"
Write-Host "[build]          stdx=$Stdx"
# 显式传了 A、实际用了 B 时必须说清楚（例如显式指了 cjenv 的 1.0.5，按版本被跳过）。
function Test-SameDir([string]$a, [string]$b) {
    if ([string]::IsNullOrEmpty($a) -or [string]::IsNullOrEmpty($b)) { return $true }
    $ra = (Resolve-Path $a -ErrorAction SilentlyContinue)
    $rb = (Resolve-Path $b -ErrorAction SilentlyContinue)
    if ($null -eq $ra -or $null -eq $rb) { return $true }
    return ($ra.Path -eq $rb.Path)
}
if (-not (Test-SameDir $explicitHome $CangjieHome)) {
    Write-Warning "-CangjieHome 指定的是 $explicitHome，实际使用 $CangjieHome（前者版本不是 1.1.x，按基线跳过）"
}
if (-not (Test-SameDir $explicitStdx $Stdx)) {
    Write-Warning "-Stdx 指定的是 $explicitStdx，实际使用 $Stdx"
}

$Cjc        = Join-Path $CangjieHome "bin\cjc.exe"
$RuntimeDir = Join-Path $CangjieHome "runtime\lib\windows_x86_64_cjnative"

$ver = (& $Cjc --version 2>&1 | Select-Object -First 1)
Write-Host "[build]          cjc 版本：$ver"
# 版本不对时**不要**让它编到一半才炸：cjc 与 stdx 版本串台的症状是
#   LLVM ERROR: Broken module found … @llvm.cj.get.vtable.func、opt.exe 崩溃
# 极易被当成编译器 bug。这里提前讲清楚，并给出解法。
if ("$ver" -notmatch '1\.1\.') {
    Write-Warning ("本机 cjc 是 '$ver'，而本项目基线是 1.1.3 + stdx 1.1.3.1（见 README『环境事实』）。`n" +
                   "    cjc 与 stdx 版本不一致时，典型症状是编译中途 LLVM ERROR: Broken module found / opt 崩溃。`n" +
                   "    处置：装 1.1.3 的 SDK 与 stdx 1.1.3.1，再用 -CangjieHome / -Stdx 显式指过去。")
}
if (-not (Test-Path $Cjc))  { throw "找不到编译器：$Cjc" }
if (-not (Test-Path $Stdx)) { throw "找不到 stdx：$Stdx" }
$VendorSrc = Join-Path $Vendor "src"
if (-not (Test-Path $VendorSrc)) {
    throw "找不到内置的轻舟源码：$VendorSrc —— 本项目把框架内置在 server\third_party\qingzhou，请确认该目录已随仓库检出。"
}

# ── 内置框架的版本与完整性（N-20） ──────────────────────────────────────
$upCommitFile = Join-Path $Vendor "UPSTREAM_COMMIT"
$upCommit = if (Test-Path $upCommitFile) { (Get-Content $upCommitFile -Encoding UTF8 | Select-Object -First 1).Trim() } else { "未知" }
$upShort  = $upCommit.Substring(0, [Math]::Min(7, $upCommit.Length))

if (-not $SkipFrameworkCheck) {
    $mf = Join-Path $Vendor "MANIFEST.sha256"
    if (-not (Test-Path $mf)) { throw "内置框架缺少 MANIFEST.sha256：$mf" }
    $bad = New-Object System.Collections.ArrayList
    $listed = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($line in (Get-Content $mf -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $m = [regex]::Match($line, '^([0-9a-f]{64})\s\s(.+)$')
        if (-not $m.Success) { throw "MANIFEST.sha256 行格式不对：$line" }
        $want = $m.Groups[1].Value
        $rel  = $m.Groups[2].Value.Trim()
        [void]$listed.Add($rel)
        $p = Join-Path $Vendor ($rel -replace '/', '\')
        if (-not (Test-Path $p)) { [void]$bad.Add("缺失 $rel"); continue }
        if ((Get-FileHash $p -Algorithm SHA256).Hash.ToLower() -ne $want) { [void]$bad.Add("内容变了 $rel") }
    }
    foreach ($f in (Get-ChildItem $VendorSrc -Filter *.cj -File)) {
        if (-not $listed.Contains("src/$($f.Name)")) { [void]$bad.Add("多出未登记的源文件 src/$($f.Name)") }
    }
    if ($bad.Count -gt 0) {
        throw ("内置轻舟与 MANIFEST.sha256 不一致：`n  - " + ($bad -join "`n  - ") + "`n" +
               "内置框架**不应被本地修改**：我们的改动一律放 server\src\fw_rbac*.cj。`n" +
               "若确实是有意的更新，请跑 server\third_party\qingzhou\update-manifest.ps1，" +
               "并在提交信息里说明为什么改了内置框架。")
    }
}

# ── 把工具链钉死（**不要删**） ───────────────────────────────────────────
# 本机装了 cjenv（另一个项目：仓颉 SDK 版本管理器），它会改写 CANGJIE_HOME 并把
# 自己的 shims 塞进 PATH。一旦 CANGJIE_HOME 指向别的 SDK（例如 1.0.5），
# 而 PATH 里的 cjc 仍是 D:\Cangjie 的 1.1.3，就会出现
#   "前端 1.1.3 + 后端 LLVM 1.0.5" 的串台：
#   LLVM ERROR: Broken module found … @llvm.cj.get.vtable.func … opt.exe 崩溃
# 这类错误看起来像编译器 bug，实际只是环境串台。这里显式指定本次编译用的工具链。
$env:CANGJIE_HOME = $CangjieHome
$env:PATH = (Join-Path $CangjieHome "bin") + ";" +
            (Join-Path $CangjieHome "third_party\llvm\bin") + ";" + $env:PATH

$libs = (Get-ChildItem "$Stdx\libstdx*.a" | ForEach-Object { "-l:$($_.Name)" })

# 排除框架自己的入口与测试：main.cj 有 main()、unit_tests.cj / manual_runner.cj 是框架自测，
# 我们的 main.cj 提供入口。这与上层 cangjie-upstream\qingzhou-tls-verification.md 里编译 examples/https.cj 的命令一致。
#
# store.cj / rbac.cj（2026-09-14，轻舟升级到 3ea387e 后新增）：上游这两张文件依赖外部 CangDB，
# 而 CangDB 的仓库只有 README、没有任何代码，`import cangdb.*` 编译不过。
# 我们用自己的适配版代替（数据层换成文件存储、响应换用我们的错误格式）：
#   server/src/fw_rbac_store.cj  -> RbacStore / UserRow / RoleRow / PermRow
#   server/src/fw_rbac.cj        -> requirePermission
# 所以这里要排除框架原版，否则 RbacStore 会重名冲突。拿到可用的 CangDB 后删掉那两个适配文件、
# 把 'store.cj' / 'rbac.cj' 从这个列表里去掉即可回到上游实现。
# 注意：内置目录里**保留**这两张上游文件（便于对照），被排除的只是"不参与编译"。
$fw = Get-ChildItem "$VendorSrc\*.cj" |
      Where-Object { $_.Name -notin @('main.cj', 'unit_tests.cj', 'manual_runner.cj', 'store.cj', 'rbac.cj') } |
      ForEach-Object { $_.FullName }

$app = Get-ChildItem "$src\*.cj" | ForEach-Object { $_.FullName }
if ($app.Count -eq 0) { throw "没有找到服务端源码：$src" }

$exe = Join-Path $out "club-server.exe"
Write-Host "[build] 框架：轻舟 $upShort（内置 third_party\qingzhou，$($fw.Count) 个文件参与编译）"
Write-Host "[build] 服务端 $($app.Count) 个文件 -> $exe"

# 目标 exe 被上一个进程占着时，ld.lld 只丢一句 "failed to write the output file: Permission denied"，
# 看上去像 SDK/权限问题，实际是服务端没停干净。先自查一遍，给能直接照做的提示。
if (Test-Path $exe) {
    try {
        $fs = [IO.File]::Open($exe, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $fs.Close()
    } catch {
        throw ("编译输出被占用：$exe" + [Environment]::NewLine +
               "  原因：还有 club-server.exe 在运行，Windows 不允许覆盖正在执行的 exe。" + [Environment]::NewLine +
               "  处置：Get-Process club-server -ErrorAction SilentlyContinue | Stop-Process -Force" + [Environment]::NewLine +
               "        然后重新执行 .\build.ps1")
    }
}

& $Cjc @fw @app --import-path $Stdx -L $Stdx @libs -lcrypt32 -Woff unused -o $exe
if ($LASTEXITCODE -ne 0) { throw "编译失败 (exit $LASTEXITCODE)" }
Write-Host "[build] 编译通过"

# ── OpenSSL 3 的两个 DLL 从哪来 ─────────────────────────────────────────
# 它们是**运行时 dlopen** 用的（不在 exe 导入表里），6.5 MB 二进制，**不随仓库提交**。
# 解析顺序（每一步都会打印实际用的是哪一份，不会静默）：
#   1) 内置目录 third_party\qingzhou\deps\openssl（放了就用）
#   2) -OpenSslDir <目录>（给了就**只用它**，不再回退）
#   3) Git for Windows 自带的 mingw64\bin（本项目本来就依赖它的 openssl CLI；实测 3.5.7）
# 都找不到 → 报错退出并写清两种处置。详见 third_party\qingzhou\deps\openssl\README.md。
function Test-OpenSslDir([string]$d) {
    if ([string]::IsNullOrEmpty($d)) { return $false }
    if (-not (Test-Path (Join-Path $d "libcrypto-3-x64.dll"))) { return $false }
    if (-not (Test-Path (Join-Path $d "libssl-3-x64.dll"))) { return $false }
    return $true
}

function Resolve-OpenSslDir([string]$VendorDir, [string]$Explicit) {
    $inRepo = Join-Path $VendorDir "deps\openssl"
    if (-not [string]::IsNullOrEmpty($Explicit)) {
        if (Test-OpenSslDir $Explicit) { return (Resolve-Path $Explicit).Path }
        throw "-OpenSslDir 里没有 libcrypto-3-x64.dll / libssl-3-x64.dll：$Explicit"
    }
    if (Test-OpenSslDir $inRepo) { return (Resolve-Path $inRepo).Path }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $git) {
        $gitRoot = Split-Path (Split-Path $git.Source) -Parent
        foreach ($cand in @((Join-Path $gitRoot "mingw64\bin"), (Join-Path $gitRoot "usr\bin"))) {
            if (Test-OpenSslDir $cand) { return (Resolve-Path $cand).Path }
        }
    }
    throw ("找不到 OpenSSL 3 的两个 DLL（libcrypto-3-x64.dll / libssl-3-x64.dll）。`n" +
           "  已按顺序找过：1) $inRepo   2) -OpenSslDir 参数   3) Git for Windows 的 mingw64\bin`n" +
           "  两种处置（任选其一）：`n" +
           "    A) 从 Git for Windows 拷一份到内置目录（推荐，版本已核对 3.5.7）：`n" +
           "         Copy-Item `"<Git>\mingw64\bin\libcrypto-3-x64.dll`" `"$inRepo`"`n" +
           "         Copy-Item `"<Git>\mingw64\bin\libssl-3-x64.dll`"    `"$inRepo`"`n" +
           "    B) 用 -OpenSslDir <目录> 指向任意一份 OpenSSL 3 x64（该目录须同时含这两个 DLL）。`n" +
           "  说明见 third_party\qingzhou\deps\openssl\README.md。")
}

if (-not $NoDll) {
    # 部署文件集（..\docs\deploy-windows-verify.md §2）：exe + 4 个 DLL。
    # 缺 libcangjie-runtime.dll 会启动即失败；缺两个 OpenSSL 3 DLL 则 crypto 运行时才报错。
    # 前两个来自仓颉 SDK（装了编译器就有）；后两个按 Resolve-OpenSslDir 的顺序解析。
    $ossl = Resolve-OpenSslDir $Vendor $OpenSslDir
    Write-Host "[build] OpenSSL DLL 来源：$ossl"
    # N-23：与 EXPECTED.sha256 比对（**告警不拒绝**）。这两个 DLL 决定部署包的密码哈希与 TLS
    # 实现，却来自"谁放了一份 / Git 升级到哪个版本"这种不受控位置 —— 换机器就可能静默换掉。
    $expFile = Join-Path $Vendor "deps\openssl\EXPECTED.sha256"
    if (Test-Path $expFile) {
        $exp = @{}
        foreach ($ln in (Get-Content $expFile -Encoding UTF8)) {
            if ($ln -match '^\s*#|^\s*$') { continue }
            $m = [regex]::Match($ln, '^([0-9a-f]{64})\s+(.+)$')
            if ($m.Success) { $exp[$m.Groups[2].Value.Trim()] = $m.Groups[1].Value }
        }
        foreach ($n in @("libcrypto-3-x64.dll", "libssl-3-x64.dll")) {
            $p = Join-Path $ossl $n
            $got = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
            $ver = (Get-Item $p).VersionInfo.FileVersion
            if ($exp.ContainsKey($n) -and $exp[$n] -ne $got) {
                Write-Host "[build] ⚠ OpenSSL 与 EXPECTED.sha256 不一致：$n" -ForegroundColor Yellow
                Write-Host "[build]    期望 $($exp[$n])" -ForegroundColor Yellow
                Write-Host "[build]    实际 $got（版本 $ver，来自 $ossl）" -ForegroundColor Yellow
                Write-Host "[build]    这会把不同的密码学实现打进部署包；有意更换请改 deps\openssl\EXPECTED.sha256" -ForegroundColor Yellow
            } else {
                Write-Host "[build]   $n  $ver  $($got.Substring(0, 16))…  与 EXPECTED 一致"
            }
        }
    } else {
        Write-Host "[build] 提示：deps\openssl\EXPECTED.sha256 不存在 —— 跳过运行时库比对（N-23）"
    }
    $dlls = @(
        @{ n = "libcangjie-runtime.dll"; d = $RuntimeDir },
        @{ n = "libboundscheck.dll";     d = $RuntimeDir },
        @{ n = "libcrypto-3-x64.dll";    d = $ossl },
        @{ n = "libssl-3-x64.dll";       d = $ossl }
    )
    foreach ($x in $dlls) {
        $p = Join-Path $x.d $x.n
        if (-not (Test-Path $p)) { throw "缺少依赖 DLL：$p" }
        Copy-Item $p $out -Force
    }
    Write-Host "[build] 已复制 4 个依赖 DLL 到 build\"
}
