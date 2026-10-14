# 公式harecとの差分

公式ソースは変更せず、ビルド用にコピーしたソースへWindows向けの変更を加えています。

現在変更しているのは `src/check.c` の `gen_typename()` だけです。Windowsでは `open_memstream()` が使えないため、`tmpfile()` を使う実装に置き換えています。

そのほかの互換処理は `compat/` に置いています。

## 差分の確認

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\show-changes.ps1
```

実行すると、採用中のバージョンの `compiled/audit/` に以下が生成されます。

| ファイル | 内容 |
| --- | --- |
| `REPORT.md` | 変更ファイルの一覧 |
| `upstream-to-windows.patch` | 公式ソースとの差分 |
| `changes.json` | ファイルのハッシュと変更情報 |
| `build-arguments.txt` | コンパイル時の引数 |

更新時も同じ比較を行い、`src/check.c` 以外に変更が発生した場合は採用を止めます。