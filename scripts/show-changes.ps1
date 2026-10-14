#requires -Version 5.1
# 採用中のHare (または指定候補) と公式ソースの差分を表示する。
# 旧バージョンでは監査レポートをその場で生成できる。
[CmdletBinding()]
param(
    [string]$CandidateDir = '',
    [switch]$Open
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Commit = ''
$Version = ''
if ($CandidateDir) {
    $VersionDir = [System.IO.Path]::GetFullPath($CandidateDir)
} else {
    $LockPath = Join-Path $Root 'upstream.lock.json'
    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
        throw '採用済みロックがありません。-CandidateDir を指定しても確認できます。'
    }
    $Lock = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $Commit = $Lock.commit
    $Version = $Lock.ref
    $ExePath = Join-Path $Root ($Lock.artifact -replace '/', '\')
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) { throw "採用された実行ファイルがありません: $ExePath" }
    $VersionDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ExePath))
}
$SourcePath = Join-Path $VersionDir 'source'
$CompiledPath = Join-Path $VersionDir 'compiled'
$StagePath = Join-Path $CompiledPath 'stage'
$AuditDir = Join-Path $CompiledPath 'audit'
$ReportPath = Join-Path $AuditDir 'REPORT.md'
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourcePath 'src') -PathType Container) -or
        -not (Test-Path -LiteralPath (Join-Path $StagePath 'src') -PathType Container)) {
        throw "公式ソースとstageが揃っていません: $VersionDir"
    }
    & (Join-Path $PSScriptRoot 'report-changes.ps1') `
        -SourcePath $SourcePath -StagePath $StagePath -OutputDir $AuditDir `
        -UpstreamCommit $Commit -VersionLabel $Version
}
Write-Host "対象: $VersionDir"
Get-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "`nパッチ: $(Join-Path $AuditDir 'upstream-to-windows.patch')"
Write-Host "JSON: $(Join-Path $AuditDir 'changes.json')"
if ($Open) { Invoke-Item -LiteralPath $ReportPath }
