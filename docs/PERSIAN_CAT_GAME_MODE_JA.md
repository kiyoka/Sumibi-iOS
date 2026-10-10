# ペルシャ猫のゲーム演出（Issue #122）

## 操作と見せ方

設定の「遊び心のあるキーボード」でゲーム演出をONにし、テーマ「獲物を狙うペルシャ猫」を選ぶ。
初期OFF・既定テーマのドラゴンは変更しない。テーマ選択だけではONにならない。

利用者の猫の写真を参考に、クリーム色の毛・丸く平たい顔・ピンクの鼻・ふさふさのしっぽを持つ8ビット風キャラクターを制作。
追加の写真に合わせて濃い眉のような線を減らし、優しい目元に調整する。
元の写真・室内・写真の個人情報はリポジトリにもアプリにも含めず、生成した透過画像だけを使う。

- 入力中は左側で低く構え、右側の小さなドット絵のピンクのボールを狙う。本物の動物ではないおもちゃにする。
- エネルギーが残っている間は、後ろ脚・腰・しっぽを描き分けた9コマでお尻をふりふりする。同じ画像のメッシュ変形は使わない。
- 中間のポーズを往復する14ステップのループを12〜24コマ/秒で再生する。打鍵の勢いで速くなり、ゲージが減る間も再生位置を保持する。
- 通常変換・範囲変換の通信開始で右へ走る。しっぽを上げた4コマの走りをループする。
- 右端に到達すると同じピンクのボールをくわえる正面ポーズに変わり、こちらを見たまま2秒間静止する。
- 決めポーズだけは通常の縦横2倍（縦向き72pt・横向き56pt）で候補帯右端に表示し、下方向へ広げてキーの上に重ねる。
- 蓄積量が多いほど走る速度・コマの切替速度・足元の小さなほこりを強める。
- 短い走り出し（0.08秒）の後に加速し、約0.68〜1.03秒で右端に到達する。2秒間こちらを見て、最後0.18秒でフェードする。
- 終了後は左側の構えに戻る。入力再開・キャンセルでは0.28秒でフェードし、前の演出が残らないようにする。
- 結果を待たせず、候補・Undo・追加候補の操作は従来通り。追加候補では再度走らない。
- OFF・テーマ変更・キーボード非表示では動き・エネルギーをリセットする。
- 「視差効果を減らす」ONでは猫は静止し、ゲージの値だけ更新する。

候補帯は縦40pt・横32ptのまま。猫は候補・ステータス文字の背面で描画し、操作を受け取らない。
Issue #125：通常入力・チャージ・走行・決めポーズ・フェードの全状態で、他テーマと同じ352pt／216ptとする（記号展開分は従来通り加算）。猫のための追加上部領域は確保せず、決めポーズのたびに入力欄の表示領域も変わらない。キーの大きさ・候補帯の高さは変更しない。
候補帯のクリップは常に維持する。決めポーズの間だけ猫をキーボード直下の透明・操作を受け取らないオーバーレイへ移す。キーボード全体のクリップも維持し、入力欄にはみ出させない。下に重なったキーはタップ可能なままにする。候補のガラス描画と猫の拡大領域を分離する。
候補一覧とメッセージの右端余白は、決めポーズ中だけ縦向き88pt・横向き72ptにして2倍の猫と重ならないようにする。自然終了・キャンセル・停止後は猫を候補帯へ戻し、余白も従来の54ptへ戻す。候補は従来通り横へスクロールできる。他のテーマとOFF時は8ptのままで、キーボードの高さも元へ戻す。
チャージ速度・入力休止時の減衰はドラゴン・宇宙船と同じ。入力内容は演出に渡さず、API通信や料金を増やさない。
ゲージが空、演出終了、非表示のときは描画タイマーを停止する。
捕獲後の静止中も描画用タイマーを止め、単発タイマーでフェードの開始だけを予約する。入力再開・OFF・非表示・テーマ切替では予約も破棄する。

## アセット

画像生成の組み込みツールを使用（CLI未使用）。透過を維持して保存する。

