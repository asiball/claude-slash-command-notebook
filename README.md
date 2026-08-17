# Slash Command Notebook — 再実行ツールキット

「Slash Command Notebook」(Claude Code スラッシュコマンドの実測リファレンス)を再生成するための一式。

- 公開ページ (GitHub Pages): https://asiball.github.io/claude-slash-command-notebook/
- ページソース: `index.html` が正本(GitHub Pages がリポジトリ直下からそのまま配信する。編集はこのファイルに直接行う)

## フォルダ構成

```
.
├── README.md
├── index.html                    # ページ本体(正本。GitHub Pages がそのまま配信)
├── fonts/                        # 端末キャプチャ表示用の等幅フォント JetBrains Mono(woff2 自己ホスト。OFL.txt 同梱)
├── setup-sample.sh               # デモ用サンプルプロジェクトを work/sample-project に再構築
├── run-headless.sh               # §1 のヘッドレス実測 → work/out/*.out
├── capture-ui.sh                 # §2 の画面採取 → work/tui-color/*.ansi
├── capture-skill-a.sh            # §1 の端末画面 前半 → work/tui2/
├── capture-skill-b.sh            # §1 の端末画面 後半 → work/tui2/
├── ansi2html.py                  # ANSI→HTML 変換とセル差し替え
└── work/                         # 一時成果物(git 管理外。丸ごと削除して再実行してよい)
    ├── sample-project/           # デモ対象(ページ §1 冒頭の Setup セルの構成と対応)
    ├── sample-project-2/         # 「端末画面(実測)」用のクリーンコピー
    ├── sample-remote.git/        # sample-project の bare リモート(/security-review 用)
    ├── out/                      # §1 ヘッドレス出力
    ├── tui-color/                # §2 ANSI キャプチャ
    └── tui2/                     # §1 端末画面キャプチャ
```

`work/` 配下は `setup-sample.sh` 以降の各スクリプトが生成するもので、リポジトリにはコミットされない(`.gitignore` 済み)。

## 前提

- Claude Code CLI(ログイン済み)、tmux、python3、git
- 一時成果物はすべて `work/` 配下に生成される(丸ごと削除して再実行してよい)

## 再実行手順

```bash
./setup-sample.sh        # 1. サンプルプロジェクトを work/sample-project に再構築
./run-headless.sh        # 2. §1 のヘッドレス実測(init/recap/compact/explain/doctor/code-review/security-review/verify。レビュー系のみ sonnet、他は haiku)
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
- 編集は `index.html` に対して直接行い、push する(main への push で GitHub Pages に反映される)。`ansi2html.py` の差し替え先も `index.html`。
- 端末キャプチャ(AA を含む)の表示は `fonts/` の JetBrains Mono(woff2)を等幅フォントとして自己ホストして固定している。罫線(U+2500〜)・ブロック要素(U+2588〜259F)を収録したフォントであることが要件で、Google Fonts 配信はサブセット化でこの範囲を落とすため使わない。

## 更新時の注意(ページ内の整合)

- ヘッダのチップ「実測 N コマンド」、§3 の「→ §1/§2 で実測」参照、目次のコマンドリンクは、セルの増減に合わせて更新する。
- 実測値を本文に書く場合は日付印を付ける(例: 「2026-08-17 実測」)。CLI バージョンはヘッダのチップと「取得方法」の2箇所にある。

## 注意

- `setup-sample.sh` が生成するサンプルコードには、レビュー系コマンドのデモ用に**意図的な脆弱性**(SQL インジェクション、コマンドインジェクション、ハードコードされたパスワード)が含まれる。実運用コードに流用しないこと。
- ページ内の端末キャプチャは伏せ字処理済み(`ansi2html.py` の `MASKS`)。再実行時も同スクリプトを通せば同じマスクが適用される。
