# App Storeスクリーンショット・テンプレート

Issue #110のバージョン1.2.0向けに更新した、iPhone 6.9インチ用テンプレートです。出力サイズは縦`1320 × 2868`ピクセルです。

## 6枚の構成

| 番号 | 見出し | 差し替える画像 |
| --- | --- | --- |
| 1 | ローマ字の文章を、自然な日本語へ | 変換後のメモアプリとSumibiキーボード |
| 2 | 英字QWERTYの1画面で入力 | ローマ字の入力途中 |
| 3 | 候補から、好みの表現を選択 | 複数候補とUndo |
| 4 | 選んだ範囲だけをAI変換 | 英文中のローマ字を選択し、「範囲を変換」を表示した画面 |
| 5 | 出力言語をプリセットで切り替え | 韓国語プリセットの効果を比較した画面 |
| 6 | 記号一覧も、ワンタップで | 展開した記号一覧とQWERTYキーボード |

## キャプチャの配置

実機またはSimulatorで撮影した縦画像を、次の名前で`captures`ディレクトリへ置きます。

```text
captures/01-natural-japanese.png
captures/02-qwerty-input.png
captures/03-candidates.png
captures/04-range-conversion.png
captures/05-writing-style-preset.png
captures/06-symbol-panel.png
```

画像がない間は、撮影内容を示すプレースホルダーが表示されます。配置した画像は端末枠の内側へ上寄せで拡大・トリミングされます。

## プレビューの生成

```sh
sh docs/app-store-screenshots/render-previews.sh
```

日本語版の生成先は`docs/app-store-screenshots/previews`、英語（アメリカ）版の生成先は`docs/app-store-screenshots/previews-en-US`です。英語版は同じ実画面を使用し、見出しと補足を英語で表示します。実際のキャプチャを配置した後に再実行すると、両方の提出候補画像を更新できます。

## 撮影前の安全確認

- APIキーを表示しない
- 個人名、メールアドレス、通知を写さない
- 文体プリセットは撮影用の一般的な名前と例文を使う
- 未実装の機能や実際と異なる変換結果を合成しない
- 6枚で外観、テーマ、時刻、文字サイズを揃える
