# App Store商品ページ メタデータ（日本語）

Sumibi `1.0.0`の初回App Store申請で使用する日本語メタデータ。

## App情報

### App Name

19文字（上限30文字）。

```text
Sumibi - AI日本語キーボード
```

### Subtitle

16文字（上限30文字）。

```text
ローマ字を自然な日本語にAI変換
```

## バージョン情報

### Promotional Text

81文字（上限170文字）。

```text
英字QWERTYキーボードのみで日本語を入力できます。キーボードは1画面のみで切り替え不要です。OpenAI互換APIを使い、ローマ字を自然な日本語へ変換します。
```

### Description

```text
Sumibiは、ローマ字で入力した文章を、AIで自然な日本語へ変換するカスタムキーボードです。

英字QWERTYの1画面で文章を入力し、専用の変換キーを押すだけ。かな入力用キーボードへ切り替えることなく、日本語を入力できます。

【主な機能】
・ローマ字の文章を自然な日本語へ変換
・英字QWERTYの1画面で、かな入力への切り替えが不要
・通常変換、タイプミス補正、ひらがな、カタカナ、漢字多めなどの追加候補
・変換結果を原文へ戻せるUndo
・製品名や固有名詞の表記を登録できるユーザー辞書
・数字段と記号キーを備えた英字QWERTYキーボード
・クリップボードから読み込んだ文章の変換
・触覚フィードバックとキークリック音の設定

【利用に必要なもの】
変換には、利用者自身で用意したOpenAI互換APIのURL、モデル名、APIキーが必要です。APIの利用料金や利用条件は、選択したAPI提供者の定めに従います。SumibiのダウンロードにAPI利用料金は含まれません。

ネットワーク変換を利用するには、iOSのキーボード設定でSumibiを追加し、「フルアクセスを許可」を有効にする必要があります。フルアクセスを許可しない場合でも通常の英字入力はできますが、AI変換は利用できません。

【プライバシー】
AI変換は、アプリ内で送信先を確認し、第三者AIへのデータ送信に同意した場合に限り実行されます。変換キーを押すと、変換対象、変換に必要な最小限の周辺文脈、登録済みユーザー辞書が、表示されたAPI送信先へ送られます。

Sumibi運営のサーバーは経由しません。キー入力、変換対象、ユーザー辞書、APIキーをSumibi運営のサーバーへ保存しません。APIキーは端末内のKeychainに保存され、iCloudへ同期されません。送信先でのデータ処理や保存は、利用者が選択したAPI提供者の規約に従います。

Sumibiはオープンソースソフトウェアです。
```

### Keywords

UTF-8で95バイト（上限100バイト）。App Nameと重複する`Sumibi`と`AI`は含めない。

```text
日本語,キーボード,ローマ字,文章変換,かな漢字,IME,入力支援,辞書,QWERTY
```

### URL

| 項目 | URL |
| --- | --- |
| Support URL | https://kiyoka.github.io/Sumibi-iOS/support.html |
| Privacy Policy URL | https://kiyoka.github.io/Sumibi-iOS/privacy.html |
| Marketing URL | https://kiyoka.github.io/Sumibi-iOS/ |

### Copyright

App Store Connectが著作権記号を自動的に付加するため、記号は入力しない。

```text
2026 Kiyoka Nishiyama
```

## 入力時の確認事項

- 初回ローカライズは日本語を選択する。
- `What’s New in This Version`は初回バージョンでは入力しない。
- Descriptionはプレーンテキストとして入力し、HTMLを使用しない。
- APIキー、審査用の認証情報、個人情報を商品ページへ記載しない。
- スクリーンショットと説明文に、未実装のフリック入力、音声入力、オフラインAI変換を含めない。
- API提供者の料金、データ保持、モデル性能をSumibiが保証する表現を使用しない。

## Apple公式上限（2026年8月7日確認）

| 項目 | 上限 |
| --- | ---: |
| App Name | 30文字 |
| Subtitle | 30文字 |
| Promotional Text | 170文字 |
| Description | 4,000文字 |
| Keywords | 100バイト |

参考：

- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
