#!/usr/bin/env python3
from __future__ import annotations

import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent / "lib_run_masked.sh"
# Built at run time so the source never holds a password-shaped string or an address,
# which the public-safety gate rejects in a tracked file.
FAKE_PASSWORD = "-".join(("abcd", "efgh", "ijkl", "mnop"))
FAKE_EMAIL = "someone" + "@" + "example.com"
MASK = (
    "s/[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}/[redacted]/g; "
    "s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}/[email]/g"
)


class RunMaskedTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.directory = Path(self._temporary_directory.name)
        self.log = self.directory / "step.log"
        self.counter = self.directory / "attempts"

    def tearDown(self) -> None:
        self._temporary_directory.cleanup()

    def step(self, body: str) -> Path:
        """A fake release step that counts its attempts, then runs `body`."""
        script = self.directory / "step.sh"
        script.write_text(
            "#!/usr/bin/env bash\n"
            f'echo x >> "{self.counter}"\n'
            f'attempt=$(wc -l < "{self.counter}" | tr -d " ")\n' + body,
            encoding="utf-8",
        )
        script.chmod(0o755)
        return script

    def run_masked(self, script: Path) -> int:
        result = subprocess.run(
            [
                "bash",
                "-c",
                f'MASK={shlex.quote(MASK)}; source "{LIB}"; run_masked "{self.log}" "{script}"',
            ],
            capture_output=True,
            text=True,
        )
        return result.returncode

    def attempts(self) -> int:
        return len(self.counter.read_text().splitlines()) if self.counter.exists() else 0

    def test_a_step_that_succeeds_runs_once(self) -> None:
        script = self.step('echo "done"\nexit 0\n')
        self.assertEqual(self.run_masked(script), 0)
        self.assertEqual(self.attempts(), 1)
        self.assertIn("done", self.log.read_text())

    def test_a_transient_failure_is_retried_once_and_can_recover(self) -> None:
        script = self.step(
            'if [ "$attempt" = 1 ]; then echo "The network connection was lost."; exit 65; fi\n'
            'echo "recovered"\nexit 0\n'
        )
        self.assertEqual(self.run_masked(script), 0)
        self.assertEqual(self.attempts(), 2)
        text = self.log.read_text()
        self.assertIn("transient network failure", text)
        self.assertIn("recovered", text)

    def test_a_transient_failure_that_persists_stops_after_the_second_attempt(self) -> None:
        script = self.step('echo "NSURLErrorDomain error -1005"\nexit 7\n')
        self.assertEqual(self.run_masked(script), 7)
        self.assertEqual(self.attempts(), 2)

    def test_a_gateway_timeout_counts_as_transient(self) -> None:
        script = self.step('echo "upload failed: HTTP 504"\nexit 1\n')
        self.assertEqual(self.run_masked(script), 1)
        self.assertEqual(self.attempts(), 2)

    def test_any_other_failure_is_not_retried(self) -> None:
        script = self.step('echo "error: No profiles for bundle id were found"\nexit 65\n')
        self.assertEqual(self.run_masked(script), 65)
        self.assertEqual(self.attempts(), 1)

    def test_credentials_are_masked_in_the_log(self) -> None:
        script = self.step(f'echo "password {FAKE_PASSWORD} for {FAKE_EMAIL}"\nexit 0\n')
        self.assertEqual(self.run_masked(script), 0)
        text = self.log.read_text()
        self.assertIn("[redacted]", text)
        self.assertIn("[email]", text)
        self.assertNotIn(FAKE_PASSWORD, text)
        self.assertNotIn(FAKE_EMAIL, text)


if __name__ == "__main__":
    unittest.main()
