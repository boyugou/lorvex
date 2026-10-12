#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

import verify_plugin_skills as vps

MANIFEST = {
    "create_task": {
        "advertises_idempotency_key": True,
        "properties": {
            "title": "string",
            "planned_date": "string",
            "recurrence": "object{freq:enum[DAILY,WEEKLY],interval:integer}required[freq]",
        },
        "required": ["title"],
    },
    "batch_defer_tasks": {
        "advertises_idempotency_key": True,
        "properties": {
            "task_ids": "array<string>",
            "structured_reason": "enum[low_energy,not_today]",
        },
        "required": ["task_ids"],
    },
}

SKILL = """---
name: {name}
description: {description}
---

# Skill

Call `create_task` with `planned_date`, then `batch_defer_tasks` with
`structured_reason` set to `not_today`.
"""


class PluginSkillVerifierTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.skills = root / "skills"
        self.skills.mkdir()
        self.manifest = root / "manifest.json"
        self.manifest.write_text(json.dumps(MANIFEST), encoding="utf-8")
        self.sources = root / "Sources"
        self.sources.mkdir()

    def write_skill(self, directory, text):
        folder = self.skills / directory
        folder.mkdir(exist_ok=True)
        (folder / "SKILL.md").write_text(text, encoding="utf-8")

    def failures(self):
        return vps.skill_failures(self.skills, self.manifest, (self.sources,))

    def test_real_tree_passes(self):
        self.assertEqual(vps.skill_failures(), [])

    def test_a_skill_that_names_real_tools_and_arguments_passes(self):
        self.write_skill("plan", SKILL.format(name="plan", description="Plan the day."))
        self.assertEqual(self.failures(), [])

    def test_nested_fields_and_enum_values_are_known(self):
        self.write_skill(
            "plan",
            SKILL.format(name="plan", description="Plan the day.") + "\nUse `low_energy`.\n")
        self.assertEqual(self.failures(), [])

    def test_a_renamed_tool_is_named_with_its_skill(self):
        self.write_skill(
            "plan",
            SKILL.format(name="plan", description="Plan the day.") + "\nThen `schedule_task`.\n")
        failures = self.failures()
        self.assertEqual(len(failures), 1)
        self.assertIn("skills/plan/SKILL.md", failures[0])
        self.assertIn("`schedule_task`", failures[0])

    def test_a_word_the_sources_use_is_known_but_a_longer_word_is_not(self):
        (self.sources / "Instructions.swift").write_text(
            'let text = """\nSections: user_profile, pending_followups_extra.\n"""\n',
            encoding="utf-8")
        self.write_skill(
            "plan",
            SKILL.format(name="plan", description="Plan the day.")
            + "\nRead `user_profile` and `pending_followups`.\n")
        failures = self.failures()
        self.assertEqual(len(failures), 1)
        self.assertIn("`pending_followups`", failures[0])

    def test_front_matter_name_must_be_the_directory(self):
        self.write_skill("plan", SKILL.format(name="plan-day", description="Plan the day."))
        failures = self.failures()
        self.assertEqual(len(failures), 1)
        self.assertIn("is not 'plan'", failures[0])

    def test_a_skill_needs_a_description(self):
        self.write_skill("plan", SKILL.format(name="plan", description=""))
        failures = self.failures()
        self.assertEqual(len(failures), 1)
        self.assertIn("no one-line description", failures[0])

    def test_a_skill_needs_front_matter(self):
        self.write_skill("plan", "# Plan\n\nCall `create_task`.\n")
        self.assertIn("no front matter", self.failures()[0])

    def test_a_directory_without_a_skill_file_fails(self):
        (self.skills / "empty").mkdir()
        self.assertEqual(self.failures(), ["empty: no SKILL.md"])

    def test_no_skills_at_all_fails(self):
        self.assertIn("no skills found", self.failures()[0])


if __name__ == "__main__":
    unittest.main()
