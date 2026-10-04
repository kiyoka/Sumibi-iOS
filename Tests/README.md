# 設定チャットの回帰確認

API通信をモックし、設定案の検証・一括適用・古い設定案の拒否・旧版の利用統計・送信内容・既存の変換処理を確認します。実APIや実APIキーは使いません。

リポジトリのルートで次を実行します。

```sh
swiftc -module-cache-path /private/tmp/sumibi-chat-test-cache \
  SumibiCore/ConversionClient.swift SumibiCore/SharedSettings.swift \
  SumibiCore/SettingsChat.swift SumibiCore/OpenAICompatibleClient.swift \
  Tests/SettingsChatTests.swift -o /private/tmp/sumibi-settings-chat-tests
/private/tmp/sumibi-settings-chat-tests
```
