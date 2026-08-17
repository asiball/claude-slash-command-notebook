# Slash Command Notebook — 再実行ツールキット

「Slash Command Notebook」(Claude Code スラッシュコマンドの実測リファレンス)を再生成するための一式。

- 公開ページ (GitHub Pages): https://asiball.github.io/claude-slash-command-notebook/
- ページソース: `slash-command-notebook.html` が正本。`index.html` は `wrap-index.py` で生成した Pages 用ラッパー

## 前提

- Claude Code CLI(ログイン済み)、tmux、python3、git
- 一時成果物はすべて `work/` 配下に生成される(丸ごと削除して再実行してよい)

## 再実行手順

```bash
./setup-sample.sh        # 1. サンプルプロジェクトを work/sample-project に再構築
./run-headless.sh        # 2. §1 のヘッドレス実測(init/recap/compact/code-review/security-review/verify)
./capture-ui.sh          # 3. §2 の画面をカラー付きで採取(tmux 110×42 → work/tui-color/*.ansi)
./capture-skill-a.sh     # 4. §1 の端末画面 前半(init/recap/compact/explain。対話モードで別回実行)
./capture-skill-b.sh     # 5. §1 の端末画面 後半(code-review/security-review/doctor。4 の tmux セッションを引き継ぐ)
python3 ansi2html.py     # 6. ANSI→HTML 変換し、既存セルのトリミング境界に合わせて差し替え
```

- 3〜5 は追加コマンド(/effort /memory /goal /btw)の採取を含まない。必要なら `capture-ui.sh` の `snap` 行に追記する。
- `ansi2html.py` は「既存セルの先頭行・末尾行」を新キャプチャ内で探して置換する方式。画面レイアウトが大きく変わった版では境界が見つからず `!!` を出すので、その場合は該当セルを手動更新する。
- メールアドレス・セッション ID は `ansi2html.py` の `MASKS` で自動伏せ字化される。マスク対象を増やす場合はここに追記。

## HTML の更新と公開

- §1 の Out(ヘッドレス出力)は `work/out/*.out` から**手動で**セルに反映する(出力は非決定的なので、本文の注記・要旨・実測値も合わせて見直すこと)。
- 編集は `slash-command-notebook.html` に対して行い、`python3 wrap-index.py` で `index.html` を再生成してから push する(main への push で GitHub Pages に反映される)。

## 更新時の注意(ページ内の整合)

- ヘッダのチップ「実測 N コマンド」、§3 の「→ §1/§2 で実測」参照、目次のコマンドリンクは、セルの増減に合わせて更新する。
- 実測値を本文に書く場合は日付印を付ける(例: 「2026-08-17 実測」)。CLI バージョンはヘッダのチップと「取得方法」の2箇所にある。

## 注意

- `setup-sample.sh` が生成するサンプルコードには、レビュー系コマンドのデモ用に**意図的な脆弱性**(SQL インジェクション、コマンドインジェクション、ハードコードされたパスワード)が含まれる。実運用コードに流用しないこと。
- ページ内の端末キャプチャは伏せ字処理済み(`ansi2html.py` の `MASKS`)。再実行時も同スクリプトを通せば同じマスクが適用される。
