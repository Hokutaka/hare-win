#requires -Version 5.1
# harec upstreamを取得し、Windows候補を作ってゲート通過時のみ採用。
# 失敗時はupstream.lock.jsonも前の合格版も変更しない。
[CmdletBinding()]
param(
    [string]$Ref = 'master',
    [string]$QbePath = '',
    [string]$GccPath = 'C:\msys64\ucrt64\bin\gcc.exe',
    [switch]$NoFetch,
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Repo = Join-Path $Root 'vendor\harec.git'
$LockPath = Join-Path $Root 'upstream.lock.json'
$UpstreamUrl = 'https://git.sr.ht/~sircmpwn/harec'
$GitCommand = Get-Command 'git.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $GitCommand) { throw 'Git for Windows の git.exe が必要です。' }
$Git = $GitCommand.Source

function Run-Native([string]$Program, [string[]]$Arguments) {
    Write-Host ('実行 > ' + $Program + ' ' + ($Arguments -join ' '))
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "実行失敗: $Program (終了コード $LASTEXITCODE)" }
}
if ($env:OS -ne 'Windows_NT') { throw 'Windows PowerShellから実行してください。' }
if ($Ref -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._/-]*$' -or $Ref.Contains('..') -or $Ref.EndsWith('/')) {
    throw "危険または不正なGit refです: $Ref"
}
if (-not $QbePath -and $env:HAREWIN_QBE) { $QbePath = $env:HAREWIN_QBE }
if (-not $QbePath) { throw '-QbePath または環境変数 HAREWIN_QBE にQBEの実行ファイルを指定してください。' }
if (-not (Test-Path -LiteralPath $QbePath -PathType Leaf)) { throw "QBEなし: $QbePath" }
if (-not (Test-Path -LiteralPath $GccPath -PathType Leaf)) { throw "GCCなし: $GccPath" }
$Triplet = ((& $GccPath '-dumpmachine') -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $Triplet -ne 'x86_64-w64-mingw32') {
    throw "x64 MinGW-w64 GCCが必要です: $Triplet"
}
# 同一コミットでもQBE/GCC/Windows互換レイヤーが変われば再検証する。
$QbeHash = (Get-FileHash -LiteralPath $QbePath -Algorithm SHA256).Hash.ToLowerInvariant()
$GccHash = (Get-FileHash -LiteralPath $GccPath -Algorithm SHA256).Hash.ToLowerInvariant()
$InputFiles = @(
    'scripts\update-upstream.ps1','scripts\build-harec.ps1','scripts\test-hare.ps1',
    'scripts\report-changes.ps1','scripts\show-changes.ps1',
    'tests\audit-smoke.ps1',
    'compat\harewin-compat.c','compat\harewin-compat.h',
    'compat\gen_typename-windows.c.txt','tests\compat-smoke.c',
    'tests\qbe-float-arg5.ssa','tests\qbe-double-arg5.ssa','src\athena3.ha','src\host.c'
)
$InputHashes = foreach ($RelativeFile in $InputFiles) {
    $RelativeFile + ':' + (Get-FileHash -LiteralPath (Join-Path $Root $RelativeFile) -Algorithm SHA256).Hash
}
$Sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $InputBytes = [System.Text.Encoding]::UTF8.GetBytes(($InputHashes -join '|'))
    $InputsHash = ([System.BitConverter]::ToString($Sha256.ComputeHash($InputBytes))).Replace('-','').ToLowerInvariant()
} finally {
    $Sha256.Dispose()
}

