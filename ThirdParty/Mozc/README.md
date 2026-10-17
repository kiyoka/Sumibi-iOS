# Mozc記号辞書の出典

- 公式リポジトリ：https://github.com/google/mozc
- 固定コミット：`0136c35782536cb43d710575c311cd4185982738`
- 利用するデータ：`src/data/symbol/symbol.tsv`、`src/data/preedit/romanji-hiragana.tsv`
- 適用条件：BSD 3-Clause。著作権・条件・免責文を保持する。
- `LICENSE` は同じコミットの原文全体を無変更で同梱する。後半の一般語彙辞書向けの別条件は、今回の利用ファイルの条件ではない。
- 元データのライセンス説明：https://github.com/google/mozc#license

Sumibi独自の生成プログラムはMIT。生成された索引はMozc由来データとしてBSDの表示を保持し、独自MITへ変更しない。
アプリとキーボードへこのフォルダを同梱し、アプリの「ライセンス」から出典表示と原文全文を閲覧できる。

## 固定元データのSHA-256

| ファイル | SHA-256 |
|---|---|
| symbol.tsv | `bc68b032a195f203dccba6f95667424199ba9b185fee2be64eeaa959253c097a` |
| romanji-hiragana.tsv | `fcb900e311d32ced05499c86e236d1084fb0c0937398deb6311fc6c7287a7821` |
| LICENSE | `44cdd923b91ea9199293abecc2762c70c87dbf1e581c027a94c416368d1a648c` |

## 再生成

上記コミットのrawファイルを取得し、リポジトリのトップで実行する。生成プログラムは2つの入力ハッシュが一致しない場合に停止する。

```sh
python3 Tools/generate_mozc_symbols.py \
  --symbols /path/to/symbol.tsv \
  --romaji /path/to/romanji-hiragana.tsv \
  --output SumibiKeyboard/ConversionDictionary/MozcSymbols.tsv
```

読みと記号を抽出し、カタカナの読みからひらがな、Mozcのローマ字表からローマ字別名を作成する。
拗音は最長のかな単位を使い、通常のヘボン式／訓令式、促音、撥音、長音、数字混じりを扱う。
別名の組み合わせは読みごとに最大128件。あらゆる小書き文字の分割入力を網羅するIMEではない。
ASCIIの大文字小文字を区別しない。記号が別文字になるNFKC互換正規化は使用しない。
元の読みも残す。読みごとの記号は元ファイルの順序で重複を除く。
元表には絵文字も含まれるが、字形画像・フォントは取り込まず、Unicode文字列だけを使う。

同梱索引：18,581読み、406,740 bytes。
SHA-256：`43b5c2eac87e8e94fbfb1477084871b062cda9f81c724e6cee9461040a7c5449`。