- [PersianCatAim.png](../SumibiKeyboard/PersianCatAim.png)：構え9コマ、3×3の透過シート。実行時に192pxへ縮小デコードし、64pxのセルに分割。
- [PersianCatHunt.png](../SumibiKeyboard/PersianCatHunt.png)：以前の構え。新しいシートを読み込めなかった場合の静止フォールバック。64px以下へ縮小デコード。
- [PersianCatRun.png](../SumibiKeyboard/PersianCatRun.png)：2×2の4コマ。128px以下へ縮小デコードし、実行時に4分割。
- [PersianCatCatch.png](../SumibiKeyboard/PersianCatCatch.png)：ピンクのボールをくわえてこちらを見る静止ポーズ。64px以下へ縮小デコード。

nearest描画とアンチエイリアス無効でドット感を保つ。
構えは各セルの透明な余白を除き、全コマ共通の倍率・右下の基準位置で描画する。コマごとに画像を伸縮・変形しない。
再生順は `0,1,2,3,2,1,4,5,6,7,6,5,8,4`。エネルギー0・停止時は先頭へ戻す。
走りは各コマの切替と帯内の移動で描く。元の高解像度画像をフルサイズで展開しない。

## 確認

2026-10-09、Issue #125：利用者の指定により、決めポーズを下方向へキー上に重ね、通常時・演出中とも追加余白を設けない方式へ変更。候補帯の原点移動後に、別オーバーレイ上の猫の座標も更新し、帯のサイズが変わらなくても位置を合わせる。高さ不変・キーの操作・終了時の復帰を確認する。その後、利用者より実機で正常に動作したとの確認を得た。
猫の動作・画像切り出し、設定チャット・エネルギーの回帰テストとシミュレーター／署名付き実機向けDebugビルドが成功。iOS 27の実際のKeyboardViewControllerを使う一時検証アプリで、2026-10-09 12:30 JSTに検証が成功した。縦向き352pt（記号展開468pt）、横向き216pt（記号展開302pt）が通常入力・走行・決めポーズ中も変わらないこと、2倍ポーズがキーボード内に収まること、猫に重なった実際のキー／記号ボタンへタップが届くことを確認。縦向きのLight/Dark、自然終了・走行／静止中のキャンセル・停止・テーマ変更・OFF・非表示と、縦横回転後の配置も確認。検証中にAPI通信は行わない。2026-10-09にiPhone 17eへ上書きインストールし、アプリ起動が成功。その後、利用者による実機動作確認も完了した。

2026-10-08の描画修正：実機で拡大後に四角形と「原文」の欠けが報告された。候補帯のクリップ解除を廃止し、猫を専用の透明オーバーレイへ分離。候補の右側余白は常時88ptではなく決めポーズ中だけ広げ、終了後は54ptへ復帰する。
iOS 27のシミュレーターで「Undo」「収める」「原文」のネイティブガラスボタンを配置し、拡大中・自然終了後のLight/Darkと記号展開を確認。終了後に候補幅が復帰し、原文が表示されること、猫が候補帯へ戻ること、キャンセルとテーマ変更・OFFも検証した。2026-10-08に修正版の実機向けビルドが成功し、iPhone 17eへの上書きインストールとアプリ起動を確認。その後、利用者から実機で修正できたとの確認を得た（四角形と「原文」の欠けが解消）。

2026-10-08の決めポーズ拡大：縦横2倍、縦／横・小型／大型幅でキーボード内に収まる位置、候補領域との非重複を計算テストで検証。
Debugビルド成功。iOS 27のシミュレーターで製品のKeyboardViewControllerを使い、縦向きのLight/Dark・記号一覧展開時を確認した。猫がキーボード内に収まり、数字キーと重ならないこと、キャンセル後のサイズ復帰、他テーマ・OFF時の高さ／クリップの復帰も検証した。
2026-10-08：9コマの構え・ピンクのボール・2倍の決めポーズを含む版を、接続中のiPhone 17eへ上書きインストールし、Sumibiアプリの起動が成功した。キーボードの実際の見え方・操作は利用者の確認待ち。

