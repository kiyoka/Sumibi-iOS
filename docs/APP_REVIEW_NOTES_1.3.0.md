# App Review Notes — Sumibi 1.3.0（確認用案）

Issue #131。以下はApp Store Connectへ登録する前の確認用案。
実機確認・モデルの接続テストが完了するまで登録しない。
旧版の審査メモを上書きせず、現行版の操作をまとめる。

## 登録前に確定する情報

- 審査モデル：候補は `gpt-6-sol`。審査用キーで変換・チャットの両方を確認して確定。
- 実機モデル・OS・配信予定ビルド：TestFlight確認後に下記のプレースホルダーを置き換える。
- APIキー：この文書には記載しない。App Store Connectのメモ欄の末尾で利用者が直接入力する。
- 審査用キーの継続運用は利用者の方針を確認する。審査中は必ず利用可能にしておく。
- 既存の審査用動画・連絡先が有効か確認し、新しい動画の添付が必要なら別途準備する。

## Notes案

```text
Sumibi is a free iPhone custom keyboard for Japanese writing with one English QWERTY layout. Type romaji, then tap “変換” to convert it into Japanese. Ordinary English typing uses the same layout. There is no Sumibi account, login, subscription, in-app purchase, advertising, or user-to-user content sharing.

The app UI is currently in Japanese. Core AI features use the user's configured OpenAI-compatible Chat Completions API directly, without a developer-operated server.

Setup
1. Launch Sumibi. Under “API設定”, set the endpoint to https://api.openai.com and select GPT-6 Sol. Enter the review API key provided at the end of these notes and tap “設定を保存”.
2. Under “プライバシー”, review the destination and enable “この第三者AIへのデータ送信に同意する”.
3. Under “変換テスト”, tap “設定したAPIで変換をテスト”.
4. Tap “設定を開く”, add the Sumibi keyboard in iOS Settings, and enable “フルアクセスを許可”.
5. Open a new note in Notes, switch to Sumibi, type “ashitaha tosyokan ni ikimasu .”, then tap “変換”. Tap a candidate to choose another expression, or “Undo” to restore the original.
6. To convert a range, select romaji text in the host app and tap “範囲を変換”. Surrounding text is left unchanged. “さらに変換候補を取得” requests additional candidates.

New in 1.3.0
- Additional candidates use a local SudachiDict index for hiragana readings and a Mozc symbol index for exact input matches. Try “hoshi” for ☆/★, “maru1” for ①, or “ten”, “nakaguro”, “.” for ・. Labels “LLM”/“辞書” are not inserted into text. “ライセンス” provides offline licenses and third-party notices.
- Model selection offers GPT-6 Sol, GPT-6 Luna, and custom input. Existing custom model IDs are preserved.
- Open “チャットで質問” to ask the configured AI about Sumibi or usage. This is not human support. For example, ask “Sumibiの使い方を教えて” or “今後15日でどれくらい費用がかかりそうですか？”. Cost forecasts are estimates based on local statistics, not invoices or account balances. Chat API usage may incur provider charges.
- Ask “音と振動を全部止めたい” to test a settings proposal. Review the proposed values and tap “適用する” to save them. No changes are applied automatically. Chat does not directly change API keys, endpoint, presets, dictionary, or game settings.
- Under “遊び心のあるキーボード”, enable “ゲーム演出” and choose a theme. It is OFF by default. Dragon, spaceship, cat, and wizard effects build energy while typing and release it on conversion. Tap the character to cycle themes. Effects make no additional API requests. Reduce Motion limits decorative movement.
- Under “キーボード設定”, key-click sounds vary by key type and can be disabled. Custom sounds follow media volume and respect silent mode. Without Full Access, system clicks are used.

Privacy
AI requests require explicit consent to the displayed endpoint. Conversion sends source text, minimal surrounding context, the registered dictionary, and the active style prompt. Chat sends the conversation, supported current settings, available model options, current time/time zone, and per-model usage statistics. API keys are used only for authentication and stored in the device Keychain. Chat history is discarded when its screen closes. Consent can be withdrawn at any time.

Bundled homophone/symbol indexes and middle-dot mappings are not sent to the API and add no API requests. This is not offline AI conversion.

Without Full Access, ordinary typing, delete, space, return, symbols, and keyboard switching remain available. AI conversion is disabled and explains the requirement.

Tested release build: <VERSION_AND_BUILD>
Physical devices and OS versions: <TESTED_DEVICES_AND_OS>

Privacy: https://kiyoka.github.io/Sumibi-iOS/privacy.html
Support: https://kiyoka.github.io/Sumibi-iOS/support.html

Review API key (kept active throughout review):
<ENTER_REVIEW_API_KEY_IN_APP_STORE_CONNECT_ONLY>
```
