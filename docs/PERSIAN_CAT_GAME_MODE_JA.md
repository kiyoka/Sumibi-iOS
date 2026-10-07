# ペルシャ猫のゲーム演出（Issue #122）

## 操作と見せ方

設定の「遊び心のあるキーボード」でゲーム演出をONにし、テーマ「獲物を狙うペルシャ猫」を選ぶ。
初期OFF・既定テーマのドラゴンは変更しない。テーマ選択だけではONにならない。

利用者の猫の写真を参考に、クリーム色の毛・丸く平たい顔・ピンクの鼻・ふさふさのしっぽを持つ8ビット風キャラクターを制作。
追加の写真に合わせて濃い眉のような線を減らし、優しい目元に調整する。
元の写真・室内・写真の個人情報はリポジトリにもアプリにも含めず、生成した透過画像だけを使う。

- 入力中は左側で低く構え、右側の小さなドット絵の布製おもちゃを狙う。水色・ピンクの帯・黄色いひもで、本物の動物ではないと分かる見た目にする。
- エネルギーが残っている間はお尻・しっぽをふりふりし、頭・前足の動きは控える。
- 通常変換・範囲変換の通信開始で右へ走る。しっぽを上げた4コマの走りをループする。
- 右端に到達すると同じ布製おもちゃをくわえる正面ポーズに変わり、こちらを見たまま2秒間静止する。
- 蓄積量が多いほど走る速度・コマの切替速度・足元の小さなほこりを強める。
- 短い走り出し（0.08秒）の後に加速し、約0.68〜1.03秒で右端に到達する。2秒間こちらを見て、最後0.18秒でフェードする。
- 終了後は左側の構えに戻る。入力再開・キャンセルでは0.28秒でフェードし、前の演出が残らないようにする。
- 結果を待たせず、候補・Undo・追加候補の操作は従来通り。追加候補では再度走らない。
- OFF・テーマ変更・キーボード非表示では動き・エネルギーをリセットする。
- 「視差効果を減らす」ONでは猫は静止し、ゲージの値だけ更新する。

候補帯は縦40pt・横32ptのまま。猫は候補・ステータス文字の背面で描画し、操作を受け取らない。
猫テーマのみ、候補一覧とメッセージの右端余白を8ptから54ptにして獲物と捕獲後のポーズを見えるようにする。候補は従来通り横へスクロールできる。他のテーマとOFF時は8ptのまま。
チャージ速度・入力休止時の減衰はドラゴン・宇宙船と同じ。入力内容は演出に渡さず、API通信や料金を増やさない。
ゲージが空、演出終了、非表示のときは描画タイマーを停止する。
捕獲後の静止中も描画用タイマーを止め、単発タイマーでフェードの開始だけを予約する。入力再開・OFF・非表示・テーマ切替では予約も破棄する。

## アセット

画像生成の組み込みツールを使用（CLI未使用）。透過を維持して保存する。

- [PersianCatHunt.png](../SumibiKeyboard/PersianCatHunt.png)：構え。実行時に64px以下へ縮小デコード。
- [PersianCatRun.png](../SumibiKeyboard/PersianCatRun.png)：2×2の4コマ。128px以下へ縮小デコードし、実行時に4分割。
- [PersianCatCatch.png](../SumibiKeyboard/PersianCatCatch.png)：カラフルな布製おもちゃをくわえてこちらを見る静止ポーズ。64px以下へ縮小デコード。

nearest描画とアンチエイリアス無効でドット感を保つ。
構えは接続した8×8メッシュで後ろ半分を左右に動かす。
走りは各コマの切替と帯内の移動で描く。元の高解像度画像をフルサイズで展開しない。

## 確認

チャージ・設定チャットの既存回帰テストと猫の移動計算テストが成功。
走りの強弱、単調な移動、4コマの範囲、フェード、終了、不正値を検証。

- [ ] Light/Dark・40pt/32ptの候補帯で、顔・しっぽ・ステータス文字が見える
- [ ] 入力中にお尻が揺れ、入力休止でゲージと動きが収まる
- [ ] 変換で右へ走り、低／高チャージの速度が変わる
- [ ] 入力中の目標とくわえたものが、動物ではなく布製おもちゃだと分かる
- [ ] 右端でおもちゃをくわえた正面ポーズになり、2秒間静止した後フェードして戻る
- [ ] 候補・Undo・範囲変換・追加候補を妨げない
- [ ] テーマ切替・OFF・キャンセルで描画が残らない
- [ ] 「視差効果を減らす」ONで静止し、OFFに戻すと演出が再開する

