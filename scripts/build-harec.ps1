#requires -Version 5.1
# ハッシュで固定されたソースのコピーからWindowsネイティブharecを構築。
# upstreamのGitリポジトリ／ファイルは一切編集しません。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [Parameter(Mandatory = $true)][string]$VersionLabel,
    [string]$UpstreamCommit = '',
    [string]$GccPath = 'C:\msys64\ucrt64\bin\gcc.exe'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Stage = Join-Path $OutputRoot 'stage'
$Bin = Join-Path $OutputRoot 'bin'
$Exe = Join-Path $Bin 'harec.exe'
$Shim = Join-Path $Root 'compat\harewin-compat.c'
$CompatHeader = Join-Path $Root 'compat\harewin-compat.h'

function Run-Native([string]$Program, [string[]]$Arguments) {
    Write-Host ('実行 > ' + $Program + ' ' + ($Arguments -join ' '))
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "実行失敗: $Program (終了コード $LASTEXITCODE)" }
}
if ($env:OS -ne 'Windows_NT') { throw 'Windows PowerShell上で実行してください。' }
if (-not (Test-Path -LiteralPath $GccPath -PathType Leaf)) { throw "GCCなし: $GccPath" }
$Triplet = ((& $GccPath '-dumpmachine') -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $Triplet -ne 'x86_64-w64-mingw32') {
    throw "x86_64-w64-mingw32 GCCが必要です: $Triplet"
}
if ($VersionLabel -notmatch '^[A-Za-z0-9_.+\-]{1,100}$') { throw '不正なVersionLabel' }
foreach ($File in @('src\main.c','src\check.c','src\util.c','include\util.h')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourcePath $File) -PathType Leaf)) {
        throw "harecソースの構成が想定外: $File"
    }
}
New-Item -Force -ItemType Directory -Path $Bin | Out-Null
Write-Host 'Windowsホスト互換層を単体テストします。'
$SmokeExe = Join-Path $Bin 'compat-smoke.exe'
Run-Native $GccPath @('-std=c11','-O0','-Wall','-Wextra','-Werror','-I', (Join-Path $Root 'compat'), '-o', $SmokeExe, (Join-Path $Root 'tests\compat-smoke.c'), $Shim)
Run-Native $SmokeExe @()

if (Test-Path -LiteralPath $Stage) { throw "出力stageは新規である必要があります: $Stage" }
New-Item -ItemType Directory -Path $Stage | Out-Null
Copy-Item -LiteralPath (Join-Path $SourcePath 'src') -Destination (Join-Path $Stage 'src') -Recurse
Copy-Item -LiteralPath (Join-Path $SourcePath 'include') -Destination (Join-Path $Stage 'include') -Recurse

# 一意に特定できた関数だけ作業コピーに変更を加える。 upstreamは無改変。
$CheckPath = Join-Path $Stage 'src\check.c'
$Text = [System.IO.File]::ReadAllText($CheckPath)
$Pattern = '(?ms)^char \*\r?\ngen_typename\(const struct type \*type\)\r?\n\{.*?^\}\r?\n'
$FoundBlocks = [regex]::Matches($Text, $Pattern)
if ($FoundBlocks.Count -ne 1 -or -not $FoundBlocks[0].Value.Contains('open_memstream')) {
    throw 'gen_typename/open_memstream が予想と違います。アップデート非互換として安全に中止します。'
}
$Replacement = [System.IO.File]::ReadAllText((Join-Path $Root 'compat\gen_typename-windows.c.txt'))
$Updated = $Text.Substring(0, $FoundBlocks[0].Index) + $Replacement + $Text.Substring($FoundBlocks[0].Index + $FoundBlocks[0].Length)
$Utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($CheckPath, $Updated, $Utf8)

# 公式versionを偽装せず、実際に採用したref/commitを表示する。
$GeneratedConfig = Join-Path $OutputRoot 'harewin-build-config.h'
$ConfigText = "#ifndef HAREWIN_BUILD_CONFIG_H`n#define HAREWIN_BUILD_CONFIG_H`n#define VERSION `"$VersionLabel`"`n#define DEFAULT_TARGET `"x86_64`"`n#endif`n"
[System.IO.File]::WriteAllText($GeneratedConfig, $ConfigText, $Utf8)
$Sources = @(Get-ChildItem -LiteralPath (Join-Path $Stage 'src') -Filter '*.c' -File | Sort-Object Name | ForEach-Object { $_.FullName })
if ($Sources.Count -lt 15) { throw "harecのCファイル数が想定外: $($Sources.Count)" }
$GccArgs = @(
    '-std=c11','-O0','-g','-Wall','-Wextra','-Wno-unused-parameter',
    '-D_GNU_SOURCE','-D_WIN32_WINNT=0x0601','-D__USE_MINGW_ANSI_STDIO=1',
    '-I',(Join-Path $Stage 'include'), '-I',(Join-Path $Root 'compat'),
    '-include',$GeneratedConfig,'-include',$CompatHeader,
    '-o',$Exe
) + $Sources + @($Shim,'-lm')
# コンパイル前に変更をレポート化する。失敗候補でもレポートが残る。
# 監査対象は公式archiveのsrc/includeとstageのsrc/include。予期せぬ改変ならここで停止。
& (Join-Path $PSScriptRoot 'report-changes.ps1') `
    -SourcePath $SourcePath -StagePath $Stage -OutputDir (Join-Path $OutputRoot 'audit') `
    -UpstreamCommit $UpstreamCommit -VersionLabel $VersionLabel -GccPath $GccPath `
    -GeneratedConfigPath $GeneratedConfig -BuildArgs $GccArgs
Write-Host "公式ソースのstageコピーからharec.exeをビルドします（Cファイル数 $($Sources.Count)）。"
Run-Native $GccPath $GccArgs
# PEの取り込みDLLを調べ、MSYS POSIXランタイム依存の混入を拒否する。
$Objdump = Join-Path (Split-Path -Parent $GccPath) 'objdump.exe'
if (-not (Test-Path -LiteralPath $Objdump -PathType Leaf)) { throw "objdump.exeなし: $Objdump" }
$Imports = @(& $Objdump '-p' $Exe)
if ($LASTEXITCODE -ne 0) { throw 'harec.exeのPE依存DLLを確認できませんでした。' }
if (($Imports -join "`n") -match '(?i)DLL Name:\s*(msys-2\.0|cygwin1)\.dll') {
    throw 'harec.exeにPOSIXランタイムDLLが混入しています。'
}
Write-Host '依存DLLを確認（MSYS/Cygwinランタイムなし）。'
Run-Native $Exe @('-v')
$Ir = Join-Path $Bin 'athena3.ssa'
Run-Native $Exe @('-o',$Ir,(Join-Path $Root 'src\athena3.ha'))
if (-not (Test-Path -LiteralPath $Ir -PathType Leaf) -or (Get-Item -LiteralPath $Ir).Length -eq 0) {
    throw 'HareソースからQBE IRが生成されませんでした。'
}
Write-Host "harecのホスト側ビルド成功（まだ採用前）: $Exe"
