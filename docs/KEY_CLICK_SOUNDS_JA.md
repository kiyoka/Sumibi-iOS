# キークリック音（Issue #127）

文字・数字・記号は軽いノック音、削除は低めのノック音、空白・改行・変換・Shift・記号切替・次のキーボードは中間のノック音を使います。標準キーボードの操作別フィードバックを参考にした、Sumibi独自の音です。Apple標準音の録音や複製ではありません。

## 音源と再生

- 音源は `Tools/GenerateKeyClickSounds.swift` で波形を合成したオリジナル。購入・第三者音源・未公開のシステム音IDは使用しません。リポジトリと同じライセンスで扱います。
- 44.1 kHz / 16 bit / モノラルPCM WAV、各22〜28ミリ秒、3つで約6.6 KBです。
- 立ち上がりと終端に短いフェードを付け、ピークを抑えています。標準音との聴き比べ・音量調整は実機確認が必要です。
- 高音が耳障りという実機での指摘を受け、高い倍音を除去し、ノイズも低域フィルターに通しています。立ち上がりを少し柔らかく、減衰を速くし、振幅も控えめにして短く鈍い音を目指しています。さらに1オクターブ低くする要望に合わせ、文字450 Hz・操作350 Hz・削除260 Hz（前の調整版の半分）へ下げました。この音程の作業版はiPhone 17eへインストール済みです。
- YouTube再生中に聞こえにくいという指摘を受け、3音源の振幅を0.20から0.40へ2倍（約+6 dB）にしました。音程・長さ・減衰・フィルターとOS音量への追従方法は変えず、WAV自体のクリッピングがないことを確認済みです。知覚される音量がちょうど2倍になるという意味ではありません。増幅版をiPhone 17eへインストールし、利用者から「ちょうど良いボリューム」と承認を得ました。
- System Sound Services方式では実機から音量が追従しないと報告されたため、ユーザー承認を受けて`AVAudioPlayer`へ変更しました。表示時に音源を読み込み・準備し、打鍵時は既存プレイヤーを先頭から再生します。打鍵ごとにプレイヤーを生成したり、再生待ちキューを作ったりしません。
- `AVAudioSession.Category.ambient`を使用し、消音・画面ロックを尊重し、他アプリの音声とミックスします。消音を回避する`playback`カテゴリやアラート再生、他アプリを音量ダウンする`duckOthers`は使用しません。根拠：[Appleのambient仕様](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient)。
- プレイヤーの相対音量を1にして、OSのメディア出力音量に従わせます。`outputVolume`を別途掛ける二重減衰やOS音量の上書きは行いません。実機ではコントロールセンターと側面ボタンで音量追従を確認します。根拠：[AppleのoutputVolume仕様](https://developer.apple.com/documentation/avfaudio/avaudiosession/outputvolume)、[プレイヤーの相対音量](https://developer.apple.com/documentation/avfaudio/avaudioplayer/volume)。
- クリック音ON・フルアクセス有効の表示時だけ音声セッションを開始し、非表示・OFF・フルアクセス無効時には再生を止めてセッションを解放します。中断中は鳴らさず、中断終了だけで音を再開しません。メディアサービスのリセット時は次の許可された打鍵で音源とセッションを再準備します。
- フルアクセス無効・音源読込／セッション開始失敗時は`UIDevice.playInputClick()`の標準音へフォールバックします。この標準音はメディア音量への追従を保証しません。失敗時にも入力自体を止めません。
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

2026-10-14に、チャット表示変更（#129）も含む作業版をiPhone 17eへ上書きインストールし、利用者から「うまく動いています」と報告を得ましたが、この時点では音の確認は含まれていませんでした。その後の試聴で高音が耳障りと指摘され音源を調整し、さらに音量が追従しないと報告されました。AVAudioPlayerへ変更した版では音が小さいと指摘され、振幅を2倍にした版を再インストールして、利用者から「ちょうど良いボリューム」と承認を得ました。音量操作への追従・消音・通話などの中断と復帰は、個別の確認完了までは断定していません。以下は詳細確認項目です。

- 文字・数字・記号、削除、空白・改行・変換・Shift・記号切替・地球儀の音を聴き比べる。
- 各キーの長押しで、音と入力／削除が同期し二重に鳴らないことを確認する。
- Sumibi側のON/OFFと再起動後の保存、フルアクセス無効時の標準音を確認する。
- コントロールセンターと側面ボタンのメディア音量で音が変化し、音量0では鳴らないことを確認する。
- 消音モード・音楽再生中・他アプリでの音声入力／通話後の復帰、iOSのキーボードクリックON/OFFの組み合わせを確認する。
- キーボードを閉じる・開く、クリック音OFF／ON、フルアクセス変更、中断後に古いクリックが再生されないことを確認する。
- 変換候補・Undo、触覚、キー拡大、ゲーム演出が従来どおり動くことを確認する。
