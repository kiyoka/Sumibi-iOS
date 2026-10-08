# ゲーム演出：キャラクターと打鍵エネルギー（Issue #122）

## 完成対象：4種類の演出

初期状態はOFF。設定の「遊び心のあるキーボード」で「ゲーム演出」をONにする。
テーマは独立したプルダウンで選択する。選択肢は「RPG風ドラゴン」「宇宙船のレーザー砲」「獲物を狙うペルシャ猫」「魔法使いの白い魔法陣」。
既定はドラゴンのまま。テーマの変更だけではゲーム演出はONにならない。
ゲーム演出ONのとき、候補バー左側のキャラクターをタップしてもテーマを切り替えられる。
順番はドラゴン → 宇宙船 → 猫 → 魔法使い → ドラゴンで循環する。通常の文字キーのタップでは切り替えない。
選択は設定に保存し、アプリへ戻ったときのテーマ選択にも反映する。切替時はチャージと古い演出をリセットするが、入力文字・候補・変換通信は維持する。OFFでは切替ボタンを隠し、ゲーム演出を勝手にONにしない。
タップ領域は左のキャラクター予約幅だけで、候補ボタン・メッセージ・候補の横スクロールに重ねない。VoiceOverでも現在のテーマと次のテーマが分かる。
以前の5テーマ版では、循環・保存・ON/OFF独立の自動テストとiOS Debugビルドが成功。iOS 27シミュレーターで実際のキーボードを組み込み、10回のボタン操作で2周すること、タップ領域が候補側へはみ出さないこと、OFF中の古いタップが無視されること、ラベルとアクセシビリティ情報が維持・更新されることを確認した。2026-10-07にiPhone 17eへ上書きインストールし、利用者からタップ切替が「うまく動きました」と実機確認を得た。
2026-10-08の要件変更で弓使いを削除し、格闘ゲーム風も不要とする。Issue #122のゴールはドラゴン・宇宙船・猫・魔法使いの4種類。過去の弓使い設定はドラゴンにフォールバックし、ゲーム演出のON/OFFを保持する。4テーマへの整理後の実機確認は以前の確認と区別する。

既存の候補バーの左の炭火アイコンを、選択したテーマのキャラクターに置き換える。
帯の高さ（縦40pt／横32pt）は変えず、左の予約幅だけ28ptから44pt（魔法使いは72pt）にする。
通常の文字・数字・記号・空白のタップでチャージし、帯の下端のゲージに表示する。
削除、長押しリピート、Shift、記号パネル切替、改行、Undo、候補選択では増加しない。

チャージは直前のタップ間隔から計算し、1タップにつき4〜12%、上限100%。
速い打鍵ほど1タップの獲得量も増える。約12打鍵／秒で最大になり、それ以上は上限を維持する。
打鍵から0.3秒は保持し、その後は毎秒16%ずつ自然に減衰する（従来の32%から半分の速度に変更）。満タンから休むと約6.6秒で空になる。全テーマ共通。打鍵1回でためる量と速度判定は変更しない。
減衰は経過時刻で計算し、表示のフレーム数に依存しない。4ptのバーを30Hzで滑らかに更新する（ドラゴン：オレンジ→黄色、宇宙船：青→シアン、猫：オレンジ→ピンク、魔法使い：紫→シアン）。
低速入力ではタップ間にも減衰し、高速入力ほど蓄積が進む。ゲージが空になったら更新タイマーは停止する。
入力先の変更、キーボードを閉じる、モードOFFではリセットする。
入力内容は渡さず、時刻だけを端末内で扱う。保存・外部送信しない。

通常変換・範囲変換の通信開始時に力を消費し、左から右に炎・レーザー・猫のダッシュ・魔法を出す。
チャージに応じて炎の幅・厚み・長さ（約0.95〜1.5秒）を変える。
炎は候補文字・ボタンの背面に描画し、最後は自然にフェードアウトする。
変換結果の表示は演出完了を待たない。追加候補取得では再発射しない。
通信開始前のエラーではチャージを消費せず、開始後の失敗では消費済みとする。
キャンセル・入力再開は残っている炎をフェードアウトさせる。