2026-10-08の9コマ版：iOSシミュレーター向けDebugビルドが成功。猫の構え・走り、画像切り出し、エネルギー減衰、弓・魔法、設定チャットの回帰テストが成功。
実際の縮小デコードを使い、9枚が別々の画像であることと、全コマで顔・しっぽを含む可視ピクセルが切り落とされないことを検証した。
iOS 27の演出単体プレビューでLight/Dark・40pt/32ptの表示を確認。描画比較でコマの変化、ゲージ0で先頭に復帰、捕獲後の静止、キャンセル・停止後の復帰を確認した。
9コマ版の実機インストール状況は上記の最新記録を参照。以下は実機確認項目と、以前の版の確認記録。

チャージ・設定チャットの既存回帰テストと猫の移動計算テストが成功。
走りの強弱、単調な移動、4コマの範囲、フェード、終了、不正値を検証。

- [ ] Light/Dark・40pt/32ptの候補帯で、顔・しっぽ・ステータス文字が見える
- [ ] 入力中にお尻が揺れ、入力休止でゲージと動きが収まる
- [ ] 変換で右へ走り、低／高チャージの速度が変わる
- [ ] 入力中の目標とくわえたものが、動物ではなくピンクのボールだと分かる
- [ ] 右端でおもちゃをくわえた正面ポーズになり、2秒間静止した後フェードして戻る
- [ ] 候補・Undo・範囲変換・追加候補を妨げない
- [ ] テーマ切替・OFF・キャンセルで描画が残らない
- [ ] 「視差効果を減らす」ONで静止し、OFFに戻すと演出が再開する

顔拡大版と捕獲後の正面ポーズ追加版はiPhone 17eに上書きインストールし、起動を確認した。利用者から正面ポーズも良いとの確認を得た。布製おもちゃ・2秒版もiPhone 17eに上書きインストール済み。ただし端末がロックされていたため、この版の自動起動はできなかった。自動・シミュレーター確認と利用者の実機確認は区別する。
iOS Debugビルド成功。iOS 27の演出単体プレビューで、Light/Dark・40pt/32ptの構えと4コマの走り、強弱による移動の差、終了後の復帰を確認した。
描画の比較テストで停止・3テーマの切替・切替後の復帰・キャンセルのフェード後に描画が残らないことを確認した。
両PNGは1254×1254で透明な四隅を保持。背景の透明部分と、柔らかい光のにじみが残っていないことも検証した。

## 制作プロンプト

### ピンクのボールへの変更（2026-10-08）

利用者の希望により、布製の筒型おもちゃをピンクのボールへ変更。猫の顔・体・正面ポーズは維持した。
組み込み画像生成を使用（CLI未使用）。保存先は `SumibiKeyboard/PersianCatCatch.png`。
右端の目標も同じ色の丸いドット絵へ変更。元の写真は使わず、生成済みの猫画像だけを編集した。
ピンクのボール版のDebugビルドと猫の構え・走り・切り出しテストが成功。
iOS 27の演出単体プレビューでLight/Dark・40pt/32ptの目標とくわえた状態を確認。描画比較で、静止・ゲージ0への復帰・キャンセル・停止を確認した。実機インストール状況は上記の最新記録を参照。

```text
Use case: precise-object-edit
Asset type: transparent 8-bit Persian cat sprite for an iOS keyboard bar.
Input image 1: edit target, the existing cat holding a blue/pink cylindrical cloth toy.
Change ONLY the toy in its mouth: replace the entire blue cylinder, pink bands, stitches and yellow string with ONE ROUND PINK TOY BALL, gently held at the same mouth position. The ball is clearly spherical/circular, bright medium pink with darker pink pixel shading and a small pale pink square highlight, simple coarse 8-bit pixel art. About the same height as the original toy but ROUND (not elongated). No strings, ribbons, animal features or other objects. Keep both eyes and pink nose completely visible.
Preserve EXACTLY the cat's face, golden eyes, gentle expression, large head proportions, cream/tan fur, white whiskers, paws, raised fluffy tail, entire body pose, size, position, framing and pixel style. Do not redesign or rescale the cat. Same square canvas, one full-body cat looking at the viewer.
Background genuinely transparent alpha, preserve existing transparency. Crisp square-pixel edges, no colored glow or matte fringe, no soft shadows, scenery, floor, text or watermark.
```

