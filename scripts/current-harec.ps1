#requires -Version 5.1
# 選択済みリビジョンのharec.exeのパスを返します。
[CmdletBinding()]
param([switch]$Version)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$LockPath = Join-Path $Root 'upstream.lock.json'
if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { throw '採用版なし。update-upstream.ps1を実行してください。' }
$Lock = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Exe = Join-Path $Root ($Lock.artifact -replace '/', '\')
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
    throw "採用済みコミット $($Lock.commit) のexeが見つかりません。update-upstream.ps1 -Ref $($Lock.commit) で再構築してください。"
}
if ($Version) { & $Exe '-v'; exit $LASTEXITCODE }
Write-Output $Exe
