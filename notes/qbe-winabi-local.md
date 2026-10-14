# QBE Windows ABI

Cerune-Lang/Cerune#92 で確認したQBEの不具合。

`amd64_win` で第5引数以降の `f32` / `f64` を受け取る際、スタック引数の型クラスが正しく保持されない。

- Issue: https://github.com/Cerune-Lang/Cerune/issues/92
- Patch: https://lists.sr.ht/~mpu/qbe/patches/71380
- 検証済みパッチ適用コミット: `0837a2a`
- ローカルQBE: `Cerune/target/qbe-issue-92/qbe.exe`

`hare-win` のテストでは現在このQBEを使用している。

QBE upstreamに修正が取り込まれたら、修正を含む公式リビジョンでf32/f64の第5引数テストを再実行する。問題がなければローカルのパッチ適用版から切り替える。