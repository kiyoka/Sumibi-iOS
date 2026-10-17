# SudachiDict Core 20260723 candidate index

The derived data in `SumibiKeyboard/ConversionDictionary/SudachiCandidates.tsv`
is not covered solely by Sumibi's MIT license. Retain `LICENSE-2.0.txt`, `LEGAL`,
and `ATTRIBUTION.txt` in repository distributions and application bundles.
The app's License screen reads these bundled files offline.

The index was adapted from Sumibi-mac PR #37, fixed commit
`e5cd77c62c89fecd3b5d34f21d2e79d851db4f62`.
The original mac TSV SHA-256 is
`56bddbf33a93c54bd4c722b6fe00fde93017fe67cad283d99cd63de68c847cf2`.
The iOS copy adds a prominent transformation notice; data rows remain identical.

Official upstream: https://github.com/WorksApplications/SudachiDict/tree/v20260723

Pinned source archives:

- https://d2ej7fkh96fzlu.cloudfront.net/sudachidict-raw/20260723/small_lex.zip
  SHA-256: `b578ac9545899783d5d7e30d5d78d5d9dcf40b36965d4af0663ec2eb041c1093`
- https://d2ej7fkh96fzlu.cloudfront.net/sudachidict-raw/20260723/core_lex.zip
  SHA-256: `a2b39e1572adab08a649b1390b134517adc55f1d733c59358b113298788bf31c`

Regenerate from these archives (outside the repository):

```sh
python3 Tools/generate_sudachi_candidates.py \
  --small /path/to/small_lex.zip --core /path/to/core_lex.zip \
  --output /private/tmp/SudachiCandidates.tsv
cmp /private/tmp/SudachiCandidates.tsv SumibiKeyboard/ConversionDictionary/SudachiCandidates.tsv
```

The generator checks both source hashes. It selects common nouns with
kanji-containing surfaces and katakana readings, converts readings to hiragana,
retains readings with at least two distinct surfaces, and ranks up to 32 surfaces
by minimum word cost (surface text breaks ties). This is not a semantic-equivalence
dictionary. No SKK-JISYO.L or Emacs generated dictionary is included.

The TSV is looked up locally and never sent to the API. Only additional-candidate
responses with a whole hiragana candidate trigger the Sudachi lookup.
The separate original `BuiltinCandidates.tsv` handles exact source mappings.

Upstream license file SHA-256:

- LEGAL: `725a8776b38e058b185e905594bc9a2437dbf3787df022fffeefedb9a84e4665`
- LICENSE-2.0.txt: `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`
