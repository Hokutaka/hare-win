#requires -Version 5.1
# 公式のarchiveとWindowsビルドstageの差分を監査する。
# source/stageへの書き込みなし。監査用の独立した一時Gitリポジトリのみ使用。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$StagePath,
    [Parameter(Mandatory = $true)][string]$OutputDir,
    [string]$UpstreamCommit = '',
    [string]$VersionLabel = '',
    [string]$GccPath = '',
    [string]$GeneratedConfigPath = '',
    [string[]]$BuildArgs = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$GitCommand = Get-Command 'git.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $GitCommand) { throw '監査レポートの作成にはGit for Windowsが必要です。' }
$Git = $GitCommand.Source
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Run-Git([string[]]$ArgsList) {
    & $Git @ArgsList | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "監査用Git処理が失敗しました (exit=$LASTEXITCODE): $($ArgsList -join ' ')" }
}
function Get-TreeMap([string]$Folder) {
    $Map = @{}
    foreach ($Top in @('src', 'include')) {
        $Dir = Join-Path $Folder $Top
        if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
            throw "監査に必要なディレクトリがありません: $Dir"
        }
        $FullDir = [System.IO.Path]::GetFullPath($Dir).TrimEnd([char[]]@('\', '/'))
        foreach ($File in @(Get-ChildItem -LiteralPath $Dir -File -Recurse)) {
            $Relative = ($Top + '/' + $File.FullName.Substring($FullDir.Length + 1).Replace('\', '/'))
            if ($Map.ContainsKey($Relative)) { throw "重複したソース名: $Relative" }
            $Map[$Relative] = $File.FullName
        }
    }
    return $Map
}
function Hash-File([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$SourceFull = [System.IO.Path]::GetFullPath($SourcePath).TrimEnd([char[]]@('\', '/'))
$StageFull = [System.IO.Path]::GetFullPath($StagePath).TrimEnd([char[]]@('\', '/'))
if ($SourceFull -eq $StageFull) { throw '元ソースとstageが同一ディレクトリです。' }
if ($UpstreamCommit -and $UpstreamCommit -notmatch '^[a-fA-F0-9]{40}$') {
    throw '指定コミットは40桁のGit SHA-1である必要があります。'
}
$From = Get-TreeMap $SourceFull
$To = Get-TreeMap $StageFull
$Changed = @()
$UnchangedCount = 0
$AllPaths = @(@($From.Keys) + @($To.Keys) | Sort-Object -Unique)
foreach ($Relative in $AllPaths) {
    $SourceHash = if ($From.ContainsKey($Relative)) { Hash-File $From[$Relative] } else { $null }
    $StageHash = if ($To.ContainsKey($Relative)) { Hash-File $To[$Relative] } else { $null }
    if ($SourceHash -eq $StageHash) { $UnchangedCount++; continue }
    $Status = if ($null -eq $SourceHash) { 'A' } elseif ($null -eq $StageHash) { 'D' } else { 'M' }
    $Changed += [pscustomobject][ordered]@{
        status = $Status
        path = $Relative
        upstream_sha256 = $SourceHash
        windows_stage_sha256 = $StageHash
    }
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$PatchPath = Join-Path $OutputDir 'upstream-to-windows.patch'
$ReportPath = Join-Path $OutputDir 'REPORT.md'
$JsonPath = Join-Path $OutputDir 'changes.json'
$FlagsPath = Join-Path $OutputDir 'build-arguments.txt'
$TempWork = Join-Path $OutputDir ('_gitdiff-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempWork | Out-Null
try {
    # 一時Git repoで本当のGitパッチを出力。upstreamのbare repoや元ソースは変更しない。
    Run-Git -ArgsList @('init', '-q', $TempWork)
    Run-Git -ArgsList @('-C', $TempWork, 'config', 'core.autocrlf', 'false')
    Run-Git -ArgsList @('-C', $TempWork, 'config', 'core.safecrlf', 'false')
    Run-Git -ArgsList @('-C', $TempWork, 'config', 'core.filemode', 'false')
    Run-Git -ArgsList @('-C', $TempWork, 'config', 'user.name', 'Hare-Windows Audit')
    Run-Git -ArgsList @('-C', $TempWork, 'config', 'user.email', 'harewin-audit@localhost')
    Run-Git -ArgsList @('-C', $TempWork, 'config', 'commit.gpgsign', 'false')
    foreach ($Part in @('src', 'include')) {
        Copy-Item -LiteralPath (Join-Path $SourceFull $Part) -Destination (Join-Path $TempWork $Part) -Recurse
    }
    Run-Git -ArgsList @('-C', $TempWork, 'add', '--all', '--', 'src', 'include')
    Run-Git -ArgsList @('-C', $TempWork, 'commit', '-q', '-m', 'Original upstream snapshot')
    foreach ($Part in @('src', 'include')) {
        Remove-Item -LiteralPath (Join-Path $TempWork $Part) -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $StageFull $Part) -Destination (Join-Path $TempWork $Part) -Recurse
    }
    Run-Git -ArgsList @('-C', $TempWork, 'add', '--all', '--', 'src', 'include')
    # 引数は空白を含まない固定文字列、出力はバイト保存。PowerShell 5.1による文字化けを避ける。
    $ErrPath = Join-Path $OutputDir 'git-diff-stderr.tmp'
    $Proc = Start-Process -FilePath $Git -WorkingDirectory $TempWork `
        -ArgumentList @('--no-pager','diff','--cached','--binary','--no-renames','HEAD','--','src','include') `
        -RedirectStandardOutput $PatchPath -RedirectStandardError $ErrPath `
        -NoNewWindow -Wait -PassThru
    if ($Proc.ExitCode -ne 0) {
        $ErrorMessage = if (Test-Path $ErrPath) { [System.IO.File]::ReadAllText($ErrPath) } else { '' }
        throw "git diffの生成に失敗 (exit=$($Proc.ExitCode)): $ErrorMessage"
    }
    if (Test-Path $ErrPath) { Remove-Item -LiteralPath $ErrPath -Force }
    if (@($Changed).Count -gt 0) {
        # パッチが実際にstageから公式ソースへ巻き戻せるかだけ検査。適用はしない。
        Run-Git -ArgsList @('-C', $TempWork, 'apply', '--reverse', '--check', $PatchPath)
    }
} finally {
    if (Test-Path -LiteralPath $TempWork) { Remove-Item -LiteralPath $TempWork -Recurse -Force }
}
$PatchSize = (Get-Item -LiteralPath $PatchPath).Length
if ($Changed.Count -gt 0 -and $PatchSize -eq 0) {
    throw 'SHA256で差分が見つかったのにGitパッチが空です。'
}
if ($Changed.Count -eq 0 -and $PatchSize -ne 0) {
    throw 'SHA256で差分がないのにGitパッチが生成されました。'
}

# 公式ソースには含まれない独自実装／ビルドオプションを別に記録。
$ExternalNames = @(
    'compat/harewin-compat.c',
    'compat/harewin-compat.h',
    'compat/gen_typename-windows.c.txt',
    'scripts/build-harec.ps1',
    'scripts/report-changes.ps1'
)
$External = @(
    foreach ($Relative in $ExternalNames) {
        $File = Join-Path $Root ($Relative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw "互換層の構成ファイルがありません: $Relative" }
        [pscustomobject][ordered]@{ path = $Relative; sha256 = (Hash-File $File) }
    }
)
$CompilerHash = if ($GccPath -and (Test-Path -LiteralPath $GccPath -PathType Leaf)) { Hash-File $GccPath } else { $null }
$Manifest = [ordered]@{
    schema = 1
    upstream_commit = $UpstreamCommit
    version_label = $VersionLabel
    source_files = $From.Count
    stage_files = $To.Count
    unchanged_files = $UnchangedCount
    changed_files = @($Changed)
    patch_sha256 = (Hash-File $PatchPath)
    gcc_path = $GccPath
    gcc_sha256 = $CompilerHash
    generated_config_sha256 = if ($GeneratedConfigPath -and (Test-Path -LiteralPath $GeneratedConfigPath -PathType Leaf)) { Hash-File $GeneratedConfigPath } else { $null }
    external_compat_files = @($External)
    build_arguments = @($BuildArgs)
}
[System.IO.File]::WriteAllText($JsonPath, (($Manifest | ConvertTo-Json -Depth 8) + "`n"), $Utf8)
$FlagText = "GCC: $GccPath`nGCC SHA256: $CompilerHash`n" + (($BuildArgs | ForEach-Object { $_ }) -join "`n") + "`n"
[System.IO.File]::WriteAllText($FlagsPath, $FlagText, $Utf8)
$Lines = @(
    '# hare-win: 公式harecとの差分'
    ''
    "- upstreamコミット: ``$UpstreamCommit``"
    "- バージョン表示: ``$VersionLabel``"
    "- 検査対象: 公式スナップショットの ``src/`` と ``include/`` vs Windowsビルド用stage"
    "- 公式ファイル数: $($From.Count)、stageファイル数: $($To.Count)"
    "- **変更ファイル: $($Changed.Count)、無変更ファイル: $UnchangedCount**"
    ''
    '## A. 公式ソースに対する内容変更'
    ''
    '| 種別 | パス |'
    '| --- | --- |'
)
if ($Changed.Count -eq 0) { $Lines += '| 変更なし | — |' }
foreach ($Item in $Changed) { $Lines += "| $($Item.status) | ``$($Item.path)`` |" }
$Lines += @(
    ''
    'M=変更、A=追加、D=削除。正確な内容は `upstream-to-windows.patch` を確認してください。'
    'このGitパッチは公式スナップショットに対する通常の `a/src/...` / `b/src/...` 差分です。'
    ''
    '## B. 追加ファイルとビルド設定'
    ''
    '- `compat/harewin-compat.c`：Windowsホスト互換関数の実装を追加リンク'
    '- `compat/harewin-compat.h`：コンパイル時に `-include` で強制インクルード'
    '- `compat/gen_typename-windows.c.txt`：stage限定の `gen_typename` 置換本文'
    '- `harewin-build-config.h`：ビルド時生成のVERSION／DEFAULT_TARGET定義を `-include`'
    '- GCCオプション・入力ファイル：`build-arguments.txt`、`changes.json` に保存'
    '- 上記独自ファイルのSHA256：`changes.json` に保存'
    ''
    '## 出力ファイル'
    ''
    '- `upstream-to-windows.patch` — Gitパッチ'
    '- `changes.json` — SHA256'
    '- `build-arguments.txt` — GCCビルド引数'
)
[System.IO.File]::WriteAllText($ReportPath, (($Lines -join "`n") + "`n"), $Utf8)
Write-Host "公式src/includeの差分: $($Changed.Count) ファイル、無変更: $UnchangedCount ファイル"
foreach ($Item in $Changed) { Write-Host "  $($Item.status) $($Item.path)" }
Write-Host "差分レポート: $ReportPath"
# 現在のビルド方式で想定していない公式ソースの変更は採用させない。
$Unexpected = @($Changed | Where-Object { $_.path -ne 'src/check.c' -or $_.status -ne 'M' })
if ($Unexpected.Count -gt 0) {
    throw "想定外のソース改変が $($Unexpected.Count) 件あります。REPORT.mdを確認してください。"
}
