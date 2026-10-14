#requires -Version 5.1
# 実際のharecを再ビルドせず、差分監査の許可／拒否を確認する。
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('harewin-audit-test-' + [guid]::NewGuid().ToString('N'))
$Source = Join-Path $Temp 'source'
$Stage = Join-Path $Temp 'stage'
$Output = Join-Path $Temp 'audit-valid'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    foreach ($Dir in @((Join-Path $Source 'src'),(Join-Path $Source 'include'),(Join-Path $Stage 'src'),(Join-Path $Stage 'include'))) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText((Join-Path $Source 'src\check.c'), "int original(void) { return 1; }`n", $Utf8)
    [System.IO.File]::WriteAllText((Join-Path $Stage 'src\check.c'), "int original(void) { return 2; }`n", $Utf8)
    [System.IO.File]::WriteAllText((Join-Path $Source 'include\test.h'), "#define VALUE 73`n", $Utf8)
    [System.IO.File]::WriteAllText((Join-Path $Stage 'include\test.h'), "#define VALUE 73`n", $Utf8)
    $OriginalHash = (Get-FileHash -LiteralPath (Join-Path $Source 'src\check.c') -Algorithm SHA256).Hash
    & (Join-Path $Root 'scripts\report-changes.ps1') -SourcePath $Source -StagePath $Stage -OutputDir $Output
    $Changes = Get-Content -LiteralPath (Join-Path $Output 'changes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $ChangedFiles = @($Changes.changed_files)
    if ($ChangedFiles.Count -ne 1 -or $ChangedFiles[0].path -ne 'src/check.c') {
        throw '監査テストの変更ファイル数が想定外です。'
    }
    $Patch = Get-Content -LiteralPath (Join-Path $Output 'upstream-to-windows.patch') -Raw -Encoding UTF8
    if (-not $Patch.Contains('diff --git a/src/check.c b/src/check.c')) {
        throw '監査Gitパッチ形式が不正です。'
    }
    [System.IO.File]::WriteAllText((Join-Path $Stage 'include\test.h'), "#define VALUE 99`n", $Utf8)
    $Rejected = $false
    try {
        & (Join-Path $Root 'scripts\report-changes.ps1') -SourcePath $Source -StagePath $Stage `
            -OutputDir (Join-Path $Temp 'audit-rejected')
    } catch {
        if ($_.Exception.Message -notmatch '想定外のソース改変') { throw }
        $Rejected = $true
    }
    if (-not $Rejected) { throw '想定外のヘッダー変更が拒否されませんでした。' }
    if (-not (Test-Path -LiteralPath (Join-Path $Temp 'audit-rejected\REPORT.md'))) {
        throw '拒否した場合の監査レポートが残っていません。'
    }
    $FinalHash = (Get-FileHash -LiteralPath (Join-Path $Source 'src\check.c') -Algorithm SHA256).Hash
    if ($OriginalHash -ne $FinalHash) { throw '監査で元ソースが変更されました。' }
    Write-Host 'PASS: source不変・Git patch生成・想定外の変更を拒否'
} finally {
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Force -Recurse }
}
