# 弓使い・魔法使いのゲーム演出（Issue #122）

設定の「遊び心のあるキーボード」に2テーマを追加する。初期OFF・既定ドラゴンは維持。テーマ選択だけではONにならない。

## 弓使いのチャージショット

- 弓はキャラクターの身長ほどの長弓。入力でエネルギーがたまるほど、弦を大きく引き絞り、矢を構える。
- 最大チャージでは引き手が大きく後ろへ動き、上半身ものけぞる。弓の両端もたわむ。矢を放つ瞬間は引き絞った姿勢を保ち、0.16秒で自然に戻す。
- 引き切る手前（チャージ80%以上）から、顔の両側から青い汗が0.75秒ごとに飛ぶ。各回は0.45秒でフェードし、短い間を置いて繰り返す。74%未満まで下がるか、矢を放つ・OFF・テーマ切替・非表示・「視差効果を減らす」ONで止める。しきい値付近の小さな揺らぎでは周期をリセットしない。
- 変換開始時に、短い反動とともに矢を左から右へ放つ。
- 低チャージでは1本、高チャージ（75%以上）では3本の矢。蓄積量が多いほど速く、長い軌跡を残す。
- 0.06秒の予備動作、0.60〜0.90秒の移動、最後0.28秒のフェード。相手や動物に当てる描写はしない。

## 魔法使いの白い魔法陣

利用者の希望により、異世界ファンタジーのような白い魔法陣を採用。特定作品の衣装・紋章は使わず、オリジナルのキャラクターと幾何学模様で表現する。

- 入力中、差し出した手の前に白い二重の魔法陣が現れる。円・三角形・短い幾何学の線がゆっくり回転する。
- 蓄積量に応じて魔法陣と中心の魔力が大きくなる。入力を休むとゲージ・魔法陣も小さくなり、空になると回転を止める。
- 白い線に紫の縁取りを付け、Light/Darkのどちらでも見えるようにする。
- 変換開始時、魔法陣から右へ白い光を放つ。魔力が多いほど太い光と多くの小さな光粒。0.12秒の予備動作、0.65〜0.85秒の移動、最後0.28秒のフェード。
- 左のアイコン予約幅を44ptから72ptへ広げ、魔法陣の上にステータス文字や候補が重ならないようにする。候補の横スクロールは維持。

## 共通

既存の打鍵エネルギーを使い、変換や範囲変換で放つ。追加候補では再発射しない。
変換結果を演出待ちにせず、文字列やAPI通信・料金を演出のために追加しない。
入力再開・キャンセルでは0.28秒で自然に消す。OFF・テーマ変更・非表示では完全にリセット。
「視差効果を減らす」ONでは回転・反動・飛翔を出さず、静的なチャージ表示のみ。
魔法陣・繰り返す汗がある間と短い発射中だけ30fps更新。空の状態・非表示・停止後に描画タイマーを残さない。
iOS 17以降。デバイスの画面サイズに応じて右端までの距離を計算する。

## アセット・制作プロンプト

組み込み画像生成を使用（CLI未使用）。いずれも正方形の透過PNG、64px以下に縮小デコード、nearest描画。写真や既存作品の画像は使わない。
弦・矢・魔法陣・光・反動はコードで描画する。
弓使いは後の調整で画像から弓本体も分離し、木の弓・引き手のメッシュ・体の傾き・汗をコードで描画する。

- [RPGArcher.png](../SumibiKeyboard/RPGArcher.png)
- [RPGWizard.png](../SumibiKeyboard/RPGWizard.png)

### 弓使い

```text
Use case: stylized-concept
Asset type: transparent 8-bit RPG archer character sprite for a 36pt-tall iOS keyboard bar.
Primary request: ONE original friendly chibi archer, full body in side view facing RIGHT, feet planted in a wide steady stance, warm brown short hair, teal-green tunic and short cape, brown boots. Clearly readable face. Left arm extends right holding a bow, right hand near chest ready to pull string; right half of sprite shows a small wooden bow curved to the right, relaxed string. No arrow yet: the app draws the arrow and stretching string during charge.
Composition: exactly ONE full-body sprite centered in a square canvas, transparent margin 8% on all sides, large head and compact body, bow about 80% of character height, bow at x=75% of canvas, grip near midheight. Character occupies left two thirds. Everything including bow and feet inside canvas.
Style: coarse square pixels like an original early 8-bit RPG, limited flat teal/brown/tan palette, dark pixel outline, crisp silhouette readable at 36px. No soft painting, gradients, glow or blur.
Background: genuine transparent alpha, no scene, floor, shadow, text or watermark.
Constraints: original generic fantasy design, no recognizable existing character, no pointed elf ears, no logos, no targets, no animals, no violence.
```

弦をアプリ側で動かすための編集：