顔拡大版と捕獲後の正面ポーズ追加版はiPhone 17eに上書きインストールし、起動を確認した。利用者から正面ポーズも良いとの確認を得た。布製おもちゃ・2秒版もiPhone 17eに上書きインストール済み。ただし端末がロックされていたため、この版の自動起動はできなかった。自動・シミュレーター確認と利用者の実機確認は区別する。
iOS Debugビルド成功。iOS 27の演出単体プレビューで、Light/Dark・40pt/32ptの構えと4コマの走り、強弱による移動の差、終了後の復帰を確認した。
描画の比較テストで停止・3テーマの切替・切替後の復帰・キャンセルのフェード後に描画が残らないことを確認した。
両PNGは1254×1254で透明な四隅を保持。背景の透明部分と、柔らかい光のにじみが残っていないことも検証した。

## 制作プロンプト

### 布製おもちゃへの変更

2026-10-07：利用者の希望により、本物のネズミに見える描写をやめ、動物型ではない布製おもちゃに統一した。猫の顔・ポーズ・しっぽは保持し、組み込み画像生成で口元の小物だけを変更（CLI未使用）。入力中の右端のおもちゃも同じ色と形をコードで描画する。こちらを見る時間は2秒。

保存先は `SumibiKeyboard/PersianCatCatch.png`。生成プロンプト：

おもちゃ版のiOS Debugビルドと2秒の静止・フェードの移動計算テストが成功。iOS 27の演出単体プレビューでLight/Dark・40pt/32ptの表示を確認した。描画比較で2秒の静止、自然終了、走行中／静止中のキャンセル、テーマ切替、古い予約の破棄を確認した。透過PNGの四隅はalpha 0〜1/255で、可視の背景はなく、透明部分31%・半透明部分2%。実機のおもちゃ版確認は未実施。

```text
Use case: precise-object-edit
Asset type: transparent 8-bit Persian cat celebration sprite for a tiny iOS keyboard bar.
Input images: Image 1 is the edit target. Change ONLY the gray mouse held in the cat's mouth into an unmistakably artificial, brightly colored cat toy.
Toy: a small horizontal padded fabric cylinder, turquoise blue with two bright pink bands, visible chunky stitched seam, and a short yellow yarn loop dangling at one end. A simple sewn cloth cat kicker toy, NOT shaped like any animal. No eyes, ears, legs, nose or animal tail. Recognizable as a colorful toy even at 36pt height. Held gently in exactly the same mouth position and about the same size as the old mouse.
Invariants: preserve the cat's exact face, gentle golden eyes, pink nose, expression, comical large-head proportions, paws, cream/tan fur, raised fluffy tail, pose, framing and coarse square-pixel style unchanged. Preserve full-body square composition and transparent padding. Do not redesign or enlarge the cat.
Style: same 8-bit coarse square-pixel art, flat colors, no gradients or soft halo. Genuinely transparent alpha background outside the sprite; no scenery, shadow, text or watermark.
Avoid: any living prey, rodents, realistic mouse, dead animal, wounds, blood, gore, animal-shaped toy.
```

以下は過去の制作記録。ネズミのプロンプトは初版の記録であり、現在のアセットは上記のおもちゃ版。

### 獲物をくわえてこちらを見るポーズ

2026-10-07：組み込み画像生成で同じ猫の正面ポーズを制作（CLI未使用）。構えと走りの画像は変更しない。
入力休止ではなく変換演出の終わりに表示し、その後フェードする。候補操作や変換結果を待たせない。初版の静止時間3秒は、後の利用者確認を受けて2秒へ短縮した。
捕獲時刻・静止時間・フェード・強弱・不正値を移動計算テストで検証する。
捕獲ポーズ追加版のiOS Debugビルド成功。iOS 27の演出単体プレビューでLight/Dark・40pt/32ptの正面ポーズを確認した。
描画比較で、右端の捕獲姿勢が静止したまま維持されること、自然終了後の復帰、走行中／捕獲後のキャンセル、捕獲後のテーマ切替、破棄したタイマーで古い演出が復活しないことを確認した。

