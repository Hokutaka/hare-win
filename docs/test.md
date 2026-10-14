# テスト

## 採用版の実行テスト

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test-hare.ps1 `
  -QbePath 'C:\tools\qbe.exe'
```

検査内容：

- Hareソース → QBE IR → Windows x64アセンブリ → COFF → EXE
- アテナ3号の消費電力をHareで計算し、Cホストから64bit整数と第5引数の受け渡しを確認
- 自律動作の消費電力、電力不足、妖怪MAXの在庫を確認
- QBE `amd64_win`の第5引数`f32`/`f64`をアセンブル
- MSYS/CygwinランタイムDLLへの依存を検査

## 差分監査テスト

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\audit-smoke.ps1
```

互換層の単体テストと`harec.exe`の起動確認は`update-upstream.ps1`で実行します。
