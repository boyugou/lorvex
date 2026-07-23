#!/usr/bin/env python3
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from verify_mcp_tool_catalog import definition_entries, duplicates


class VerifyMCPToolCatalogTests(unittest.TestCase):
    def test_definition_entries_read_domain_registry_files(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "TaskToolDefinitions.swift").write_text(
                """
enum TaskToolDefinitions {
  static let all: [ToolDefinition] = [
    .write(12, TaskToolCatalog.createTaskTool) { _, _ in fatalError() },
    .read(4, TaskToolCatalog.listTasksTool) { _, _ in fatalError() },
  ]
}
""",
                encoding="utf-8",
            )
            (root / "SystemToolDefinitions.swift").write_text(
                """
enum SystemToolDefinitions {
  static let all: [ToolDefinition] = [
    .read(0, SystemToolCatalog.getOverviewTool) { _, _ in fatalError() },
  ]
}
""",
                encoding="utf-8",
            )
            (root / "ToolRegistryTaskDispatch.swift").write_text(
                'case "ignored_legacy_dispatch": break',
                encoding="utf-8",
            )

            self.assertEqual(
                definition_entries(root),
                [
                    ("read", 0, "SystemToolCatalog.getOverviewTool"),
                    ("write", 12, "TaskToolCatalog.createTaskTool"),
                    ("read", 4, "TaskToolCatalog.listTasksTool"),
                ],
            )

    def test_duplicates_returns_each_repeated_value_once(self) -> None:
        self.assertEqual(duplicates(["a", "b", "a", "a"]), ["a"])


if __name__ == "__main__":
    unittest.main()