生成プロンプト：

```text
Use case: precise-object-edit
Asset type: transparent 8-bit Persian cat CAPTURED-PREY celebration sprite for a tiny iOS keyboard bar
Input images: Image 1 is the exact cat identity/style and big-head proportion reference.
Primary request: make ONE new pose of this SAME cream Persian cat after it catches a small gray pixel mouse: gently hold the small mouse across its mouth and TURN ITS FACE DIRECTLY TOWARD THE VIEWER with calm proud, soft eyes, as if saying "look what I caught". Keep the full face and both eyes clearly readable above the mouse. Hold a quiet still pose, not running. The body may be three-quarter facing right, but the FACE looks straight at us. Tail stays proudly UP.
Identity invariants: preserve the same big rounded head, flat short Persian muzzle, little pink nose, warm golden-dark eyes, fluffy cream cheeks, tiny ears, warm tan markings and gentle expression from the reference. Same comical head/body proportion, do not invent a different generic cartoon cat.
Prey: tiny simple gray pixel mouse with a pink ear and thin tail, safely and gently held, no wounds, blood, gore, eating, teeth or menacing expression. It should not cover the cat's eyes or dominate the face.
Composition: exactly ONE full-body cat centered on a SQUARE canvas, all ears/paws/tail visible, compact stance, modest transparent padding, similar total scale to reference. NOT a sprite sheet. Recognizable at 36pt tall.
Style: same coarse square-pixel 8-bit game art, limited flat cream/tan/brown palette plus gray mouse. No gradients, soft fur painting, fine texture, glow, shadow or antialiasing.
Background: genuinely transparent alpha outside sprites, no scenery, floor, text, accessories, watermark or other characters.
```

初回の構え：

```text
Use case: stylized-concept
Asset type: transparent 8-bit Persian cat sprite for an iOS keyboard candidate bar
Input images: Image 1 is a character-identity reference only, the user's real Persian cat. Do not reproduce the room, towels, or pose in the photo.
Primary request: make ONE charming, elegant Persian cat based on that photo in a low stalking pose, full body facing RIGHT. Front shoulders and round flat face are low, front paws reach forward, fluffy hindquarters raised a little, ready to wiggle its rump and chase prey. The large fluffy tail rises upward behind the rump, fully visible.
Identity: long cream/beige fur with warm caramel shading and darker tan face, broad flat round Persian face, tiny pink nose, small ears, fluffy white-cream chest and cheeks. Use simple dark attentive eyes, not sleeping eyes. Keep a dignified rather than comic expression.
Style: authentic coarse 8-bit console pixel art, visibly large square pixels as if on a 32 by 32 grid enlarged nearest-neighbor, limited flat palette, dark warm-brown outline, no gradients or fur texture.
Composition: exactly one side-profile cat centered in a square canvas, fill most of canvas, all paws and raised tail visible, modest transparent padding. No sprite sheet.
Constraints: genuinely transparent alpha background; no prey (drawn separately by app), no scenery, no floor, no shadow, no words or watermark, no accessories, no existing fictional character.
```

初回の走り：

```text
Use case: stylized-concept
Asset type: transparent 2-by-2 RUN CYCLE sprite sheet for an iOS keyboard
Input images: Image 1 is the exact cat character/style reference. Preserve this cream Persian cat's flat face, tan face mask, pink nose, long fluffy cream fur and large upright fluffy tail. Do not include the stalking pose.
Primary request: four distinct full-body animation frames of this SAME elegant Persian cat galloping RIGHT. Tail is held proudly UP in every frame (never horizontal or lowered). Head aims to the right toward prey. Cats have four paws, no extra limbs.
Layout: exact regular 2 by 2 grid on a square transparent canvas, four equal square cells, no drawn grid lines. One cat centered in each cell with identical scale, same head/body proportions, same clear transparent margin on every side. No sprite crosses its cell boundary. All tail tips and paws visible in every cell.
Frame sequence reading order: top-left front legs reaching forward/hind legs pushing; top-right gathered legs underneath body; bottom-left front legs planted/hind legs coming forward; bottom-right airborne extended stride. Give clearly DIFFERENT leg positions for a looping gallop, while keeping head and tail location consistent.
Style: use fewer, larger square pixels than the reference; genuine coarse 8-bit sprite appearance, limited flat warm cream/tan/brown palette, no fine fur texture, no smooth shading, no antialiasing.
Constraints: real transparent alpha everywhere outside the four cats; no text or frame numbers, no border, no shadows, no ground, no scenery, no prey or accessories, no existing fictional character.
```