ゲーム演出中は候補バーの従来の光の走査を重ねない。変換キーの演出は維持する。
OFFではキャラクター・ゲージ・放出演出を非表示にし、従来の帯と炭火アイコンに戻す。
追加API・効果音・振動はなし。iOS 17以降で利用可。
「視差効果を減らす」ONでは火炎・拡大・反動・猫の動き・ゲージの補間アニメーションは出さず、ゲージの値更新のみ行う。
炎の描画は短い演出中だけ30fpsで行い、終了・非表示・キーボード切替時には停止する。

## 「Sumibiに相談」での紹介

相談画面に「遊び心のあるキーボードについて教えて」の質問例を追加。
会話用の操作ガイドには、全4テーマの名前・特徴、初期OFF、設定画面でのON/OFFとテーマ選択、キャラクタータップによる循環、チャージと休止時の減衰、通常／範囲変換での放出を含める。
演出による追加API通信がないこと、変換結果・料金に影響しないこと、「視差効果を減らす」と猫の拡大ポーズも説明できる。
テーマ名と順序は設定のプルダウンと同じ定義から取得する。ゲーム設定の現在値は会話に送信しないので推測しないよう指示する。
「猫にして」「ゲーム演出をOFFにして」などは設定画面の操作を案内するだけとし、チャットの変更対象4項目は拡張しない。
モックAPIで紹介・テーマ一覧・切替方法・料金・動かない場合・OFFの質問と継続会話を確認する。これは実LLMの回答品質の検証ではなく、説明の送信・履歴維持・保存設定が変わらないことの回帰確認。実AIとの会話は実機で別途確認する。

## 実機確認

4テーマへの整理版：4テーマの順序・2周の保存、旧弓使い設定からのフォールバックとON/OFF保持、相談チャットから弓使いを紹介しないこと、魔法使いの従来タイミング、エネルギー・猫の動作と画像切り出しの回帰テストが成功。シミュレーター・実機向けDebugビルドが成功し、実機用アプリに弓使いの画像が残っていないことも確認。2026-10-08にiPhone 17eへ上書きインストールし、アプリの起動に成功。利用者から4テーマ版の実機動作確認完了の報告を得た。以下の詳細項目や実AIによる相談回答は個別の確認報告と区別する。

iOS 27シミュレーターの実際のKeyboardViewControllerで、8回のキャラクターボタン操作による4テーマの2周・保存、ON/OFFと古いタップの無効化、タップ領域、候補／ステータス文字への非干渉、VoiceOverの現在／次テーマ、魔法陣用の幅を確認。作成される演出ビューが4つだけであること、各演出の自然終了・キャンセル・明示的な停止後に描画タイマーや猫の静止タイマーが残らないことも検証した。Light/Darkを明示適用した描画を確認し、2026-10-08 23:22 JSTにプレビューの全検証が成功。プレビューはAPI通信を行わず、正常終了時に元のゲーム設定へ戻す。自動確認と実機の主観的な操作感確認は区別する。

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
- [ ] 4テーマを切り替えると表示が変わり、前のチャージ・放出演出が残らない
- [ ] 左のキャラクターを繰り返しタップすると4テーマを一周してドラゴンに戻り、設定画面にも選択が残る
- [ ] キャラクター切替が文字入力・候補選択・候補の横スクロールを妨げず、OFFでは切り替わらない
- [ ] 宇宙船では低チャージの短い光弾、高チャージの太いレーザーが表示される

宇宙船の演出・制作記録は [SPACE_LASER_GAME_MODE_JA.md](SPACE_LASER_GAME_MODE_JA.md) を参照。
猫の演出・制作記録は [PERSIAN_CAT_GAME_MODE_JA.md](PERSIAN_CAT_GAME_MODE_JA.md) を参照。
白い魔法陣の演出・制作記録は [FANTASY_GAME_MODE_JA.md](FANTASY_GAME_MODE_JA.md) を参照。
猫は右端でピンクのボールをくわえ、こちらを向いた2倍の正面ポーズで2秒間静止した後フェードする。本物の動物は描かない。猫テーマのみ、右上にポーズ用の余白を確保する。

## アセット制作記録

画像生成の組み込みツールを使用（CLIは未使用）。
保存先：[RPGDragon.png](../SumibiKeyboard/RPGDragon.png)
元画像の透過を維持。実行時はImageIOで64px以下に縮小デコードし、nearestフィルターで粗いドットを保ちながら拡張のメモリを抑える。
炎・ゲージ・反動はアプリ内で描画する。炎の上でもステータス文字が読めるよう、ゲーム演出ON時だけ小さな不透明の背景を付ける。

