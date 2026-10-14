# 公式ソースとの差分

公式harecの`src/`と`include/`を、Windowsビルド用の`stage/`と比較します。

## ソースの変更

| ファイル | 内容 |
| --- | --- |
| `src/check.c` | `gen_typename()`の`open_memstream()`を`tmpfile()`による処理に置換 |

公式ソースは変更しません。変更するのはビルド用のコピーです。

## 追加するもの

- `compat/harewin-compat.c` — Windows用互換関数
- `compat/harewin-compat.h` — 互換宣言
- `compat/gen_typename-windows.c.txt` — `gen_typename()`置換コード
- ビルド時生成ヘッダーとGCCオプション

## 差分の出力

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\show-changes.ps1
```

`build/v/<版>/compiled/audit/`に保存されます。

- `REPORT.md` — 変更ファイル一覧
- `upstream-to-windows.patch` — Git差分
- `changes.json` — SHA256など
- `build-arguments.txt` — コンパイル引数
