# 公式ソースの更新

`update-upstream.ps1` で公式harecの更新を取得します。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\update-upstream.ps1 `
  -Ref master `
  -QbePath '<qbe.exeのフルパス>'
```

指定したコミットからWindows版をビルドし、テストが通った場合だけ採用します。

採用したコミットは `upstream.lock.json` に記録されます。

## 現在のバージョン

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\current-harec.ps1 -Version
```

## 差分の確認

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\show-changes.ps1
```