"""Unit tests for docs/hive/tools/inventory.py (run: python3 -m unittest discover -s tests -p 'test_*.py')."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "docs" / "hive" / "tools"))

import inventory  # noqa: E402


class TestParseEnv(unittest.TestCase):
    def test_none(self) -> None:
        self.assertEqual(inventory.parse_env(None), {})

    def test_malformed_list_entry(self) -> None:
        out = inventory.parse_env(["FOO=bar", "noequals"])
        self.assertIn("malformed", out["noequals"])

    def test_dict_inline_and_env(self) -> None:
        out = inventory.parse_env({"A": "1", "B": "${X}"})
        self.assertEqual(out["A"], "inline `1`")
        self.assertEqual(out["B"], "env")


class TestNormalizeLabels(unittest.TestCase):
    def test_none(self) -> None:
        self.assertEqual(inventory.normalize_labels(None), [])

    def test_dict(self) -> None:
        self.assertEqual(
            sorted(inventory.normalize_labels({"a": "b", "c": "d"})),
            ["a=b", "c=d"],
        )

    def test_list(self) -> None:
        self.assertEqual(inventory.normalize_labels(["x=y"]), ["x=y"])

    def test_scalar_is_not_iterated_as_chars(self) -> None:
        self.assertEqual(inventory.normalize_labels("bad"), [])


class TestDependsOn(unittest.TestCase):
    def test_dict_with_non_dict_value_uses_value(self) -> None:
        raw = {"depends_on": {"db": "service_started"}}
        facts = inventory.extract_service("web", raw)
        self.assertEqual(facts.depends_on, ["db (service_started)"])

    def test_dict_with_dict_value(self) -> None:
        raw = {"depends_on": {"db": {"condition": "service_healthy"}}}
        facts = inventory.extract_service("web", raw)
        self.assertEqual(facts.depends_on, ["db (service_healthy)"])


if __name__ == "__main__":
    unittest.main()
