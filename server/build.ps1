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

param(
    [string]$CangjieHome = "D:\Cangjie",
    [string]$Stdx        = "E:\cangjie\stdx\windows_x86_64_cjnative\static\stdx",
    [string]$Vendor      = "",
    [switch]$NoDll,
    [switch]$SkipFrameworkCheck
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$src  = Join-Path $root "src"
$out  = Join-Path $root "build"
if ([string]::IsNullOrEmpty($Vendor)) { $Vendor = Join-Path $root "third_party\qingzhou" }
New-Item -ItemType Directory -Force -Path $out | Out-Null

$Cjc        = Join-Path $CangjieHome "bin\cjc.exe"
$RuntimeDir = Join-Path $CangjieHome "runtime\lib\windows_x86_64_cjnative"

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

& $Cjc @fw @app --import-path $Stdx -L $Stdx @libs -lcrypt32 -Woff unused -o $exe
if ($LASTEXITCODE -ne 0) { throw "编译失败 (exit $LASTEXITCODE)" }
Write-Host "[build] 编译通过"

if (-not $NoDll) {
    # 部署文件集（..\docs\deploy-windows-verify.md §2）：exe + 4 个 DLL。
    # 缺 libcangjie-runtime.dll 会启动即失败；缺两个 OpenSSL 3 DLL 则 crypto 运行时才报错。
    # 前两个来自仓颉 SDK；后两个来自**内置的**轻舟 deps（原先指仓库外，N-20 一并收进来）。
    $dlls = @(
        @{ n = "libcangjie-runtime.dll"; d = $RuntimeDir },
        @{ n = "libboundscheck.dll";     d = $RuntimeDir },
        @{ n = "libcrypto-3-x64.dll";    d = Join-Path $Vendor "deps\openssl" },
        @{ n = "libssl-3-x64.dll";       d = Join-Path $Vendor "deps\openssl" }
    )
    foreach ($x in $dlls) {
        $p = Join-Path $x.d $x.n
        if (-not (Test-Path $p)) { throw "缺少依赖 DLL：$p" }
        Copy-Item $p $out -Force
    }
    Write-Host "[build] 已复制 4 个依赖 DLL 到 build\"
}
