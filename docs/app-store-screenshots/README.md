# App Storeスクリーンショット・テンプレート

Issue #50のiPhone 6.9インチ向けテンプレートです。出力サイズは縦`1320 × 2868`ピクセルです。

## 6枚の構成

| 番号 | 見出し | 差し替える画像 |
| --- | --- | --- |
| 1 | ローマ字の文章を、自然な日本語へ | 変換後のメモアプリとSumibiキーボード |
| 2 | 英字QWERTYの1画面で入力 | ローマ字の入力途中 |
| 3 | 候補から、好みの表現を選択 | 複数候補とUndo |
| 4 | 記号一覧も、ワンタップで | 展開した記号一覧とQWERTYキーボード |
| 5 | 固有名詞をユーザー辞書に登録 | ユーザー辞書編集画面 |
| 6 | 送信先を確認してからAI変換 | プライバシー欄と同意スイッチ |

## キャプチャの配置

実機またはSimulatorで撮影した縦画像を、次の名前で`captures`ディレクトリへ置きます。

```text
captures/01-natural-japanese.png
captures/02-qwerty-input.png
captures/03-candidates.png
captures/04-user-dictionary.png
captures/05-privacy-consent.png
captures/06-symbol-panel.png
```

画像がない間は、撮影内容を示すプレースホルダーが表示されます。配置した画像は端末枠の内側へ上寄せで拡大・トリミングされます。

## プレビューの生成

```sh
sh docs/app-store-screenshots/render-previews.sh
```

生成先は`docs/app-store-screenshots/previews`です。実際のキャプチャを配置した後に再実行すると、提出候補画像を更新できます。

## 撮影前の安全確認

- APIキーを表示しない
- 個人名、メールアドレス、通知を写さない
- 辞書は`sumibi = Sumibi`、`openai = OpenAI`などのテストデータを使う
- 未実装の機能や実際と異なる変換結果を合成しない
- 6枚で外観、テーマ、時刻、文字サイズを揃える
