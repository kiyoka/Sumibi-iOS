# Copyright (c) 2026 Kiyoka Nishiyama
# SPDX-License-Identifier: MIT
"""Build a local symbol index from pinned, BSD-licensed Mozc data.

The generator is MIT; its output is derived from Mozc and remains subject to
Mozc's BSD 3-Clause notice. No downloads or third-party Python dependencies.
"""
import argparse
from collections import defaultdict
from functools import lru_cache
import hashlib
from pathlib import Path

COMMIT = "0136c35782536cb43d710575c311cd4185982738"
SYMBOL_SHA256 = "bc68b032a195f203dccba6f95667424199ba9b185fee2be64eeaa959253c097a"
ROMAJI_SHA256 = "fcb900e311d32ced05499c86e236d1084fb0c0937398deb6311fc6c7287a7821"
MAX_ALIASES = 128


def verified_text(path, expected):
    data = Path(path).read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"Unexpected source SHA-256: {path}")
    return data.decode("utf-8")


def hiragana(text):
    # Convert kana only: NFKC would destroy distinctions such as ① versus 1.
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def inverse_romaji(table):
    result = defaultdict(set)
    for line in table.splitlines():
        fields = line.split("\t")
        # Rules with a carry (kk -> っ, leaving k) are handled separately below.
        if len(fields) != 2:
            continue
        roman, kana = fields
        kana = hiragana(kana)
        if roman.isascii() and kana and all("ぁ" <= c <= "ゖ" or c == "ー" for c in kana):
            result[kana].add(roman)
    return result


def romaji_aliases(reading, inverse):
    text = hiragana(reading)

    @lru_cache(None)
    def suffix(position):
        if position == len(text):
            return ("",)
        choices = set()
        # Prefer a compound kana rule (e.g. しゅ -> shu/syu), not shi+xyu.
        lengths = [length for length in range(min(3, len(text) - position), 0, -1)
                   if text[position:position + length] in inverse]
        if lengths:
            length = lengths[0]
            kana = text[position:position + length]
            for tail in suffix(position + length):
                for roman in inverse[kana]:
                    # A bare n before a vowel/y/n would be parsed as another kana.
                    if kana == "ん" and roman == "n" and tail and tail[0] in "aiueoyn":
                        continue
                    choices.add(roman + tail)
        elif text[position].isascii():
            choices.update(text[position].lower() + tail for tail in suffix(position + 1))
        if text[position] == "っ":
            for tail in suffix(position + 1):
                if tail and tail[0].isascii() and tail[0].isalpha() and tail[0] not in "aiueon":
                    choices.add(tail[0] + tail)
        return tuple(sorted(choices, key=lambda value: (len(value), value))[:MAX_ALIASES])

    return suffix(0)


def build_index(symbols, roman_table):
    inverse = inverse_romaji(roman_table)
    entries = defaultdict(dict)  # Ordered de-duplication preserves Mozc's row order.
    for line in symbols.splitlines()[1:]:
        fields = line.split("\t")
        if len(fields) < 3 or not fields[1]:
            continue
        surface = fields[1]
        for reading in fields[2].split():
            keys = {reading.lower(), hiragana(reading).lower()}
            keys.update(romaji_aliases(reading, inverse))
            for key in keys:
                if key:
                    entries[key][surface] = None
    header = (
        "# Derived from Mozc symbol.tsv and romanji-hiragana.tsv; BSD 3-Clause.\n"
        "# Copyright 2010-2018, Google Inc. See ThirdParty/Mozc/LICENSE.\n"
        f"# Source commit: {COMMIT}\n"
        "# Sumibi changes: reading-to-symbol index, kana/romaji aliases, sorted keys, deduplication.\n"
    )
    return header + "".join(key + "\t" + "\t".join(entries[key]) + "\n" for key in sorted(entries))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--romaji", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = build_index(verified_text(args.symbols, SYMBOL_SHA256),
                         verified_text(args.romaji, ROMAJI_SHA256))
    Path(args.output).write_text(output, encoding="utf-8")
    print(f"Wrote {len(output.splitlines()) - 4:,} readings, {len(output.encode('utf-8')):,} bytes")


if __name__ == "__main__":
    main()
