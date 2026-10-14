#requires -Version 5.1
# 採用候補を検証するゲート。Cホストを使う小さなHare ABI回帰ケース。
[CmdletBinding()]
param(
    [string]$HarecPath = '',
    [string]$QbePath = '',
    [string]$GccPath = 'C:\msys64\ucrt64\bin\gcc.exe',
    [string]$OutputDir = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $QbePath -and $env:HAREWIN_QBE) { $QbePath = $env:HAREWIN_QBE }
if (-not $QbePath) { throw '-QbePath または HAREWIN_QBE を指定してください。' }
if (-not $HarecPath) {
    $LockFile = Join-Path $Root 'upstream.lock.json'
    if (-not (Test-Path -LiteralPath $LockFile)) { throw '採用版がありません。update-upstream.ps1を実行してください。' }
    $Lock = Get-Content -LiteralPath $LockFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $HarecPath = Join-Path $Root ($Lock.artifact -replace '/', '\')
}
if (-not $OutputDir) { $OutputDir = Join-Path $Root 'build\manual-test' }
foreach ($Tool in @($HarecPath,$QbePath,$GccPath)) {
    if (-not (Test-Path -LiteralPath $Tool -PathType Leaf)) { throw "実行ファイルがありません: $Tool" }
}
New-Item -Force -ItemType Directory -Path $OutputDir | Out-Null
function Run-Native([string]$Program, [string[]]$Arguments) {
    Write-Host ('実行 > ' + $Program + ' ' + ($Arguments -join ' '))
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "実行失敗: $Program (終了コード $LASTEXITCODE)" }
}
$Ir = Join-Path $OutputDir 'athena3.ssa'
$Asm = Join-Path $OutputDir 'athena3.s'
$Obj = Join-Path $OutputDir 'athena3.obj'
$Exe = Join-Path $OutputDir 'hare-abi.exe'
Write-Host '[1/2] Hare → QBE → COFF → PE → アテナ3号のテレメトリ'
Run-Native $HarecPath @('-o',$Ir,(Join-Path $Root 'src\athena3.ha'))
Run-Native $QbePath @('-t','amd64_win','-o',$Asm,$Ir)
Run-Native $GccPath @('-c','-o',$Obj,$Asm)
Run-Native $GccPath @('-std=c11','-Wall','-Wextra','-o',$Exe,(Join-Path $Root 'src\host.c'),$Obj)
Run-Native $Exe @()
$Objdump = Join-Path (Split-Path -Parent $GccPath) 'objdump.exe'
if (-not (Test-Path -LiteralPath $Objdump -PathType Leaf)) { throw "objdump.exeなし: $Objdump" }
$Imports = @(& $Objdump '-p' $Exe)
if ($LASTEXITCODE -ne 0) { throw '生成EXEのPE依存DLLを確認できませんでした。' }
if (($Imports -join "`n") -match '(?i)DLL Name:\s*(msys-2\.0|cygwin1)\.dll') {
    throw '生成EXEにPOSIXランタイムDLLが混入しています。'
}

# Cerune Issue #92：第5引数f32のWindows ABI lowering回帰。
Write-Host '[2/2] QBE Windows ABI: 第5引数f32/f64のアセンブル検証'
$FloatAsm = Join-Path $OutputDir 'qbe-float-arg5.s'
$FloatObj = Join-Path $OutputDir 'qbe-float-arg5.obj'
Run-Native $QbePath @('-t','amd64_win','-o',$FloatAsm,(Join-Path $Root 'tests\qbe-float-arg5.ssa'))
Run-Native $GccPath @('-c','-o',$FloatObj,$FloatAsm)
$DoubleAsm = Join-Path $OutputDir 'qbe-double-arg5.s'
$DoubleObj = Join-Path $OutputDir 'qbe-double-arg5.obj'
Run-Native $QbePath @('-t','amd64_win','-o',$DoubleAsm,(Join-Path $Root 'tests\qbe-double-arg5.ssa'))
Run-Native $GccPath @('-c','-o',$DoubleObj,$DoubleAsm)
Write-Host 'PASS: harecホスト・Hare Win64整数ABI・QBE stack-f32/f64回帰ゲート' 
