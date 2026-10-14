from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import github_release as release


class GitHubReleaseTests(unittest.TestCase):
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
