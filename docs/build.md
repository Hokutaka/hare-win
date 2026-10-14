# ビルド

## 必要なもの

- Windows x64
- PowerShell 5.1以降
- Git for Windows
- MSYS2 UCRT64 GCC（`C:\msys64\ucrt64\bin\gcc.exe`）
- Windows上で動作するQBE（`amd64_win`ターゲット対応）

## 実行

リポジトリのルートでPowerShellを開きます。

```powershell
$env:HAREWIN_QBE = 'C:\tools\qbe.exe'

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\update-upstream.ps1 -Ref '0.26.0'
```

`HAREWIN_QBE`には手元の`qbe.exe`のパスを指定してください。

## 生成先

- `vendor/harec.git/` — 公式harecのbare Gitリポジトリ
- `build/c/` — ビルド・テスト中の候補
- `build/v/` — テスト通過済みの版
- `upstream.lock.json` — 現在の採用コミット

採用済みの`harec.exe`を確認する場合：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\current-harec.ps1 -Version
```
