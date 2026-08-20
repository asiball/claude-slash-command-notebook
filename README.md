# Slash Command Notebook — 再実行ツールキット

「Slash Command Notebook」(Claude Code スラッシュコマンドの実測リファレンス)を再生成するための一式。

- 公開ページ (GitHub Pages): https://asiball.github.io/claude-slash-command-notebook/
- ページソース: `index.html` が正本(GitHub Pages がリポジトリ直下からそのまま配信する。編集はこのファイルに直接行う)
- 姉妹ページ: `config.html`(Config Notebook — 設定ファイルの階層・優先順位・permissions の実測。準備中)

## フォルダ構成

```
.
├── README.md
├── index.html                    # ページ本体(正本。GitHub Pages がそのまま配信)
├── config.html                   # 姉妹ページ Config Notebook(準備中)
├── fonts/                        # 端末キャプチャ表示用の等幅フォント JetBrains Mono(woff2 自己ホスト。OFL.txt 同梱)
├── setup-sample.sh               # デモ用サンプルプロジェクトを work/sample-project に再構築
├── run-headless.sh               # §1 のヘッドレス実測 → work/out/*.out
├── capture-ui.sh                 # §2 の画面採取 → work/tui-color/*.ansi
├── capture-skill-a.sh            # §1 の端末画面 前半 → work/tui2/
├── capture-skill-b.sh            # §1 の端末画面 後半 → work/tui2/
├── capture-config.sh             # Config Notebook 用の画面採取 → work/config-tui/*.ansi
├── ansi2html.py                  # ANSI→HTML 変換とセル差し替え(引数なし=index.html、`config` 指定で config.html)
└── work/                         # 一時成果物(git 管理外。丸ごと削除して再実行してよい)
    ├── sample-project/           # デモ対象(ページ §1 冒頭の Setup セルの構成と対応。setup-sample.sh 実行のたびに再構築)
    ├── sample-project-2/         # 「端末画面(実測)」用のクリーンコピー
    ├── sample-remote.git/        # sample-project の bare リモート(/security-review 用)
    ├── out/                      # §1 ヘッドレス出力
    ├── tui-color/                # §2 ANSI キャプチャ
    ├── tui2/                     # §1 端末画面キャプチャ
    ├── config-demo/              # Config Notebook のデモ対象(capture-config.sh 実行のたびに再構築)
    ├── config-tui/               # Config Notebook の ANSI キャプチャ
    └── config-backup/            # capture-config.sh が ~/.claude/settings.json を退避する場所
```

`work/` 配下は `setup-sample.sh` 以降の各スクリプトが生成するもので、リポジトリにはコミットされない(`.gitignore` 済み)。

## 前提

- Claude Code CLI(ログイン済み)、tmux、python3、git
- 一時成果物はすべて `work/` 配下に生成される(丸ごと削除して再実行してよい)。ただし `setup-sample.sh` 自体が自動で消すのは `work/sample-project`・`work/sample-project-2`・`work/sample-remote.git` のみで、採取済みの `work/out`・`work/tui-color`・`work/tui2` は残す(これらを作り直したい場合は該当スクリプトを再実行するか、手動で削除する)

## 再実行手順

```bash
./setup-sample.sh        # 1. サンプルプロジェクトを work/sample-project に再構築
./run-headless.sh        # 2. §1 のヘッドレス実測(init/recap/compact/explain/doctor/code-review/security-review/verify。レビュー系のみ sonnet、他は haiku)
./capture-ui.sh          # 3. §2 の画面をカラー付きで採取(tmux 110×42 → work/tui-color/*.ansi)
./capture-skill-a.sh     # 4. §1 の端末画面 前半(init/recap/compact/explain。対話モードで別回実行)
./capture-skill-b.sh     # 5. §1 の端末画面 後半(code-review/security-review/doctor。4 の tmux セッションを引き継ぐ)
python3 ansi2html.py     # 6. ANSI→HTML 変換し、§2 の画面セルのみをトリミング境界に合わせて差し替え(引数なし=従来どおり index.html 対象)
```

