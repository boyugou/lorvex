#!/usr/bin/env python3

from __future__ import annotations

import ast
import json
import os
import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest import mock

import mcp_stdio_smoke


class McpStdioSmokeSafetyTests(unittest.TestCase):
    def test_valid_signature_without_entitlement_blob_is_unsandboxed(self) -> None:
        binary = Path("/tmp/LorvexMCPHost")
        entitlement_read = CompletedProcess(
            ["codesign", "-d"], 0, stdout=b"", stderr=b""
        )
        signature_verify = CompletedProcess(
            ["codesign", "--verify"], 0, stdout=b"", stderr=b""
        )
        with mock.patch.object(
            mcp_stdio_smoke.subprocess,
            "run",
            side_effect=[entitlement_read, signature_verify],
        ) as run:
            self.assertEqual(mcp_stdio_smoke.signed_entitlements(binary), {})

        self.assertEqual(run.call_count, 2)
        self.assertEqual(
            run.call_args_list[1].args[0],
            ["codesign", "--verify", "--strict", str(binary)],
        )

    def test_empty_entitlement_blob_with_invalid_signature_fails_closed(self) -> None:
        binary = Path("/tmp/LorvexMCPHost")
        entitlement_read = CompletedProcess(
            ["codesign", "-d"], 0, stdout=b"", stderr=b""
        )
        signature_verify = CompletedProcess(
            ["codesign", "--verify"], 1, stdout=b"", stderr=b"invalid"
        )
        with mock.patch.object(
            mcp_stdio_smoke.subprocess,
            "run",
            side_effect=[entitlement_read, signature_verify],
        ):
            with self.assertRaisesRegex(
                mcp_stdio_smoke.McpSmokeFailure, "signature verification failed"
            ):
                mcp_stdio_smoke.signed_entitlements(binary)

    def test_sandboxed_binary_without_cli_opt_in_never_reaches_reset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "LorvexMCPHost"
            binary.touch(mode=0o755)
            with (
                mock.patch.dict(
                    os.environ,
                    {"MCP_HOST_BINARY": str(binary)},
                    clear=False,
                ),
                mock.patch.object(
                    mcp_stdio_smoke, "is_sandboxed_binary", return_value=True
                ),
                mock.patch.object(
                    mcp_stdio_smoke, "real_app_group_smoke_isolation"
                ) as isolation,
                mock.patch.object(mcp_stdio_smoke, "run_smoke") as run_smoke,
            ):
                with self.assertRaisesRegex(
                    mcp_stdio_smoke.McpSmokeFailure,
                    "refusing to launch a sandboxed MCP helper",
                ):
                    mcp_stdio_smoke.main([])
            isolation.assert_not_called()
            run_smoke.assert_not_called()

    def test_sandboxed_reset_requires_environment_acknowledgement_before_side_effects(
        self,
    ) -> None:
        with (
            mock.patch.dict(
                os.environ,
                {mcp_stdio_smoke.DESTRUCTIVE_RESET_ENV: "0"},
                clear=False,
            ),
            mock.patch.object(mcp_stdio_smoke, "signed_entitlements") as entitlements,
            mock.patch.object(mcp_stdio_smoke, "stop_lorvex_processes") as stop,
            mock.patch.object(mcp_stdio_smoke, "reset_real_app_group_state") as reset,
        ):
            with self.assertRaisesRegex(
                mcp_stdio_smoke.McpSmokeFailure,
                mcp_stdio_smoke.DESTRUCTIVE_RESET_ENV,
            ):
                with mcp_stdio_smoke.real_app_group_smoke_isolation(
                    Path("/unused/LorvexMCPHost"),
                    "group.com.lorvex.apple",
                    ("Lorvex", "LorvexMCPHost"),
                ):
                    self.fail("destructive context unexpectedly yielded")
        entitlements.assert_not_called()
        stop.assert_not_called()
        reset.assert_not_called()

    def test_unsandboxed_packaging_flag_still_uses_only_temporary_database(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "LorvexMCPHost"
            binary.touch(mode=0o755)
            temporary_context = mock.MagicMock()
            temporary_context.__enter__.return_value = (
                Path(tmp) / "isolated.db",
                {"LORVEX_APPLE_DB_PATH": str(Path(tmp) / "isolated.db")},
            )
            temporary_context.__exit__.return_value = False
            with (
                mock.patch.dict(
                    os.environ,
                    {
                        "MCP_HOST_BINARY": str(binary),
                        mcp_stdio_smoke.DESTRUCTIVE_RESET_ENV: "0",
                    },
                    clear=False,
                ),
                mock.patch.object(
                    mcp_stdio_smoke, "is_sandboxed_binary", return_value=False
                ),
                mock.patch.object(
                    mcp_stdio_smoke,
                    "db_isolation",
                    return_value=temporary_context,
                ) as temporary_isolation,
                mock.patch.object(
                    mcp_stdio_smoke, "real_app_group_smoke_isolation"
                ) as real_isolation,
                mock.patch.object(
                    mcp_stdio_smoke, "run_smoke", return_value=0
                ) as run_smoke,
            ):
                self.assertEqual(
                    mcp_stdio_smoke.main(["--reset-real-app-group"]), 0
                )

            temporary_isolation.assert_called_once()
            real_isolation.assert_not_called()
            run_smoke.assert_called_once()

    def test_sandboxed_reset_runs_before_and_after_without_restore(self) -> None:
        with tempfile.TemporaryDirectory() as home:
            expected_db = (
                Path(home)
                / "Library"
                / "Group Containers"
                / "group.com.lorvex.apple"
                / "Lorvex"
                / "db.sqlite"
            )
            with (
                mock.patch.dict(
                    os.environ,
                    {mcp_stdio_smoke.DESTRUCTIVE_RESET_ENV: "1"},
                    clear=False,
                ),
                mock.patch.object(Path, "home", return_value=Path(home)),
                mock.patch.object(
                    mcp_stdio_smoke,
                    "signed_entitlements",
                    return_value={
                        "com.apple.security.app-sandbox": True,
                        "com.apple.security.application-groups": [
                            "group.com.lorvex.apple"
                        ],
                    },
                ),
                mock.patch.object(
                    mcp_stdio_smoke, "verify_sandboxed_release_binary"
                ) as verify,
                mock.patch.object(mcp_stdio_smoke, "stop_lorvex_processes") as stop,
                mock.patch.object(mcp_stdio_smoke, "require_quiescent_app_group") as quiet,
                mock.patch.object(
                    mcp_stdio_smoke,
                    "reset_real_app_group_state",
                    side_effect=[4, 5],
                ) as reset,
            ):
                with mcp_stdio_smoke.real_app_group_smoke_isolation(
                    Path("/release/LorvexMCPHost"),
                    "group.com.lorvex.apple",
                    ("Lorvex", "LorvexMCPHost", "LorvexFocusWidget"),
                ) as (db_path, environment):
                    self.assertEqual(db_path, expected_db)
                    self.assertEqual(environment, {})

        verify.assert_called_once()
        self.assertEqual(stop.call_count, 2)
        self.assertEqual(quiet.call_count, 2)
        self.assertEqual(reset.call_args_list, [mock.call(expected_db), mock.call(expected_db)])

    def test_real_reset_erases_all_data_but_preserves_lock_inodes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / "Lorvex"
            directory.mkdir()
            db = directory / "db.sqlite"
            marker = Path(str(db) + ".storage-generation")
            marker.write_text('{"generation":7,"updatedAt":"old"}', encoding="utf-8")
            for suffix in ("", "-wal", "-shm", ".install-identity"):
                Path(str(db) + suffix).write_text("private", encoding="utf-8")
            (directory / "widget_snapshot_v3.json").write_text(
                "private", encoding="utf-8"
            )
            nested = directory / "future-private-sidecar"
            nested.mkdir()
            (nested / "payload").write_text("private", encoding="utf-8")
            storage_lock = Path(str(db) + ".storage-lock")
            install_lock = Path(str(db) + ".install-identity-lock")
            install_lock.write_text("", encoding="utf-8")

            generation = mcp_stdio_smoke.reset_real_app_group_state(db)

            self.assertEqual(generation, 8)
            self.assertEqual(json.loads(marker.read_text())["generation"], 8)
            self.assertTrue(storage_lock.exists())
            self.assertTrue(install_lock.exists())
            self.assertEqual(
                {path.name for path in directory.iterdir()},
                {
                    marker.name,
                    storage_lock.name,
                    install_lock.name,
                },
            )

    def test_corrupt_generation_fails_closed_before_erasing_data(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / "Lorvex"
            directory.mkdir()
            db = directory / "db.sqlite"
            db.write_text("private", encoding="utf-8")
            Path(str(db) + ".storage-generation").write_text(
                "not-json", encoding="utf-8"
            )

            with self.assertRaisesRegex(
                mcp_stdio_smoke.McpSmokeFailure, "present but unreadable"
            ):
                mcp_stdio_smoke.reset_real_app_group_state(db)

            self.assertEqual(db.read_text(encoding="utf-8"), "private")

    def test_source_contains_no_move_copy_backup_or_restore_operation(self) -> None:
        source_path = Path(mcp_stdio_smoke.__file__)
        tree = ast.parse(source_path.read_text(encoding="utf-8"))
        forbidden_calls: list[str] = []
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
                continue
            if (
                isinstance(node.func.value, ast.Name)
                and node.func.value.id == "shutil"
                and node.func.attr in {"move", "copy", "copy2", "copytree"}
            ):
                forbidden_calls.append(node.func.attr)
        self.assertEqual(forbidden_calls, [])

    def test_packaging_paths_select_the_explicit_destructive_mode(self) -> None:
        script_dir = Path(mcp_stdio_smoke.__file__).parent
        for name in ("package_local.sh", "package_dmg.sh", "archive_local.sh"):
            source = (script_dir / name).read_text(encoding="utf-8")
            self.assertIn("mcp_stdio_smoke.py", source)
            self.assertIn("--reset-real-app-group", source)

        verify_all = (script_dir / "verify_all.sh").read_text(encoding="utf-8")
        self.assertNotIn(
            f"{mcp_stdio_smoke.DESTRUCTIVE_RESET_ENV}=1",
            verify_all,
            "the default full gate must never manufacture destructive consent",
        )


if __name__ == "__main__":
    unittest.main()