```text
Use case: precise-object-edit
Input images: Image 1 is the exact archer sprite edit target.
Primary request: REMOVE ONLY THE BOWSTRING: the thin nearly vertical dark strand running from upper bow tip down past the grip to lower bow tip in the open gap left of the curved wooden bow. Leave that gap truly transparent. The app will draw and animate the string and arrow itself. Do not include an arrow.
Invariants: keep the character face, eyes, green teal cape/tunic, hands and pose, wooden curved bow, bow grip, boots, pixel art style, silhouette, scale and square composition EXACTLY unchanged. Keep all alpha transparency and fully transparent corners. No scenery, shadow, text or glow.
```

### 身長ほどの弓と大きな引き動作への調整

組み込み画像生成で弓だけを取り除き、顔・服・手足・位置は保持。保存先は `SumibiKeyboard/RPGArcher.png`。大きな木の弓と弦はアプリ側で独立描画し、チャージに合わせて動かす。
調整版のiOS Debugビルド・引き動作の計算テスト・既存回帰テストが成功。汗は当初1回のみだったが、利用者の希望で引き切る手前から定期的に飛ぶ仕様へ変更。周期・開始／停止のしきい値・無効化・不正値の自動テストが成功した。シミュレーターでは追加の打鍵なしで汗が3回繰り返すこと、間隔が空くこと、チャージが下がると止まることを描画比較で確認。発射の自然終了・キャンセル・5テーマ切替・停止の回帰確認も成功。Light/Darkの大きな弓・姿勢・汗を演出単体プレビューで確認済み。2026-10-07に調整版をiPhone 17eへ上書きインストールし、利用者が「分かりやすい表現になった」と実機確認した。

```text
Use case: precise-object-edit
Asset type: transparent 8-bit character sprite component for runtime bow animation.
Image 1: edit target, original green-tunic chibi archer.
Change ONLY one object: remove the wooden bow completely, and any remaining bowstring/arrow. Make every removed bow pixel outside the character transparent. Preserve the character's rightmost extended hand/fist exactly at its old position, as if gripping an invisible bow. Preserve the entire rear hand at chest. Do NOT remove or redesign hands or arms.
Keep character face, hair, tunic, cape, legs, boots, all proportions, exact pose, size, square canvas framing and original placement unchanged. The app will draw a much larger animated bow and string separately. Do not recenter or rescale the remaining character after removing bow.
Same coarse flat square-pixel art. Real transparent alpha outside character, including removed bow area and all four corners. No scene, glow, shadow, text, watermark or added objects.
```

### 魔法使い

```text
Use case: stylized-concept
Asset type: transparent 8-bit RPG wizard character sprite for a 36pt-tall iOS keyboard bar.
Primary request: ONE original friendly chibi wizard, full body side-three-quarter view facing RIGHT, big readable warm face with eyes visible, indigo pointed hat with a wide floppy brim, violet robe with pale turquoise trim, short boots. Rightward arm extends forward, open palm near x=80%, y=48% of canvas ready to gather and cast magic; other hand holds a small simple wooden staff close to body. No spell, orb, smoke or particles in the bitmap: the app animates these at the open palm.
Composition: ONE full-body sprite centered on a square canvas, genuinely transparent margins 8% on all four sides, large head, compact body, hat/palm/staff/feet completely inside. Open palm clear on the right edge of silhouette. Pleasant energetic casting-ready pose.
Style: coarse square pixels like an original early 8-bit RPG, limited flat violet/indigo/turquoise/tan palette, dark pixel outline, crisp silhouette readable at 36px. No gradients, soft painting, glow or blur.
Background: genuine transparent alpha, no scene, floor, shadow, text or watermark.
Constraints: original generic fantasy character, no recognizable existing wizard, no logos, no animals or violence.
```

## 確認

- 自動テスト：チャージ量による速度差、予備動作、移動の単調性、フェード、終了、不正値、設定の5テーマ保存とON/OFFの独立性。
- iOS Debugビルド成功。iOS 27シミュレーターの演出単体プレビューで、Light/Darkのチャージ・矢・白い魔法陣・魔法の強弱と32pt表示を確認した。描画比較で自然終了、キャンセル後のフェード、5テーマ切替、停止、不正な入力で古い演出が残らないことを検証した。既存のエネルギー・猫・設定チャットの回帰テストも成功。
- 画像：1254×1254・alpha保持・四隅alpha 0・透明部分60%以上・柔らかい背景のにじみなし。
- [ ] Light/Dark、縦40pt・横32ptで顔・弦・白い魔法陣が見える
- [ ] チャージで弦が引かれ、休止で戻る
- [x] 身長ほどの大きな弓、引き手・上半身・弓のたわみが分かり、引き切る手前から定期的に汗が飛ぶ
- [ ] 魔法陣が大きくなり回転し、休止で収まる
- [ ] 低／高チャージで矢・魔法の強さが変わる
- [ ] 候補・Undo・範囲変換・追加候補の操作を妨げない
- [ ] キャンセル・OFF・テーマ切替・非表示で描画が残らない
- [ ] 「視差効果を減らす」ON/OFFの切替で装飾の動きを抑制できる

チェックリストは実機確認用。自動・シミュレーター確認と実機確認を区別する。2026-10-07にiPhone 17eへ上書きインストールし、起動と利用者による弓使いの演出確認が完了。他の未チェック項目は一括で確認済みとはしない。
