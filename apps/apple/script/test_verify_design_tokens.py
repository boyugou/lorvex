"""Unit tests for verify_design_tokens.py."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import verify_design_tokens as vdt


class DesignTokenVerifierTests(unittest.TestCase):
    def scan(self, source: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "Sources/LorvexApple/Views"
            target.mkdir(parents=True)
            (target / "Sample.swift").write_text(source, encoding="utf-8")
            return vdt.token_failures(root)

    def test_raw_hues_in_color_positions_are_flagged(self) -> None:
        failures = self.scan(
            "\n".join(
                [
                    "let a = Color.orange",
                    "Text(x).foregroundStyle(.red)",
                    "Chip(tint: .green)",
                    "shape.fill(isDone ? .green : .secondary)",
                    "let b = AnyShapeStyle(.blue)",
                    "let c = Color(red: 0.1, green: 0.2, blue: 0.3)",
                    ".tint(.orange)",
                ]
            )
        )
        self.assertEqual(len(failures), 7, failures)
        self.assertTrue(all("raw system hue" in f for f in failures))

    def test_tokens_and_semantic_styles_pass(self) -> None:
        failures = self.scan(
            "\n".join(
                [
                    "Text(x).foregroundStyle(LorvexDesign.Palette.overdue)",
                    "Chip(tint: LorvexDesign.Palette.neutral)",
                    ".foregroundStyle(.secondary)",
                    ".tint(.accentColor)",
                    ".font(LorvexDesign.Typography.tertiaryText)",
                    "RoundedRectangle(cornerRadius: LorvexDesign.Radius.card)",
                    "// Color.orange in a comment is fine",
                ]
            )
        )
        self.assertEqual(failures, [])

    def test_fixed_sizes_and_numeric_radii_are_flagged(self) -> None:
        failures = self.scan(
            "\n".join(
                [
                    ".font(.system(size: 11, weight: .medium))",
                    "RoundedRectangle(cornerRadius: 12, style: .continuous)",
                ]
            )
        )
        self.assertEqual(len(failures), 2, failures)
        self.assertIn("fixed point size", failures[0])
        self.assertIn("numeric corner radius", failures[1])

    def test_line_marker_and_allowlist_opt_out(self) -> None:
        marked = self.scan(".font(.system(size: 16))  // lorvex-design-token: allow")
        self.assertEqual(marked, [])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            allowed = root / "Sources/LorvexCore/Support/LorvexDesignSystem.swift"
            allowed.parent.mkdir(parents=True)
            allowed.write_text("public static let overdue: Color = .red\n", encoding="utf-8")
            self.assertEqual(vdt.token_failures(root), [])

    def test_real_tree_passes(self) -> None:
        self.assertEqual(vdt.token_failures(), [])


if __name__ == "__main__":
    unittest.main()
