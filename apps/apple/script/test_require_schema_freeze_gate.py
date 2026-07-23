#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


HELPER = Path(__file__).with_name("require_schema_freeze_gate.sh").resolve()


class RequireSchemaFreezeGateTests(unittest.TestCase):
    def _write_fake_tree(
        self,
        root: Path,
        *,
        statuses: dict[str, int] | None = None,
        freeze_output: str = "schema-freeze tripwire PASS: armed",
    ) -> Path:
        statuses = statuses or {}
        script_dir = root / "script"
        script_dir.mkdir()
        call_log = root / "calls.log"

        embed = script_dir / "verify_schema_embed.sh"
        embed.write_text(
            "#!/usr/bin/env bash\n"
            "printf 'embed\\n' >> \"$CALL_LOG\"\n"
            "echo 'schema embed checked'\n"
            f"exit {statuses.get('embed', 0)}\n",
            encoding="utf-8",
        )
        embed.chmod(0o755)

        for key, filename, output in (
            ("ladder", "verify_migration_ladder.py", "migration ladder checked"),
            ("payload", "verify_sync_payload_contract.py", "payload contract checked"),
            ("freeze", "verify_schema_freeze.py", freeze_output),
        ):
            release_argument_guard = (
                "import sys\n"
                "if sys.argv[1:] != ['--release']:\n"
                "    raise SystemExit(97)\n"
                if key == "freeze"
                else ""
            )
            (script_dir / filename).write_text(
                "import os\n"
                "from pathlib import Path\n"
                f"Path(os.environ['CALL_LOG']).open('a', encoding='utf-8').write('{key}\\n')\n"
                f"{release_argument_guard}"
                f"print({output!r})\n"
                f"raise SystemExit({statuses.get(key, 0)})\n",
                encoding="utf-8",
            )

        return call_log

    def _run(self, root: Path, call_log: Path, *, allow_unfrozen: bool = False):
        env = dict(os.environ)
        env["CALL_LOG"] = str(call_log)
        if allow_unfrozen:
            env["LORVEX_ALLOW_UNFROZEN"] = "1"
        else:
            env.pop("LORVEX_ALLOW_UNFROZEN", None)
        return subprocess.run(
            [
                "bash",
                "-c",
                f'source "{HELPER}"; require_schema_freeze_armed "{root}"',
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

    def test_armed_release_runs_all_four_schema_validators(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            call_log = self._write_fake_tree(root)

            result = self._run(root, call_log)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                call_log.read_text(encoding="utf-8").splitlines(),
                ["embed", "ladder", "payload", "freeze"],
            )

    def test_every_validator_runs_even_when_embed_validation_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            call_log = self._write_fake_tree(root, statuses={"embed": 1})

            result = self._run(root, call_log)

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(
                call_log.read_text(encoding="utf-8").splitlines(),
                ["embed", "ladder", "payload", "freeze"],
            )
            self.assertIn("FAILED", result.stderr)

    def test_dormant_freeze_still_requires_explicit_prelaunch_override(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            call_log = self._write_fake_tree(
                root,
                freeze_output="schema-freeze tripwire DORMANT: pre-launch",
            )

            refused = self._run(root, call_log)
            allowed = self._run(root, call_log, allow_unfrozen=True)

            self.assertNotEqual(refused.returncode, 0)
            self.assertEqual(allowed.returncode, 0, allowed.stderr)


if __name__ == "__main__":
    unittest.main()
