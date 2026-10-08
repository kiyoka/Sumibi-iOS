# 魔法使いの白い魔法陣（Issue #122）

2026-10-08：Issue #122のゴールをドラゴン・宇宙船・猫・魔法使いの4テーマへ変更。弓使いは選択肢・描画・同梱画像から削除し、格闘ゲーム風も対象外とする。過去の制作・確認記録はGit履歴に残る。

初期OFF・既定ドラゴンは維持。テーマ選択だけではONにならない。以前の弓使いの保存設定はドラゴンにフォールバックし、ON/OFFは保持する。

## 魔法使いの白い魔法陣

利用者の希望により、異世界ファンタジーのような白い魔法陣を採用。特定作品の衣装・紋章は使わず、オリジナルのキャラクターと幾何学模様で表現する。

- 入力中、差し出した手の前に白い二重の魔法陣が現れる。円・三角形・短い幾何学の線がゆっくり回転する。
- 蓄積量に応じて魔法陣と中心の魔力が大きくなる。入力を休むとゲージ・魔法陣も小さくなり、空になると回転を止める。
- 白い線に紫の縁取りを付け、Light/Darkのどちらでも見えるようにする。
- 変換開始時、魔法陣から右へ白い光を放つ。魔力が多いほど太い光と多くの小さな光粒。0.12秒の予備動作、0.65〜0.85秒の移動、最後0.28秒のフェード。
- 左のアイコン予約幅を44ptから72ptへ広げ、魔法陣の上にステータス文字や候補が重ならないようにする。候補の横スクロールは維持。


## 動作と停止

既存の打鍵エネルギーを使い、変換や範囲変換で放つ。追加候補では再発射しない。
変換結果を演出待ちにせず、文字列やAPI通信・料金を演出のために追加しない。
入力再開・キャンセルでは0.28秒で自然に消す。OFF・テーマ変更・非表示では完全にリセット。
「視差効果を減らす」ONでは回転・反動・飛翔を出さず、静的なチャージ表示のみ。
魔法陣がある間と短い発射中だけ30fps更新。空の状態・非表示・停止後に描画タイマーを残さない。
iOS 17以降。デバイスの画面サイズに応じて右端までの距離を計算する。

## アセット・制作プロンプト

組み込み画像生成を使用（CLI未使用）。正方形の透過PNG、64px以下に縮小デコード、nearest描画。写真や既存作品の画像は使わない。
魔法陣・光・反動はコードで描画する。

- [RPGWizard.png](../SumibiKeyboard/RPGWizard.png)

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

4テーマへの整理では、魔法使いの予備動作0.12秒、移動0.65〜0.85秒、最後0.28秒のフェードは変更しない。自動テストで旧弓使い設定のフォールバックと4テーマの保存・循環、魔法の速度差・移動・フェード・不正値を確認する。

以下は4テーマ版の実機確認項目。以前の5テーマ版の実機確認と区別する。

- [ ] Light/Dark、縦40pt・横32ptで顔・白い魔法陣が見える
- [ ] 魔法陣が大きくなり回転し、休止で収まる
- [ ] 低／高チャージで魔法の強さが変わる
- [ ] 候補・Undo・範囲変換・追加候補の操作を妨げない
- [ ] キャンセル・OFF・4テーマ切替・非表示で描画が残らない
- [ ] 「視差効果を減らす」ON/OFFの切替で装飾の動きを抑制できる