- 3〜5 は追加コマンド(/effort /memory /goal /btw)の採取を含まない。必要なら `capture-ui.sh` の `snap` 行に追記する。
- 引数なしの `ansi2html.py` が自動で差し替えるのは **§2 の画面セル**(`work/tui-color/*.ansi`)のみ。§1 の「端末画面(実測)」(`work/tui2/` の平文キャプチャ)は対象外なので、内容の反映は手動で行う。`config.html` を対象にする場合は `python3 ansi2html.py config`(後述)。
- `ansi2html.py` は「既存セルの先頭行・末尾行」を新キャプチャ内で探して置換する方式。画面レイアウトが大きく変わった版では境界が見つからず `!!` を出すので、その場合は該当セルを手動更新する。
- メールアドレス・セッション ID は `ansi2html.py` の `MASKS` で自動伏せ字化される。マスク対象を増やす場合はここに追記。

### Config Notebook の採取(準備中)

姉妹ページ `config.html` の画面セルは、上とは別の2手順で採取・反映する:

```bash
./capture-config.sh          # 1. 設定スコープ / permissions の実測画面を採取(work/config-demo を再構築 → work/config-tui/*.ansi)
python3 ansi2html.py config  # 2. ANSI→HTML 変換し、config.html の画面セルを差し替え
```

- 初回はセルが「(未採取)」プレースホルダのため、境界探索なしでキャプチャ全行が丸ごと差し替わる(`ok-full` と表示)。2回目以降は index.html と同じく既存セルの先頭行・末尾行を境界として置換する。
- `capture-config.sh` は user スコープのデモのため **`~/.claude/settings.json` を一時変更する**(`"model": "claude-opus-5"` を JSON マージで追記)。変更前の内容は `work/config-backup/` に退避され、スクリプト終了時(異常終了・中断を含む)に `trap` で必ず復元されるが、ユーザー設定に触れる以上、コンテナや VM などの隔離環境での実行を推奨。

## HTML の更新と公開

- §1 の Out(ヘッドレス出力)は `work/out/*.out` から**手動で**セルに反映する(出力は非決定的なので、本文の注記・要旨・実測値も合わせて見直すこと)。
- §1 の「端末画面(実測)」(`work/tui2/` の平文キャプチャ)も同様に**手動で**セルに反映する。`ansi2html.py` が自動差し替えするのは §2 の画面セルのみ。
- 編集は `index.html` に対して直接行い、push する(main への push で GitHub Pages に反映される)。`ansi2html.py` の差し替え先も、引数なしなら `index.html`(`config` 指定時のみ `config.html`)。
- 端末キャプチャ(AA を含む)の表示は `fonts/` の JetBrains Mono(woff2)を等幅フォントとして自己ホストして固定している。罫線(U+2500〜)・ブロック要素(U+2588〜259F)を収録したフォントであることが要件で、Google Fonts 配信はサブセット化でこの範囲を落とすため使わない。

## 更新時の注意(ページ内の整合)

- ヘッダのチップ「実測 N コマンド」、§3 の「→ §1/§2 で実測」参照、目次のコマンドリンクは、セルの増減に合わせて更新する。
- 実測値を本文に書く場合は日付印を付ける(例: 「2026-08-17 実測」)。CLI バージョンはヘッダのチップと「取得方法」の2箇所にある。

## 注意

- `setup-sample.sh` が生成するサンプルコードには、レビュー系コマンドのデモ用に**意図的な脆弱性**(SQL インジェクション、コマンドインジェクション、ハードコードされたパスワード)が含まれる。実運用コードに流用しないこと。
- `/verify` などはこの脆弱なサンプルコードを実際に実行する。一連の再実行(`setup-sample.sh` 〜 `capture-skill-b.sh`)はコンテナや VM などの隔離環境で行うこと。
- ページ内の端末キャプチャは伏せ字処理済み(`ansi2html.py` の `MASKS`)。再実行時も同スクリプトを通せば同じマスクが適用される。