顔の表情調整（途中版）：

```text
Use case: character-consistency.
Edit target: the previously generated single transparent crouching Persian cat sprite visible in the recent conversation images (NOT the 2-by-2 running sheet).
Facial identity reference: the user's latest real cat photo, showing a cream Persian cat sitting on a wooden floor and turning its face to the right. Use that gentler face. The older sleeping photo is not the requested face reference.
Change ONLY the crouching sprite's face: dignified gentle expression, relaxed eyelids, warm attentive dark/golden eyes, flat round Persian muzzle, small pink nose and fluffy cream cheeks. Remove heavy angled dark eyebrow lines and the angry scowl. Lighten the tan face shading around the eyes. No exaggerated cartoon smile.
Preserve exactly the cream/beige body, the low stalking pose, paws, raised fluffy tail, coarse square-pixel 8-bit style, limited flat palette, full-body composition and scale. No other cats. No sheet. No photo background, scenery, floor, shadow, text or accessories. Genuine transparent alpha background.
```

顔の最終調整（元の構え・走りの姿勢を維持）：

```text
Use case: precise-object-edit
Image 1: edit target. Image 2: supporting FACE EXPRESSION reference only.
Change only the faces in Image 1 to the gentle, relaxed Persian expression in Image 2. Remove thick angled angry eyebrows. Warm soft dark-golden eyes, cream rounded cheeks, small pink flat nose. Not fierce, no comic grin.
Keep EXACTLY Image 1's composition, canvas aspect ratio, body silhouette, size, placement, leg poses, raised tail, pixel style and palette. Do not adopt Image 2's body pose or proportions.
Background must be 100% TRANSPARENT alpha, no brown glow, no halo, no shadow, no ambient color outside cat pixels, no floor, text or decoration. Hard pixel silhouettes.
There is ONE crouching stalking cat in Image 1. Preserve its low head/front paws and slightly raised rump. Return ONE sprite on the same square canvas.
```

```text
Use case: precise-object-edit
Image 1: edit target. Image 2: supporting FACE EXPRESSION reference only.
Change only the faces in Image 1 to the gentle, relaxed Persian expression in Image 2. Remove thick angled angry eyebrows. Warm soft dark-golden eyes, cream rounded cheeks, small pink flat nose. Not fierce, no comic grin.
Keep EXACTLY Image 1's composition, canvas aspect ratio, body silhouette, size, placement, leg poses, raised tail, pixel style and palette. Do not adopt Image 2's body pose or proportions.
Background must be 100% TRANSPARENT alpha, no brown glow, no halo, no shadow, no ambient color outside cat pixels, no floor, text or decoration. Hard pixel silhouettes.
Image 1 is a 2 by 2 RUN CYCLE sheet: preserve its exact four equal square cells and all four DIFFERENT running leg poses. Apply gentle face consistently to ALL four cats. Keep tail UP and every sprite within its cell. Return the same square 2 by 2 sheet with no drawn grid lines.
```

### 顔を大きくしたコミカルな比率への調整

最終の走り画像の余白調整プロンプト：

```text
Use case: precise-object-edit
Asset type: transparent pixel-art 2-by-2 animation sprite sheet.
Image 1: EDIT TARGET, big-headed Persian run sheet. Image 2: big-headed Persian facial identity reference.
Change ONLY layout/padding of Image 1. Each cat MUST be entirely inside its own exact equal square quadrant, with a generous fully transparent 8% margin INSIDE ALL FOUR sides of its cell. In particular, the top-left cat's big head must not cross the central vertical boundary into the top-right cell. No residual pixels from a neighboring cat may occur in another cell.
Keep exactly the FOUR DIFFERENT running poses and order, all facing RIGHT, tail proudly UP in ALL frames. Keep the same big head/body ratio, gentle photo-inspired Persian face, golden-dark eyes, small pink nose, round cream fluffy cheeks, flat muzzle, tiny ears, cream/tan coat, coarse square pixels and flat palette. SAME scale for all four cats. Do not reduce only the heads; scale whole sprites uniformly just enough to make transparent gutters.
Square canvas, exact regular 2 by 2 grid, no drawn grid lines. Alpha must be 0 throughout margins and central horizontal/vertical gutters. No background, glow, halo, shadow, floor, text, numbers, extra characters, accessories or scenery.
```

