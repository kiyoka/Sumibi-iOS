#!/usr/bin/env python3
# Copyright (c) 2026 Kiyoka Nishiyama
# SPDX-License-Identifier: MIT
"""Regenerate the iOS index using Sumibi-mac PR #37's pinned Sudachi rules."""

import argparse
import csv
import hashlib
import io
import unicodedata
import zipfile
from collections import defaultdict
from pathlib import Path

VERSION = "20260723"
HASHES = {
    "small_lex.zip": "b578ac9545899783d5d7e30d5d78d5d9dcf40b36965d4af0663ec2eb041c1093",
    "core_lex.zip": "a2b39e1572adab08a649b1390b134517adc55f1d733c59358b113298788bf31c",
}
HEADER = (
    f"# Derived from SudachiDict Core {VERSION}; see ThirdParty/SudachiDict/LEGAL\n"
    "# Sumibi candidate index: filtered common nouns, hiragana readings, ranked surfaces; "
    "generated from the upstream CSVs, not the unmodified dictionary.\n"
)


def verify(path, member):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    if digest.hexdigest() != HASHES[member + ".zip"]:
        raise ValueError(f"Unexpected source data: {path}")


def entries(path, member):
    verify(path, member)
    with zipfile.ZipFile(path) as archive:
        with archive.open(member + ".csv") as source:
            for row in csv.reader(io.TextIOWrapper(source, encoding="utf-8", newline="")):
                if len(row) < 13 or row[5:7] != ["名詞", "普通名詞"]:
                    continue
                reading = unicodedata.normalize("NFKC", row[11])
                if not reading or any(not ("ァ" <= c <= "ヶ" or c == "ー") for c in reading):
                    continue
                surface = row[4]
                if not any("\u3400" <= c <= "\u9fff" or c in "々〆〇" for c in surface):
                    continue
                if "\t" in surface or "\n" in surface:
                    continue
                try:
                    cost = int(row[3])
                except ValueError:
                    continue
                reading = "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in reading)
                yield reading, surface, cost


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--small", type=Path, required=True)
    parser.add_argument("--core", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    grouped = defaultdict(dict)
    for path, member in ((args.small, "small_lex"), (args.core, "core_lex")):
        for reading, surface, cost in entries(path, member):
            grouped[reading][surface] = min(grouped[reading].get(surface, cost), cost)
    with args.output.open("w", encoding="utf-8", newline="\n") as output:
        output.write(HEADER)
        for reading in sorted(grouped):
            surfaces = grouped[reading]
            if len(surfaces) < 2:
                continue
            ranked = sorted(surfaces, key=lambda s: (surfaces[s], s))[:32]
            output.write("\t".join((reading, *ranked)) + "\n")


if __name__ == "__main__":
    main()
