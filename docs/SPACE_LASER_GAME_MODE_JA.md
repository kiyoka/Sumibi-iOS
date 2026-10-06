# 宇宙船のレーザー砲（Issue #122）

## 表示と操作

設定の「遊び心のあるキーボード」→「テーマ」で「宇宙船のレーザー砲」を選び、「ゲーム演出」をONにする。
既定のテーマ・初期OFFは変更せず、ドラゴンと切り替えて使用できる。
テーマ変更は即保存。OFFのまま選択してもONにしない。未知の保存値は従来通りドラゴンに戻す。
キーボード再表示または入力時に設定を反映し、変更時には前のチャージ・演出をリセットする。

ドラゴンと同じ打鍵エネルギー計算を使用。青→シアンの4ptバーと、砲口の静的な光で蓄積を示す。
通常・範囲変換の通信開始で消費し、左から右へ発射する。追加候補取得では発射しない。
35%未満のチャージでは短い光弾が移動し、それ以上では蓄積量に応じて太さが変わる青・シアン・白のレーザーになる。
長さは帯の幅内、時間は約0.85〜1.4秒。発射時には機体が軽く後退し、砲口の位置は機体の反動に追従する。
機体の背面には小さなオレンジの推進炎を表示。レーザーは最後の35%でフェードアウトする。
入力再開・キャンセル時は0.28秒で消える。テーマ変更・OFF・非表示で描画更新を停止する。
待機中に演出用タイマーは動かさず、発射中だけ30fps。「視差効果を減らす」ONでは発射・反動・拡大を行わない。
ドラゴンと同じ帯の高さ・予約幅・操作性を維持し、候補・Undo・ステータス文字の背面に描画する。
音・追加の振動・API呼び出し・入力内容の保存は追加しない。

## 制作記録

画像生成の組み込みツールを使用（CLI未使用）。既存作品の画像・キャラクターを入力に使わず、新しい汎用SFデザインとして生成。
保存先：[SpaceLaserShip.png](../SumibiKeyboard/SpaceLaserShip.png)。実際の透過アルファを維持。
実行時は64px以下に縮小デコードし、nearestフィルターでドットを保つ。レーザー・推進炎・砲口の光はアプリ内で描画。
既存作品との完全な非類似や法的安全性を保証するものではない。

最終生成プロンプト：

```text
Use case: stylized-concept
Asset type: transparent 8-bit spaceship sprite for an iOS keyboard candidate bar
Primary request: exactly one original small spaceship with a laser cannon in its nose, pointing RIGHT, full side profile, readable at only 36 points tall. A compact sturdy silver-blue hull, dark blue outline, cyan cockpit and cyan cannon aperture; small swept fins and a short rear engine nozzle. Create a fresh generic sci-fi design, not based on any existing game or film.
Style: coarse early 8-bit console pixel art, large square pixels as if on a 32 by 32 grid enlarged with nearest neighbor, limited flat palette of about 6 colors, clear silhouette, no gradients or texture.
Composition: ship centered, fills most of a square canvas; all parts visible; nose and cannon at the right edge. One sprite only, no sprite sheet.
Backdrop: genuinely transparent alpha background.
Constraints: no laser beam, no engine flame, no scenery, no stars, no ground shadow, no logos, no lettering, no watermark, no recognizable existing spacecraft. The animated laser and engine exhaust will be drawn separately by the app.
```

## 確認

- iOS Debugビルド成功。
- 設定の初期OFF・保存・宇宙船の選択・ON/OFFとの独立性・未知値のフォールバックを自動テストで確認。
- 共通エネルギー計算、設定チャット・変換クライアントの既存モック回帰テスト成功。
- iOS 27シミュレーターの単体プレビューでLight/Dark・40pt/32pt・低チャージ光弾・高チャージレーザー・従来のドラゴンを確認。
- 単体プレビューの描画比較テストで、停止・発射中のテーマ切替・切替復帰・キャンセル後に静止姿勢へ戻り、放出演出が残らないことを確認。
- 署名付きビルドをiPhone 17eに上書きインストールし、起動成功。利用者から「いいですね。エネルギーの量によってアニメが変わるのがいいです」との実機確認結果を得た。
