from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import github_release as release


class GitHubReleaseTests(unittest.TestCase):
    def test_build_commit_accepts_descriptions_and_ignores_other_builds_and_message_bodies(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            repo = Path(name)

            def local_run(command: list[str]) -> str:
                return subprocess.run(command, cwd=repo, capture_output=True, text=True, check=True).stdout.strip()

            def commit(subject: str, body: str | None = None) -> str:
                command = [
                    "git", "-c", "user.name=Fixture", "-c", "user.email=fixture",
                    "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                    "commit", "--quiet", "--allow-empty", "-m", subject,
                ]
                if body is not None:
                    command.extend(["-m", body])
                local_run(command)
                return local_run(["git", "rev-parse", "HEAD"])

            local_run(["git", "init", "--quiet"])
            exact = commit("Build 144")
            described = commit("Build 145: improve Review and calendar")
            commit("Build 1450: a different build")
            commit("Record release delivery", "Build 145")
            with patch.object(release, "run", side_effect=local_run):
                self.assertEqual(release.build_commit(144), exact)
                self.assertEqual(release.build_commit(145), described)
                with self.assertRaises(SystemExit):
                    release.build_commit(146)

    def test_dmg_for_build_finds_the_one_dmg_of_that_build(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            dist = Path(name)
            for file in [
                "Lorvex-macOS-1.0.0+132-arm64.dmg",
                "Lorvex-macOS-1.0.0+133-arm64.dmg",
                "Lorvex-macOS-1.0.0+133-arm64.dmg.sha256",
                "Lorvex-macOS-MAS-1.0.0+133.pkg",
            ]:
                (dist / file).write_bytes(b"x")
            path, version = release.dmg_for_build(133, dist)
            self.assertEqual(path.name, "Lorvex-macOS-1.0.0+133-arm64.dmg")
            self.assertEqual(version, "1.0.0")
            with self.assertRaises(SystemExit):
                release.dmg_for_build(134, dist)

    def test_publish_passes_an_absolute_notes_path_to_github(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            dmg = root / "fixture.dmg"
            dmg.write_bytes(b"fixture")
            notes = root / "notes.md"
            source_commit = "a" * 40
            notes.write_text(f"Changes\n{release.sha256_of(dmg)}\n{source_commit[:7]}\n")
            relative_notes = Path(os.path.relpath(notes))
            created = []

            def github(command: list[str], **kwargs: object) -> str:
                if command[:3] == ["gh", "release", "create"]:
                    passed_notes = Path(command[command.index("--notes-file") + 1])
                    self.assertTrue(passed_notes.is_absolute())
                    self.assertEqual(passed_notes, notes.resolve())
                    created.append(command)
                return ""

            with (
                patch.object(release, "dmg_for_build", return_value=(dmg, "1.0.0")),
                patch.object(release, "build_commit", return_value=source_commit),
                patch.object(release, "verify_dmg"),
                patch.object(release, "run", side_effect=github),
            ):
                self.assertEqual(release.command_publish(145, relative_notes, False), 0)
            self.assertEqual(len(created), 1)

    def test_dmg_for_build_refuses_two_dmgs_of_one_build(self) -> None:
        with tempfile.TemporaryDirectory() as name:
            dist = Path(name)
            (dist / "Lorvex-macOS-1.0.0+133-arm64.dmg").write_bytes(b"x")
            (dist / "Lorvex-macOS-1.1.0+133-arm64.dmg").write_bytes(b"y")
            with self.assertRaises(SystemExit):
                release.dmg_for_build(133, dist)

    def test_notes_problems_names_what_is_missing(self) -> None:
        sha = "a" * 64
        good = f"changes\nshould print `{sha}`.\nBuilt from commit `abc1234`.\n"
        self.assertEqual(release.notes_problems(good, sha, "abc1234"), [])
        self.assertEqual(
            len(release.notes_problems(f"{release.PLACEHOLDER}\n{good}", sha, "abc1234")), 1
        )
        self.assertEqual(len(release.notes_problems("changes only", sha, "abc1234")), 2)
        self.assertEqual(len(release.notes_problems(good + "ask a@b.c\n", sha, "abc1234")), 1)
        # A lone @ (the character a CSV note names) and a link are not addresses.
        self.assertEqual(release.notes_problems(good + "starts with `@`\n", sha, "abc1234"), [])
        self.assertEqual(
            release.notes_problems(good + "https://example.com/a@b\n", sha, "abc1234"), []
        )

    def test_releases_to_delete_keeps_other_versions_and_newer_builds(self) -> None:
        tags = ["v1.0.0+131", "v1.0.0+132", "v1.0.0+134", "v1.1.0+120", "v0.9.0+5", "latest"]
        self.assertEqual(release.releases_to_delete(tags, "1.0.0", 133), ["v1.0.0+131", "v1.0.0+132"])
        self.assertEqual(release.releases_to_delete([], "1.0.0", 133), [])

    def test_newest_build_before_reads_local_and_remote_tags(self) -> None:
        tags = ["v1.0.0+134", "v1.0.0+135", "v1.0.0+136", "v1.0.0+137", "v1.0.0+notes"]
        self.assertEqual(release.newest_build_before(137, tags), 136)
        self.assertEqual(release.newest_build_before(136, tags[:2]), 135)
        self.assertEqual(release.newest_build_before(120, tags), 119)

    def test_the_notes_skeleton_is_complete_but_marked_unfinished(self) -> None:
        sha = "b" * 64
        skeleton = release.NOTES_TEMPLATE.format(
            version="1.0.0",
            build=133,
            previous=132,
            placeholder=release.PLACEHOLDER,
            dmg=release.ASSET_DMG,
            sha=sha,
            commit="abc1234",
        )
        self.assertIn("(132)", skeleton)
        self.assertIn(sha, skeleton)
        self.assertEqual(
            release.notes_problems(skeleton, sha, "abc1234"), ["the notes still hold the WHAT CHANGED marker"]
        )


if __name__ == "__main__":
    unittest.main()