2026-10-07：写真由来の顔立ち・優しい表情は保ち、頭と顔を大きくして体をコンパクトにする。
構えと走り4コマを同じ比率に揃える。候補帯や猫の表示領域の大きさは変更しない。
お尻のメッシュ変形は左側に限定し、大きな顔の目・鼻が揺れで歪まないようにする。
組み込み画像生成で既存アセットを編集した（CLI未使用）。
走りはコマ内の透明な余白も調整し、隣のコマが混入しない配置にした。
顔拡大版の移動計算テスト・iOS Debugビルドが成功。Light/Dark・40pt/32ptの演出単体プレビューで確認した。
最終の走り画像は中央のコマ境界に目に見える不透明な画素がないことを検証し、隣のコマの断片が見えないことをプレビューでも確認した。停止・テーマ切替・キャンセル後の描画比較テストも成功。

構えの編集プロンプト：

```text
Use case: precise-object-edit
Asset type: transparent 8-bit Persian cat sprite for a tiny 36pt-tall keyboard bar
Input images: Image 1 is the existing crouching cat EDIT TARGET and facial identity reference.
Primary request: give this SAME cat a much bigger HEAD AND FACE, a charming comical big-headed proportion, so its face is clearly visible at very small size. Enlarge the whole head, fluffy cheeks, eyes/nose/muzzle together by about 1.6x relative to the body. The head should occupy approximately 55-60% of the whole cat width and at least half its height. Make the body compact to fit, NOT the face small to fit. Preserve the relative proportions of eyes, nose and muzzle within the face.
Identity invariants: this is a cream/beige Persian based on a real cat, flat short muzzle, rounded fluffy cheeks, gentle dark golden eyes, tiny pink nose, small ears. Preserve its recognizable facial features, warm tan markings and gentle expression; do NOT replace it with a generic cartoon cat or change to enormous anime eyes. Humor comes from head/body proportions, not a different face.
Pose: one low stalking cat facing RIGHT, front paws forward, rump slightly raised, large fluffy tail held UP behind. Keep all paws, ears and tail tips visible, with transparent padding.
Style: coarse 8-bit square pixels, limited flat cream/tan/brown palette, no new fine texture or gradients.
Canvas: ONE full-body sprite on a SQUARE canvas, similar total occupied bounds to the original so it fits the existing view. No sprite sheet. Genuinely transparent alpha outside cat; no soft glow, halo, shadow, floor, scenery, accessories, prey, text or watermark.
```

走りの編集プロンプト：

```text
Use case: precise-object-edit
Asset type: transparent 2-by-2 8-bit Persian cat run-cycle sheet for a tiny keyboard bar
Input images: Image 1 is the run sheet EDIT TARGET. Image 2 is the crouching cat facial identity reference.
Primary request: enlarge each cat's WHOLE HEAD AND FACE to a charming comical big-headed proportion. The head should occupy 55-60% of each cat's overall width and at least half its height, so the face reads clearly at 36pt. Make bodies compact to fit within their cells. Enlarge head/cheeks/eyes/nose/muzzle together, preserving the relative proportions of features inside the face.
Identity: the SAME real-photo-inspired cream Persian, warm tan markings, fluffy rounded cheeks, short flat muzzle, gentle golden-dark eyes, small pink nose and small ears. Preserve the recognizable facial identity and gentle expression; no huge anime eyes, no generic cartoon face, no grin. Humor is in proportions, not a changed face.
Layout invariants: exact regular 2 by 2 grid on a SQUARE canvas. Four equal square cells, one cat centered in each at IDENTICAL scale. Preserve all four DISTINCT running leg poses in reading order. All cats face RIGHT, tails remain proudly UP in ALL frames. Complete ears, paws and tail tips visible. No sprite crosses a cell boundary. No drawn grid lines.
Style: coarse square-pixel 8-bit art, same limited flat warm cream/tan/brown palette, no gradients or fine fur texture.
Transparency: background 100% transparent alpha, no glow, no halo, no shadow, no floor, no scenery, no prey, accessories, text or numbers.
```
