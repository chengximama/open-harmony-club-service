# 重新生成内置轻舟的 MANIFEST.sha256
#
# 什么时候用：**有意**修改/增删了 server\third_party\qingzhou 下的文件之后。
# 平时不要跑 —— build.ps1 会校验清单，就是为了让"内置框架被本地改动"这件事**当场暴露**，
# 而不是变成一次静默漂移（见 docs/code-review.md 的 N-20）。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\update-manifest.ps1

$ErrorActionPreference = "Stop"

$vendor = $PSScriptRoot
$mf = Join-Path $vendor "MANIFEST.sha256"

$lines = New-Object System.Collections.ArrayList
foreach ($f in (Get-ChildItem $vendor -Recurse -File | Where-Object { $_.Name -ne 'MANIFEST.sha256' })) {
    $rel = $f.FullName.Substring($vendor.Length + 1).Replace('\', '/')
    $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
    [void]$lines.Add("$h  $rel")
}
$sorted = ($lines | Sort-Object { $_.Split('  ')[1] })
[System.IO.File]::WriteAllText($mf, (($sorted -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))

Write-Host "[manifest] 已重新生成：$mf"
Write-Host "[manifest] 共 $($sorted.Count) 个文件"
Write-Host "[manifest] 提醒：若这不是有意改动，请用 git status / git diff 看看内置框架被动过什么。"
