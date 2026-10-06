# ゲーム演出：RPG風ドラゴン（Issue #122）

## 今回の試作

初期状態はOFF。設定の「遊び心のあるキーボード」で「ゲーム演出」をONにする。
テーマは独立したプルダウンで選択する。今回の選択肢は「RPG風ドラゴン」のみ。
格闘ゲーム風の制作は後続とし、まだIssue全体の完了とはしない。

既存の候補バーの左の炭火アイコンをドラゴンに置き換える。
帯の高さ（縦40pt／横32pt）は変えず、左の予約幅だけ28ptから44ptにする。
通常の文字・数字・記号・空白のタップでチャージし、帯の下端のゲージに表示する。
削除、長押しリピート、Shift、記号パネル切替、改行、Undo、候補選択では増加しない。

チャージは直前のタップ間隔から計算し、1タップにつき4〜12%、上限100%。
速い打鍵ほど1タップの獲得量も増える。約12打鍵／秒で最大になり、それ以上は上限を維持する。
打鍵から0.3秒は保持し、その後は毎秒32%ずつ自然に減衰する。満タンから休むと約3.4秒で空になる。
減衰は経過時刻で計算し、表示のフレーム数に依存しない。4ptのオレンジ→黄色のバーを30Hzで滑らかに更新する。
低速入力ではタップ間にも減衰し、高速入力ほど蓄積が進む。ゲージが空になったら更新タイマーは停止する。
入力先の変更、キーボードを閉じる、モードOFFではリセットする。
入力内容は渡さず、時刻だけを端末内で扱う。保存・外部送信しない。

通常変換・範囲変換の通信開始時に力を消費し、左から右に火を吹く。
チャージに応じて炎の幅・厚み・長さ（約0.95〜1.5秒）を変える。
炎は候補文字・ボタンの背面に描画し、最後は自然にフェードアウトする。
変換結果の表示は演出完了を待たない。追加候補取得では再発射しない。
通信開始前のエラーではチャージを消費せず、開始後の失敗では消費済みとする。
キャンセル・入力再開は残っている炎をフェードアウトさせる。

ゲーム演出中は候補バーの従来の光の走査を重ねない。変換キーの演出は維持する。
OFFではドラゴン・ゲージ・炎を非表示にし、従来の帯と炭火アイコンに戻す。
追加API・効果音・振動はなし。iOS 17以降で利用可。
「視差効果を減らす」ONでは火炎・拡大・反動・ゲージの補間アニメーションは出さず、ゲージの値更新のみ行う。
炎の描画は短い演出中だけ30fpsで行い、終了・非表示・キーボード切替時には停止する。

## 実機確認

自動テスト：チャージの速度差・上限・入力休止時の減衰・表示周期への非依存・消費時刻・リセット、不正時刻、設定の初期OFF・保存・選択の独立性を確認済み。
既存の設定チャット・変換クライアントのモック回帰テスト、iOS Debugビルドも成功。
iOS 27シミュレーターの演出単体プレビューで、Light/Darkのドラゴン・炎・ステータス文字の可読性を確認済み。
初回のドラゴン試作は、iPhone 17eで利用者から「良い感じ」とのフィードバックあり。
休止で下がるメーターの調整版も、iPhone 17eで利用者から「非常に良い感じ」との実機フィードバックあり。
以下の詳細な確認項目は個別の確認後にチェックする。

- [ ] 未設定・OFFでは従来の帯が表示される
- [ ] ONにするとドラゴンが表示され、ゆっくり／速い打鍵でチャージ速度が変わる
- [ ] 入力を休むとバーが滑らかに減り、再開すると現在値から蓄積が再開する
- [ ] 通常変換・範囲変換で左から右へ炎が出て、強さが蓄積量で変わる
- [ ] 結果の表示を待たせず、候補・Undo・追加候補・キャンセルが操作できる
- [ ] 数字・記号・空白はチャージ、削除・リピート・改行は非対象
- [ ] OFF・キーボード切替・入力先変更でリセットされる
- [ ] Light/Dark・縦横・記号展開時に候補と文字が読める
- [ ] 「視差効果を減らす」ONでは装飾の動きがなく、ゲージの値は更新される。OFFに戻して再度変換できる
- [ ] 長めの入力・連続変換でも引っかかりや描画の残りがない

## アセット制作記録

画像生成の組み込みツールを使用（CLIは未使用）。
保存先：[RPGDragon.png](../SumibiKeyboard/RPGDragon.png)
元画像の透過を維持。実行時はImageIOで132px以下に縮小デコードし、拡張のメモリを抑える。
炎・ゲージ・反動はアプリ内で描画する。炎の上でもステータス文字が読めるよう、ゲーム演出ON時だけ小さな不透明の背景を付ける。

最終生成プロンプト：

```text
Use case: stylized-concept
Asset type: transparent pixel-art sprite for an iOS keyboard candidate bar
Primary request: one original RPG dragon, facing RIGHT, full-body side profile, ready to breathe fire from its open mouth toward the right. The actual animated fire will be drawn separately by the app; do NOT include any fire in this sprite.
Style: charming classic 16-bit RPG pixel art, crisp square pixels, bold readable silhouette and dark outline, compact red-orange dragon with small wings, horns, curled tail and cream belly. Recognizable at only 36 points tall.
Composition: exactly ONE dragon centered and filling most of a square canvas, all body parts fully visible, mouth at the right edge of the head. No sprite sheet, no panels, no multiple poses.
Backdrop: truly transparent background, no scenery, no floor, no shadow outside the sprite.
Constraints: original character, no existing game characters, no text, no logo, no watermark, no flame. Preserve a real alpha channel.
```
