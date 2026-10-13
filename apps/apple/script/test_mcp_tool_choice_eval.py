#!/usr/bin/env python3
"""Unit tests for mcp_tool_choice_eval.py: catalog text, schema checks, and scoring."""

import json
import unittest
from pathlib import Path

import mcp_tool_choice_eval as evaluation

TOOLS = [
    {
        "name": "create_task",
        "description": "Create a task.",
        "annotations": {"readOnlyHint": False},
        "inputSchema": {
            "type": "object",
            "properties": {
                "idempotency_key": {"type": "string"},
                "title": {"type": "string", "description": "What to do."},
                "priority": {"type": "integer", "enum": [1, 2, 3]},
                "tags": {"type": "array", "items": {"type": "string"}},
                "due": {"type": ["string", "null"]},
            },
            "required": ["title"],
        },
    },
    {
        "name": "get_overview",
        "description": "Read the day.",
        "annotations": {"readOnlyHint": True},
        "inputSchema": {"type": "object", "properties": {}},
    },
]
BY_NAME = {tool["name"]: tool for tool in TOOLS}


class CatalogTests(unittest.TestCase):
    def test_catalog_lists_access_description_and_params_without_the_idempotency_key(self) -> None:
        text = evaluation.compact_catalog(TOOLS)
        self.assertIn("### create_task [write]\nCreate a task.", text)
        self.assertIn("title*:string — What to do.", text)
        self.assertIn("priority:integer{1|2|3}", text)
        self.assertIn("tags:array<string>", text)
        self.assertNotIn("idempotency_key", text)
        self.assertIn("### get_overview [read]\nRead the day.\nparams: (none)", text)


class SchemaTests(unittest.TestCase):
    def problems(self, call: dict) -> list[str]:
        return evaluation.schema_problems(BY_NAME, call)

    def test_a_valid_call_has_no_problems(self) -> None:
        call = {"tool": "create_task", "args": {"title": "x", "priority": 2, "tags": ["a"], "due": None}}
        self.assertEqual(self.problems(call), [])

    def test_unknown_tool_missing_required_unknown_argument_enum_and_type(self) -> None:
        self.assertEqual(self.problems({"tool": "nope"}), ["nope: no such tool"])
        self.assertEqual(
            self.problems({"tool": "create_task", "args": {}}),
            ["create_task: missing required argument title"],
        )
        self.assertEqual(
            self.problems({"tool": "create_task", "args": {"title": "x", "colour": 1}}),
            ["create_task: unknown argument colour"],
        )
        self.assertIn("is not one of [1, 2, 3]", self.problems({"tool": "create_task", "args": {"title": "x", "priority": 9}})[0])
        self.assertIn("is not of type string", self.problems({"tool": "create_task", "args": {"title": 5}})[0])

    def test_a_boolean_is_not_an_integer(self) -> None:
        self.assertEqual(len(self.problems({"tool": "create_task", "args": {"title": "x", "priority": True}})), 1)


class ScoringTests(unittest.TestCase):
    SCENARIOS = [
        {"request": "Add a task", "accepted": ["create_task"]},
        {"request": "What is on today", "accepted": ["get_overview"]},
        {"request": "Plan", "accepted": ["get_overview", "create_task"]},
    ]

    def test_decisive_or_any_call_counts_and_misses_are_listed_with_their_doubt(self) -> None:
        answers = [
            {"id": 1, "calls": [{"tool": "create_task", "args": {"title": "x"}}], "decisive": "create_task"},
            {"id": 2, "calls": [{"tool": "create_task", "args": {"title": "x"}}], "decisive": "create_task", "doubt": "get_overview"},
            {"id": 3, "calls": [{"tool": "get_overview"}], "decisive": "something_else"},
        ]
        report = evaluation.check_answers(TOOLS, self.SCENARIOS, answers)
        self.assertEqual(report["matched"], 2)
        self.assertEqual([item["id"] for item in report["mismatches"]], [2])
        self.assertEqual(report["doubts"], [{"id": 2, "doubt": "get_overview"}])

    def test_a_call_to_an_unknown_tool_is_a_schema_problem_with_its_request_number(self) -> None:
        answers = [{"id": 1, "calls": [{"tool": "make_task", "args": {}}], "decisive": "make_task"}]
        report = evaluation.check_answers(TOOLS, self.SCENARIOS[:1], answers)
        self.assertEqual(report["schema_problems"], ["#1 make_task: no such tool"])

    def test_a_missing_answer_is_reported(self) -> None:
        report = evaluation.check_answers(TOOLS, self.SCENARIOS, [{"id": 1, "calls": [], "decisive": "create_task"}])
        self.assertEqual(report["missing"], [2, 3])

    def test_the_shipped_scenarios_are_well_formed(self) -> None:
        scenarios = json.loads(Path(evaluation.SCENARIOS).read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(scenarios), 40)
        for scenario in scenarios:
            self.assertTrue(scenario["request"].strip())
            self.assertTrue(scenario["accepted"])
        self.assertEqual(len({scenario["request"] for scenario in scenarios}), len(scenarios))


if __name__ == "__main__":
    unittest.main()
