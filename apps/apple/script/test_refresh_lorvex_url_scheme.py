#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "script" / "refresh_lorvex_url_scheme.sh"
BUILD_AND_RUN = ROOT / "script" / "build_and_run.sh"


class RefreshLorvexURLSchemeTests(unittest.TestCase):
    def test_refresh_script_is_shell_valid(self) -> None:
        subprocess.run(["bash", "-n", str(SCRIPT)], check=True)

    def test_refresh_script_is_dry_run_by_default_and_registers_target(self) -> None:
        source = SCRIPT.read_text()

        self.assertIn("APPLY=0", source)
        self.assertIn('"$LSREGISTER" -u "$bundle"', source)
        self.assertIn("couldn't unregister stale LaunchServices path", source)
        self.assertIn('"$LSREGISTER" -f "$bundle"', source)
        self.assertIn('"$LSREGISTER" -dump', source)
        self.assertIn("registered_lorvex_bundles", source)
        self.assertIn('re.split(r"(?m)^-{20,}', source)
        self.assertIn('claimed schemes:            {scheme}:', source)
        self.assertIn('"/Applications/$APP_DISPLAY_NAME.app"', source)
        self.assertIn('"/Applications/$APP_NAME.app"', source)
        self.assertIn("Refreshing $URL_SCHEME:// LaunchServices registration", source)

    def test_build_and_run_registers_only_the_launching_modes_after_signing(self) -> None:
        source = BUILD_AND_RUN.read_text()
        codesign_verify = source.index('codesign --verify --deep --strict "$APP_BUNDLE"')
        case_statement = source.index('case "$MODE" in')
        modes = source[case_statement:]

        self.assertLess(codesign_verify, case_statement)
        self.assertIn('"$LSREGISTER" -f "$APP_BUNDLE"', source)
        # A bundle staged for packaging is never registered: it would take
        # this Mac's lorvex:// links and widget taps from the installed app.
        stage_mode = modes[modes.index("--stage-only|stage)") : modes.index("run)")]
        self.assertNotIn("refresh_launchservices_registration", stage_mode)
        for mode in ("run)", "--debug|debug)", "--logs|logs)", "--telemetry|telemetry)", "--verify|verify)"):
            branch = modes[modes.index(mode) :]
            branch = branch[: branch.index(";;")]
            self.assertIn("refresh_launchservices_registration", branch, mode)


if __name__ == "__main__":
    unittest.main()
