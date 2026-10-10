# 設定チャットの回帰確認

API通信をモックし、設定案の検証・一括適用・古い設定案の拒否・旧版の利用統計・送信内容・既存の変換処理を確認します。実APIや実APIキーは使いません。

Issue #120では、統計の金額・日時・不明値、任意期間の質問と会話履歴の送信、操作ガイド、秘密情報の除外も確認します。モック応答はLLMの実際の計算能力を検証するものではありません。実APIの回答は[相談チャット仕様](../docs/CHAT_ASSISTANT_SPEC_JA.md)の確認例を使って別途検証します。
遊び心のあるキーボードの相談では、全4テーマの説明と並び、ON/OFF・テーマ選択の設定画面への誘導、チャージ・料金・動きを抑える設定の案内、継続会話とゲーム設定の不変性もモックで確認します。ゲーム設定を変更する不正な応答は拒否します。

リポジトリのルートで次を実行します。

```sh
swiftc -module-cache-path /private/tmp/sumibi-chat-test-cache \
  SumibiCore/ConversionClient.swift SumibiCore/SharedSettings.swift \
  SumibiCore/SettingsChat.swift SumibiCore/OpenAICompatibleClient.swift \
  Tests/SettingsChatTests.swift -o /private/tmp/sumibi-settings-chat-tests
/private/tmp/sumibi-settings-chat-tests
```

## ゲーム演出のチャージ

Issue #122のチャージ速度・上限・休止時の連続減衰・表示周期の違い・消費時刻・リセットを通信なしで確認します。
上記の設定チャットテストには、ゲーム演出の初期OFF・保存・テーマ選択とON/OFFの独立性、キャラクタータップ用の4テーマ循環と2周の保存確認、削除済みの弓使い設定からの安全なフォールバックとON/OFF保持も含まれます。

```sh
swiftc -module-cache-path /private/tmp/sumibi-game-test-cache \
  SumibiCore/KeyboardGameEnergy.swift Tests/KeyboardGameEnergyTests.swift \
  -o /private/tmp/sumibi-game-energy-tests
/private/tmp/sumibi-game-energy-tests
```

## 猫の構え・ダッシュ

描き分けた構え9コマの往復、打鍵の勢いによる速度、速度変更時の位相維持、リセット、不正値を確認します。走り出し、移動の単調性、走り4コマ、おもちゃをくわえた後の2秒間の静止・正面ポーズ、フェードも確認します。
決めポーズの縦横2倍と、縦／横・複数の画面幅でキーボード内に収まり候補領域と重ならない配置も確認します。Issue #125では上部余白を追加せず候補帯右端から下方向にキー上へ重なり、通常の高さのキーボード内に収まることも確認します。

```sh
swiftc -module-cache-path /private/tmp/sumibi-cat-test-cache \
  SumibiKeyboard/CatHuntEffectView.swift Tests/CatRunMotionTests.swift \
  -o /private/tmp/sumibi-cat-motion-tests
/private/tmp/sumibi-cat-motion-tests
```

画像の3×3配置・9コマの差・透明な境界・実行時と同じ192pxデコードを確認します。製品コードと同じ切り出し処理で、顔・しっぽの可視ピクセルが欠けないことも確認します（macOSのImageIOを使用）。

```sh
swiftc -module-cache-path /private/tmp/sumibi-cat-test-cache \
  SumibiKeyboard/CatHuntEffectView.swift Tests/CatAimSpriteTests.swift \
  -o /private/tmp/sumibi-cat-sprite-tests
/private/tmp/sumibi-cat-sprite-tests
```

## 魔法使い

魔法使いの予備動作・移動時間が変更されていないこと、チャージ量に応じた速度・移動の単調性・終了・フェード・不正値を確認します。設定チャットのテストには4テーマの保存と初期OFFも含まれます。

```sh
swiftc -module-cache-path /private/tmp/sumibi-fantasy-test-cache \
  SumibiKeyboard/FantasyGameEffectView.swift Tests/FantasyShotMotionTests.swift \
  -o /private/tmp/sumibi-fantasy-motion-tests
/private/tmp/sumibi-fantasy-motion-tests
```
