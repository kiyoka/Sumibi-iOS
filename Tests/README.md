# 設定チャットの回帰確認

API通信をモックし、設定案の検証・一括適用・古い設定案の拒否・旧版の利用統計・送信内容・既存の変換処理を確認します。実APIや実APIキーは使いません。

Issue #120では、統計の金額・日時・不明値、任意期間の質問と会話履歴の送信、操作ガイド、秘密情報の除外も確認します。モック応答はLLMの実際の計算能力を検証するものではありません。実APIの回答は[相談チャット仕様](../docs/CHAT_ASSISTANT_SPEC_JA.md)の確認例を使って別途検証します。

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
上記の設定チャットテストには、ゲーム演出の初期OFF・保存・テーマ選択とON/OFFの独立性も含まれます。

```sh
swiftc -module-cache-path /private/tmp/sumibi-game-test-cache \
  SumibiCore/KeyboardGameEnergy.swift Tests/KeyboardGameEnergyTests.swift \
  -o /private/tmp/sumibi-game-energy-tests
/private/tmp/sumibi-game-energy-tests
```

## 猫のダッシュ

蓄積量に応じた速度、走り出し、移動の単調性、4コマの切替、おもちゃをくわえた後の2秒間の静止・正面ポーズ、フェード、終了、不正値を確認します。

```sh
swiftc -module-cache-path /private/tmp/sumibi-cat-test-cache \
  SumibiKeyboard/CatHuntEffectView.swift Tests/CatRunMotionTests.swift \
  -o /private/tmp/sumibi-cat-motion-tests
/private/tmp/sumibi-cat-motion-tests
```

## 弓使い・魔法使い

予備動作・チャージ量に応じた速度・移動の単調性・終了・フェード・不正値、大きな弓の引き動作と汗の開始・周期・停止を確認します。設定チャットのテストには5テーマの保存と初期OFFも含まれます。

```sh
swiftc -module-cache-path /private/tmp/sumibi-fantasy-test-cache \
  SumibiKeyboard/FantasyGameEffectView.swift Tests/FantasyShotMotionTests.swift \
  -o /private/tmp/sumibi-fantasy-motion-tests
/private/tmp/sumibi-fantasy-motion-tests
```
