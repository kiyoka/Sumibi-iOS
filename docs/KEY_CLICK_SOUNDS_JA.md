# キークリック音（Issue #127）

文字・数字・記号は軽い高めのクリック、削除は低めのクリック、空白・改行・変換・Shift・記号切替・次のキーボードは中間のクリックを使います。標準キーボードの操作別フィードバックを参考にした、Sumibi独自の音です。Apple標準音の録音や複製ではありません。

## 音源と再生

- 音源は `Tools/GenerateKeyClickSounds.swift` で波形を合成したオリジナル。購入・第三者音源・未公開のシステム音IDは使用しません。リポジトリと同じライセンスで扱います。
- 44.1 kHz / 16 bit / モノラルPCM WAV、各22〜28ミリ秒、3つで約6.6 KBです。
- 立ち上がりと終端に短いフェードを付け、ピークを抑えています。標準音との聴き比べ・音量調整は実機確認が必要です。
- キーボード表示時に読み込み、公開API `AudioServicesCreateSystemSoundID` で登録。タップ時は `AudioServicesPlaySystemSoundWithCompletion` で非同期再生します。
- UI音の属性を有効にし、消音を回避するアラート再生やオーディオセッションの変更は行いません。消音・音量・他アプリの音声との共存は実機で確認します。
- フルアクセス無効時や登録に失敗した場合は `UIDevice.playInputClick()` の標準音へフォールバックします。失敗時に入力を止めません。
- Sumibiの「キークリック音」の初期ON・保存・ON/OFFを維持。独自音はiOSの「キーボードのクリック」スイッチとの完全連動を保証しないため、Sumibi側でON/OFFを設定します。標準音へのフォールバック時はiOS側のクリック設定にも従います。
- 初回タッチ・削除開始・リピートの既存の音の発生箇所を置き換え、入力・長押しタイミング、触覚・アニメーションには変更を加えません。

## 音源の再生成と自動確認

リポジトリのルートで実行します。生成先を `/private/tmp` にすれば、保存済み音源を書き換えず再現性を検証できます。

```sh
swiftc -module-cache-path /private/tmp/sumibi-click-cache \
  SumibiKeyboard/KeyClickSound.swift Tools/GenerateKeyClickSounds.swift \
  -o /private/tmp/sumibi-generate-key-clicks
/private/tmp/sumibi-generate-key-clicks /private/tmp/sumibi-regenerated-clicks
swiftc -module-cache-path /private/tmp/sumibi-click-cache \
  SumibiKeyboard/KeyClickSound.swift Tests/KeyClickSoundTests.swift \
  -o /private/tmp/sumibi-key-click-tests
/private/tmp/sumibi-key-click-tests /private/tmp/sumibi-regenerated-clicks
```

## 実機確認状況と詳細確認項目

2026-10-14に、チャット表示変更（#129）も含む作業版をiPhone 17eへ上書きインストールし、利用者から「うまく動いています」と正常動作の報告を得ました。以下は詳細確認項目です。消音・音量・音楽再生中などの組み合わせは、個別に確認済みとはしていません。

- 文字・数字・記号、削除、空白・改行・変換・Shift・記号切替・地球儀の音を聴き比べる。
- 各キーの長押しで、音と入力／削除が同期し二重に鳴らないことを確認する。
- Sumibi側のON/OFFと再起動後の保存、フルアクセス無効時の標準音を確認する。
- 消音スイッチ・音量、音楽再生中、iOSのキーボードクリックON/OFFの組み合わせを確認する。
- 変換候補・Undo、触覚、キー拡大、ゲーム演出が従来どおり動くことを確認する。
