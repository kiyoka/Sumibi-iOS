# App Review Notesと審査手順

Issue #52で整備した、初回リリースのApp Review向け手順です。審査用APIキーなどの秘密情報は、このファイルやGitへ記録しません。

## 審査用APIの運用

- 送信先：`https://api.openai.com`
- モデル：アプリの既定値 `gpt-5.6-terra`
- 認証：審査専用のOpenAI API Projectで、審査期間だけ有効なAPIキーを発行する
- 制限：Projectへ低い月間予算とレート制限を設定し、他の用途と共有しない
- 受け渡し：APIキーはApp Store Connectの「App Review Information」にだけ入力する。Git、スクリーンショット、一般公開する説明文には含めない
- 終了：審査完了後にキーを失効させる。再審査時は新しいキーへ交換する

審査開始から完了まで、API、モデル、審査用Projectを利用可能な状態に保ちます。障害を確認した場合はApp Store ConnectのResolution Centerで状況を連絡し、新しい審査用キーまたは復旧見込みを安全に案内します。通常の英字入力はAPI障害時も確認できますが、AI変換の代替とは説明しません。

## App Store Connectへ貼り付けるReview Notes

次の文面にある `<REVIEW_API_KEY>` だけを、送信直前に審査専用キーへ置き換えます。

```text
Sumibi is an iPhone custom keyboard that converts text entered with its QWERTY keyboard into Japanese using a third-party AI API.

Review API settings
- Endpoint: https://api.openai.com
- Model: gpt-5.6-terra
- API key: <REVIEW_API_KEY>
This key is provided only for App Review and will remain active during review. No account login is required.

Setup and test
1. Launch Sumibi. In “API設定”, enter the endpoint, model, and API key above, then tap “設定を保存”.
2. In “プライバシー”, confirm the displayed destination and enable “この第三者AIへのデータ送信に同意する”.
3. In “変換テスト”, tap “設定したAPIで変換をテスト” and confirm that a Japanese result appears.
4. Tap “設定を開く”. In iOS Settings, add the Sumibi keyboard and enable “フルアクセスを許可”. Full Access is required only for network conversion and access to the settings/API key shared with the containing app.
5. Open Notes or another text field, switch to Sumibi, type “sumibi yakiniku ga sukidesu .”, and tap “変換”. Confirm that the text is replaced by Japanese and candidates are shown.
6. Tap “↶ Undo” to restore the original text.
7. If a globe button is shown, tap it to move to the next keyboard. iOS may instead provide the keyboard-switching control outside the extension.

User dictionary
1. Return to Sumibi and open “ユーザー辞書”.
2. Enter “sumibi = Sumibi” and save it.
3. Return to Notes, type “sumibi”, and tap “変換”. Confirm that “Sumibi” is offered while preserving its capitalization.

Privacy and operation without Full Access
AI data is sent only after the reviewer explicitly enables the consent switch and taps the conversion button. The conversion text, the minimum surrounding context needed for conversion, and the complete registered user dictionary are sent to the displayed third-party API endpoint. The developer’s server is not used. The API key is stored in the device Keychain. Consent can be withdrawn in the app.

With Full Access disabled, ordinary QWERTY character input, delete, space, return, symbols, and switching to the next keyboard remain available. AI conversion does not send data and displays a message that Full Access is required.

Privacy policy: https://kiyoka.github.io/Sumibi-iOS/privacy.html
Support: https://kiyoka.github.io/Sumibi-iOS/support.html

If the review API is temporarily unavailable, please retry the in-app conversion test. If it remains unavailable, contact us through App Review; we will restore the service or provide a replacement review key. Ordinary typing can still be tested without the API, but it is not a substitute for reviewing AI conversion.
```

## 申請前チェックリスト

- Releaseビルドを実機へ入れ、クラッシュしない
- フルアクセスOFFで英字、削除、空白、改行、記号が入力できる
- フルアクセスOFFで変換を押しても通信せず、必要性を示すメッセージが出る
- 複数のキーボードを有効にし、必要な場合に専用の地球儀ボタンが現れて次のキーボードへ進める
- 審査用APIキーでアプリ内の変換テストが成功する
- 同意OFFではアプリとキーボードのどちらからもAIへ送信しない
- 同意ONかつフルアクセスONで、キーボードから変換、候補選択、Undoが動く
- `sumibi = Sumibi`を登録し、辞書の指定表記が候補へ反映される
- APIキーを含まない状態でGit差分と提出用スクリーンショットを確認する
- App Store Connectの連絡先、プライバシーポリシーURL、サポートURLが有効である
- 提出直前にReview Notesのプレースホルダーを審査専用APIキーへ置き換える
- 審査中はAPIを監視し、完了後に審査専用APIキーを失効させる

## 根拠となるAppleの要件

- [App Review Guidelines 4.4.1](https://developer.apple.com/app-store/review/guidelines/#extensions)：文字入力、次のキーボードへ進む方法、フルアクセスなしでの動作が必要
- [App Review Guidelines 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#privacy)：第三者AIを含む共有先を明示し、送信前に明示的な許可を得る必要がある
- [Before You Submit](https://developer.apple.com/app-store/review/guidelines/#before-you-submit)：審査に必要なアクセス情報を提供し、バックエンドを稼働させ、分かりにくい機能をReview Notesで説明する