初回（16ビット風）の生成プロンプト：

```text
Use case: stylized-concept
Asset type: transparent pixel-art sprite for an iOS keyboard candidate bar
Primary request: one original RPG dragon, facing RIGHT, full-body side profile, ready to breathe fire from its open mouth toward the right. The actual animated fire will be drawn separately by the app; do NOT include any fire in this sprite.
Style: charming classic 16-bit RPG pixel art, crisp square pixels, bold readable silhouette and dark outline, compact red-orange dragon with small wings, horns, curled tail and cream belly. Recognizable at only 36 points tall.
Composition: exactly ONE dragon centered and filling most of a square canvas, all body parts fully visible, mouth at the right edge of the head. No sprite sheet, no panels, no multiple poses.
Backdrop: truly transparent background, no scenery, no floor, no shadow outside the sprite.
Constraints: original character, no existing game characters, no text, no logo, no watermark, no flame. Preserve a real alpha channel.
```

### 8ビット風への調整

2026-10-07：利用者の要望に合わせ、同じキャラクターを大きな色面・粗いドット・少ない陰影に描き直した。
画像生成の組み込みツールで既存画像を編集し、同じアセット名に差し替えた。透過は維持。
炎は縦8段を目安に4〜5ptのドットで描き、輪郭・長さをグリッドに揃える。
固定の赤・オレンジ・黄色の3色を重ね、アンチエイリアスは無効。
形の揺らぎは12fps相当、終了・キャンセル時のフェードは従来の30fpsで更新する。
エネルギー計算・候補操作・演出時間・「視差効果を減らす」の挙動は変更しない。
調整版はiOSアプリのDebugビルド・エネルギー計算テストが成功。
iOS 27シミュレーターの演出単体プレビューでLight/Darkのドット表現とステータス文字の可読性を確認。

### 火炎中のキャラクターアクション

同じ画像を8×8の接続したメッシュで描画し、画像の追加なしで翼・首を別々に動かす。
開始時は約0.34秒の軽いのけぞり（最大約10度）を付ける。
火炎中は翼を約4.5回／秒で上下させ、首・頭を約2.5回／秒で小さく上下させる。
首の動きに合わせて炎の出発点も移動する。
最後の0.25秒、またはキャンセル時の0.28秒で動きを弱め、元の姿勢に戻す。
炎と同じ30fpsの描画タイマーを共有し、終了・非表示・OFF・「視差効果を減らす」ONで静止姿勢に戻る。待機中の更新タイマーは追加しない。
Debugビルド成功。単体プレビューでLight/Dark・40pt/32ptの帯を撮影し、のけぞり・羽ばたきの姿勢変化と終了後の静止復帰を確認。
署名付きビルドをiPhone 17eに上書きインストールし、起動を確認。利用者の実機確認後、「一旦このアートワークでいきます」との了承を得た。

最終編集プロンプト（組み込みツール、CLI未使用）：

```text
Use case: style-transfer
Asset type: transparent 8-bit RPG sprite for an iOS keyboard candidate bar
Input images: Image 1 is the edit target, the existing original red-orange dragon.
Primary request: redraw this same dragon one step more retro, as a genuinely coarse, low-resolution 8-bit game sprite. Simplify the silhouette and details into large, clearly visible square pixels, as if drawn on a 32 by 32 pixel grid and enlarged with nearest-neighbor.
Keep: one red-orange dragon facing RIGHT, full body, wings, cream belly, horns, curled tail, open mouth ready to breathe fire. Preserve its identity and compact pose, but simplify aggressively.
Style: authentic early console RPG sprite, flat limited palette of about 6 opaque colors, single-pixel dark outline, large solid color clusters. No gradients, no smooth shading, no tiny textured pixels, no antialiasing.
Composition: exactly ONE centered dragon filling most of a square transparent canvas; all parts visible; no sprite sheet.
Constraints: actual transparent background and alpha, no backdrop, no shadow, no flame (the app animates it), no lettering, no watermark, no existing game character. The visible pixels should be much coarser than in the source.
```