Write-Host "公式harecの更新を確認します: $Ref"
if (-not (Test-Path -LiteralPath (Join-Path $Repo 'HEAD'))) {
    if ($NoFetch) { throw '-NoFetchですがローカルのvendor/harec.gitがありません。' }
    New-Item -Force -ItemType Directory -Path (Join-Path $Root 'vendor') | Out-Null
    Run-Native $Git @('clone','--bare',$UpstreamUrl,$Repo)
}
$ActualRemote = ((& $Git '-C' $Repo 'remote' 'get-url' 'origin') -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $ActualRemote -ne $UpstreamUrl) {
    throw "vendor/harec.git のoriginが公式と異なります: $ActualRemote"
}
if (-not $NoFetch) {
    # branch変更とtag追加を取得する。checkoutやresetは一度も行わない。
    Run-Native $Git @('-C',$Repo,'fetch','--prune','--tags','origin','+refs/heads/*:refs/remotes/origin/*')
}

# 短いref文字列をrev-parseへ直接渡さない。tag / branch / commitを明確に区別。
$Spec = ''
if ($Ref -match '^[a-fA-F0-9]{40}$') {
    $Spec = "$Ref^{commit}"
} else {
    & $Git '-C' $Repo 'show-ref' '--verify' '--quiet' ("refs/tags/" + $Ref)
    if ($LASTEXITCODE -eq 0) {
        $Spec = 'refs/tags/' + $Ref + '^{commit}'
    } else {
        & $Git '-C' $Repo 'show-ref' '--verify' '--quiet' ("refs/remotes/origin/" + $Ref)
        if ($LASTEXITCODE -eq 0) { $Spec = 'refs/remotes/origin/' + $Ref + '^{commit}' }
    }
}
if (-not $Spec) { throw "取得済みの公式リポジトリにrefがありません: $Ref" }
$Commit = ((& $Git '-C' $Repo 'rev-parse' '--verify' $Spec) -join '').Trim()
if ($LASTEXITCODE -ne 0 -or $Commit -notmatch '^[a-f0-9]{40}$') {
    throw "コミット解決に失敗しました: $Ref -> $Commit"
}
Write-Host "検証対象: $Ref -> $Commit"
if (-not $Force -and (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
    $Old = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($Old.commit -eq $Commit -and $Old.ref -eq $Ref -and
        $Old.qbe_sha256 -eq $QbeHash -and $Old.gcc_sha256 -eq $GccHash -and
        $Old.inputs_sha256 -eq $InputsHash) {
        $OldExe = Join-Path $Root ($Old.artifact -replace '/', '\')
        if ((Test-Path -LiteralPath $OldExe -PathType Leaf) -and
            (Get-FileHash -LiteralPath $OldExe -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Old.harec_sha256) {
            Write-Host '前回合格済みのコミットです。再検証は -Force で実行できます。'
            Write-Host "現行版: $OldExe"
            exit 0
        }
    }
}

$Guid = [guid]::NewGuid().ToString('N').Substring(0, 8)
$Short = $Commit.Substring(0, 12)
$Candidate = Join-Path $Root ("build\c\$Short-$Guid")
$Source = Join-Path $Candidate 'source'
$Compiled = Join-Path $Candidate 'compiled'
$Archive = Join-Path $Candidate 'harec-source.zip'
New-Item -Force -ItemType Directory -Path $Source | Out-Null
Write-Host "候補を作成: $Candidate"
try {
    # commit hash固定のソーススナップショット。bare upstreamリポジトリには作業ツリー自体がない。
    Run-Native $Git @('-C',$Repo,'archive','--format=zip',("--output=" + $Archive),$Commit)
    Expand-Archive -LiteralPath $Archive -DestinationPath $Source
    Remove-Item -LiteralPath $Archive -Force
    $VersionLabel = 'upstream-' + $Short + '-harewin'

    # 子プロセス経由で異常終了を必ず検出する。
    Run-Native 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass',
        '-File',(Join-Path $PSScriptRoot 'build-harec.ps1'),
        '-SourcePath',$Source,'-OutputRoot',$Compiled,'-VersionLabel',$VersionLabel,
        '-UpstreamCommit',$Commit,'-GccPath',$GccPath)
    Run-Native 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass',
        '-File',(Join-Path $PSScriptRoot 'test-hare.ps1'),
        '-HarecPath',(Join-Path $Compiled 'bin\harec.exe'),
        '-QbePath',$QbePath,'-GccPath',$GccPath,
        '-OutputDir',(Join-Path $Candidate 'tests'))
    # 差分が生成されていなければ採用を拒否する（後日比較不能になるのを防ぐ）。
    $AuditPath = Join-Path $Compiled 'audit'
    foreach ($Name in @('REPORT.md','changes.json','upstream-to-windows.patch','build-arguments.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $AuditPath $Name) -PathType Leaf)) {
            throw "公式ソースとの差分監査が欠落しています: $Name"
        }
    }
    # ここまで全ゲート成功。採用対象の実行ファイルをバージョン保存。
    $VersionName = "$Short-$Guid"
    $VersionDir = Join-Path $Root ("build\v\$VersionName")
    New-Item -Force -ItemType Directory -Path (Join-Path $Root 'build\v') | Out-Null
    Move-Item -LiteralPath $Candidate -Destination $VersionDir
    $Artifact = "build/v/$VersionName/compiled/bin/harec.exe"
    $Exe = Join-Path $Root ($Artifact -replace '/', '\')
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw '候補移動後のharec.exeがありません。' }

    # ロックファイルだけが「どの版を採用するか」の正本。
    $ReportArtifact = "build/v/$VersionName/compiled/audit/REPORT.md"
    $PatchArtifact = "build/v/$VersionName/compiled/audit/upstream-to-windows.patch"
    $ManifestArtifact = "build/v/$VersionName/compiled/audit/changes.json"
    $Lock = [ordered]@{
        schema = 1
        upstream_url = $UpstreamUrl
        ref = $Ref
        commit = $Commit
        artifact = $Artifact
        audit_report = $ReportArtifact
        audit_patch = $PatchArtifact
        audit_manifest = $ManifestArtifact
        audit_patch_sha256 = (Get-FileHash -LiteralPath (Join-Path $VersionDir 'compiled\audit\upstream-to-windows.patch') -Algorithm SHA256).Hash.ToLowerInvariant()
        tested_utc = [DateTime]::UtcNow.ToString('o')
        gcc_target = $Triplet
        qbe_sha256 = $QbeHash
        gcc_sha256 = $GccHash
        inputs_sha256 = $InputsHash
        harec_sha256 = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash.ToLowerInvariant()
        tests = @('compat-smoke','harec-version','hare-qbe-ir','hare-qbe-win64-athena3-telemetry','qbe-win64-f32-f64-arg5-assembly')
    }
    $Json = ($Lock | ConvertTo-Json -Depth 5) + "`n"
    $Temp = $LockPath + '.tmp-' + [guid]::NewGuid().ToString('N')
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Temp, $Json, $Utf8)
    if (Test-Path -LiteralPath $LockPath -PathType Leaf) {
        # 同じディレクトリ／ボリューム上で既存lockを置換。バックアップも残す。
        [System.IO.File]::Replace($Temp, $LockPath, ($LockPath + '.bak-' + [guid]::NewGuid().ToString('N').Substring(0, 8)), $true)
    } else {
        [System.IO.File]::Move($Temp, $LockPath)
    }
    Write-Host '========================================'
    Write-Host 'PASS: upstream更新候補のWindowsゲートが全件成功。採用しました。'
    Write-Host "採用コミット: $Commit"
    Write-Host "harec.exe: $Exe"
    Write-Host "公式ソースとの差分: $(Join-Path $Root ($ReportArtifact -replace '/', '\'))"
    Write-Host "Gitパッチ: $(Join-Path $Root ($PatchArtifact -replace '/', '\'))"
    Write-Host 'upstream.lock.json をGitへコミットすると採用revisionを共有できます。'
} catch {
    Write-Warning "候補は不採用です。既存upstream.lock.jsonは更新しません: $_"
    Write-Warning "確認用の候補ファイル（存在する場合）: $Candidate"
    throw
}