### お尻フリフリを専用コマへ変更（2026-10-08）

既存の生成済み構え画像を参照して9ポーズを制作し、余白を調整した。組み込み画像生成を使用（CLI未使用）。元の写真は参照・追加していない。
保存先は `SumibiKeyboard/PersianCatAim.png`。走り4コマ・おもちゃをくわえた正面ポーズ・2秒の静止は変更しない。
初期案の16コマ版は向きと余白が揃わなかったため不採用。採用した9コマ版のプロンプト：

```text
Use case: stylized-concept
Asset type: transparent 3-by-3 sprite sheet of NINE animation frames.
Image 1: exact character identity and style reference.
Draw nine distinct full-body poses of this SAME big-headed cream Persian cat playfully wiggling its raised hindquarters before pouncing to the RIGHT. ALL NINE cats face RIGHT, never mirror or turn left. Preserve the SAME recognizable big rounded flat face, gentle golden eyes, pink nose, cream/tan fur, large fluffy cheeks and raised fluffy tail. Keep head and front paws fixed; only redraw the rear half changing anatomy, hind-leg bends, pelvis twist and tail curve. This is actual sequential hand-drawn animation, not mesh distortion.
Order reading left to right then top to bottom: 0 center; 1 slight rump-toward-viewer; 2 medium rump-toward-viewer; 3 maximum rump-toward-viewer; 4 relaxed center; 5 slight rump-away-from-viewer; 6 medium rump-away-from-viewer; 7 maximum rump-away-from-viewer; 8 relaxed center.
EXACT regular 3 columns by 3 rows on a square canvas, nine equal SQUARE cells. One cat fully inside each cell. Identical scale, head placement, front paw baseline and viewing angle. The cat occupies about 65% of the cell width and height, with LARGE transparent margins all around every cell. No outline touches cell edges. Keep all ears, paws and tail tips visible. No drawn borders, grid lines, frame numbers or labels.
Same coarse square-pixel 8-bit art. Hard pixel silhouettes with flat cream, tan, warm-brown outlines and gentle eyes. No gradients, fine fur painting, blur or soft halo.
Genuinely transparent background alpha outside the cats, with EMPTY TRANSPARENT gutters. No colored matte or glow, no red or yellow fringe, no shadow, scenery, floor, toys, prey, text, watermark or other objects.
```

最終の余白調整プロンプト：

```text
Use case: precise-object-edit
Image 1 is a nine-frame 3x3 Persian-cat anticipation animation sheet. Perform a MAJOR LAYOUT CHANGE, not an identity change.
The cats are currently much too large in their cells and bleed across borders. SHRINK EVERY ENTIRE CAT TO 70% OF ITS CURRENT WIDTH AND HEIGHT. The cat art itself and ALL NINE DIFFERENT POSES must remain exactly the same. Do not crop off paws, face or tail.
Place each shrunken cat back into its original 3x3 square cell. Align all front paws to the same baseline at 82% cell height; align pink noses to the same x coordinate, about 67% cell width. All cats keep the same size, SAME big heads, gentle faces, right-facing direction and original frame order.
After shrink, each cell must have a clearly wide EMPTY TRANSPARENT gutter of at least 12% of cell width on EVERY side. In particular there must be a wide transparent vertical lane between columns 1 and 2; the middle-row left cat's nose must not cross into the middle cat cell.
REMOVE all isolated red/yellow specks and colored outer fringes, make them alpha 0. Transparent alpha outside cats, crisp cream/tan/brown square-pixel silhouettes. Same square canvas, same 3 columns and 3 rows. No new poses, no mirrored cats, no extra objects, no grid lines, text or numbers.
The visible output must show MUCH SMALLER cats separated by MUCH WIDER blank transparent gutters than Image 1.
```

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
当時はお尻のメッシュ変形を左側に限定した。2026-10-08に上記の専用9コマへ置き換え、メッシュ変形は廃止した。
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
