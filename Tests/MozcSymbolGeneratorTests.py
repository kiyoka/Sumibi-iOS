# Copyright (c) 2026 Kiyoka Nishiyama
# SPDX-License-Identifier: MIT
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "mozc_symbols", Path(__file__).resolve().parents[1] / "Tools/generate_mozc_symbols.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class MozcSymbolGeneratorTests(unittest.TestCase):
    table = "ma\tま\nru\tる\nshi\tし\nsi\tし\nho\tほ\na\tあ\nka\tか\ni\tい\n" \
            "n\tん\nn'\tん\nnn\tん\n-\tー\nya\tや\nxtu\tっ\n"

    def test_aliases(self):
        inverse = generator.inverse_romaji(self.table)
        self.assertEqual(set(generator.romaji_aliases("ほし", inverse)), {"hoshi", "hosi"})
        self.assertIn("maru1", generator.romaji_aliases("まる1", inverse))
        self.assertIn("hoshi", generator.romaji_aliases("ホシ", inverse))
        self.assertIn("ka-shi", generator.romaji_aliases("かーし", inverse))
        aliases = generator.romaji_aliases("かんい", inverse)
        self.assertIn("kan'i", aliases)
        self.assertIn("kanni", aliases)
        self.assertNotIn("kani", aliases)
        self.assertIn("kasshi", generator.romaji_aliases("かっし", inverse))
        self.assertLessEqual(len(generator.romaji_aliases("し" * 20, inverse)), generator.MAX_ALIASES)

    def test_index_preserves_symbols_order_and_deduplicates(self):
        data = "POS\tCHAR\tReading\n記号\t☆\tほし しろぼし\n記号\t★\tほし\n記号\t☆\tほし\n数\t①\tまる1\n"
        index = generator.build_index(data, self.table)
        self.assertIn("hoshi\t☆\t★\n", index)
        self.assertIn("hosi\t☆\t★\n", index)
        self.assertIn("まる1\t①\n", index)
        self.assertIn("maru1\t①\n", index)
        self.assertNotIn("maru1\t1\n", index)
        self.assertEqual(index, generator.build_index(data, self.table))
        self.assertIn("BSD 3-Clause", index)

    def test_rejects_changed_source(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.tsv"
            path.write_text("modified", encoding="utf-8")
            with self.assertRaises(ValueError):
                generator.verified_text(path, generator.SYMBOL_SHA256)


if __name__ == "__main__":
    unittest.main()
