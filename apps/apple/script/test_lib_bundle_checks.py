#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent / "lib_bundle_checks.sh"

QUARANTINE = "0083;5f5e1000;Safari;"


class BundleChecksTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.bundle = Path(self._temporary_directory.name) / "Sample.app"
        self.bundle.mkdir()
        (self.bundle / "Contents").mkdir()
        self.bundle.chmod(0o755)
        (self.bundle / "Contents").chmod(0o755)

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def add_file(self, name: str, mode: int = 0o644) -> Path:
        path = self.bundle / "Contents" / name
        path.write_text("x", encoding="utf-8")
        path.chmod(mode)
        return path

    def quarantine(self, *paths: Path) -> None:
        result = subprocess.run(
            ["xattr", "-w", "com.apple.quarantine", QUARANTINE, *map(str, paths)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            self.skipTest(f"this filesystem refused the quarantine attribute: {result.stderr.strip()}")

    def run_check(self, function: str) -> tuple[int, list[str], bool]:
        """Run the function the way archive_mas.sh does: under `set -euo pipefail`, its
        output captured by a command substitution. Returns (exit code, output lines,
        whether the script went on past the substitution)."""
        script = (
            "set -euo pipefail\n"
            f'source "{LIB}"\n'
            f'found="$({function} "{self.bundle}")"\n'
            'printf "%s\\n" "$found"\n'
            'echo "--reached--" >&2\n'
        )
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
        lines = [line for line in result.stdout.splitlines() if line]
        return result.returncode, lines, "--reached--" in result.stderr

    def test_a_clean_bundle_prints_nothing_and_the_script_goes_on(self) -> None:
        self.add_file("Info.plist")
        for function in ("bundle_unreadable_files", "bundle_quarantined_files"):
            code, lines, reached = self.run_check(function)
            self.assertEqual((code, lines, reached), (0, [], True), function)

    def test_a_file_only_its_owner_can_read_is_named(self) -> None:
        hidden = self.add_file("embedded.provisionprofile", mode=0o600)
        self.add_file("Info.plist")
        code, lines, reached = self.run_check("bundle_unreadable_files")
        self.assertEqual((code, reached), (0, True))
        self.assertEqual(lines, [str(hidden)])

    def test_a_file_with_the_quarantine_attribute_is_named(self) -> None:
        marked = self.add_file("embedded.provisionprofile")
        self.add_file("Info.plist")
        self.quarantine(marked)
        code, lines, reached = self.run_check("bundle_quarantined_files")
        self.assertEqual((code, reached), (0, True))
        self.assertEqual(lines, [str(marked)])

    def test_only_the_first_five_are_printed_and_the_script_still_goes_on(self) -> None:
        # Enough long names that the pipe fills past head's early exit, which is
        # what ends an unguarded pipeline under pipefail.
        files = [self.add_file(f"{'n' * 80}-{index:04d}", mode=0o600) for index in range(900)]
        code, lines, reached = self.run_check("bundle_unreadable_files")
        self.assertEqual((code, reached, len(lines)), (0, True, 5))
        self.quarantine(*files)
        code, lines, reached = self.run_check("bundle_quarantined_files")
        self.assertEqual((code, reached, len(lines)), (0, True, 5))

    def test_a_missing_bundle_does_not_end_the_script(self) -> None:
        for function in ("bundle_unreadable_files", "bundle_quarantined_files"):
            script = (
                "set -euo pipefail\n"
                f'source "{LIB}"\n'
                f'found="$({function} "{self.bundle}/absent")"\n'
                'echo "reached:${found}:"\n'
            )
            result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, "reached::"), function)


if __name__ == "__main__":
    unittest.main()
