#!/usr/bin/env python3
"""Install-time runtime proof for the exact app copied from the production DMG."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path


LSREGISTER = Path(
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
    "LaunchServices.framework/Support/lsregister"
)
PLUGINKIT = Path("/usr/bin/pluginkit")
OPEN = Path("/usr/bin/open")
LSOF = Path("/usr/sbin/lsof")


class RuntimeProbeFailure(RuntimeError):
    pass


def bundle_tree_digest(root: Path) -> str:
    """Digest relative names, file bytes, modes, and symlink targets."""
    if not root.is_dir():
        raise RuntimeProbeFailure(f"app bundle is missing: {root}")
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        status = path.lstat()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update((status.st_mode & 0o7777).to_bytes(4, "big"))
        if path.is_symlink():
            target = os.readlink(path).encode("utf-8")
            digest.update(b"L")
            digest.update(len(target).to_bytes(8, "big"))
            digest.update(target)
        elif path.is_dir():
            digest.update(b"D")
        elif path.is_file():
            digest.update(b"F")
            digest.update(status.st_size.to_bytes(8, "big"))
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            raise RuntimeProbeFailure(f"unsupported filesystem entry in app bundle: {path}")
    return digest.hexdigest()


def matching_plugin_path(
    output: str, identifier: str, expected_path: Path
) -> Path | None:
    expected = os.path.normpath(str(expected_path.absolute()))
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) < 2 or not fields[0].strip(" +-").startswith(f"{identifier}("):
            continue
        candidate = os.path.normpath(fields[-1].strip())
        if candidate == expected:
            return Path(candidate)
    return None


def classify_procinfo_result(
    returncode: int, stdout: str, stderr: str
) -> tuple[bool, bool]:
    combined = f"{stdout}\n{stderr}".strip()
    if returncode == 0:
        if "entitlements validated" not in combined.lower():
            raise RuntimeProbeFailure(
                "launchctl procinfo succeeded but did not validate entitlements"
            )
        return True, True
    lowered = combined.lower()
    if "requires root privileges" in lowered or "not supported" in lowered:
        return False, False
    raise RuntimeProbeFailure(f"launchctl procinfo failed: {combined or returncode}")


def atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def process_ids(process_name: str) -> list[int]:
    result = subprocess.run(
        ["pgrep", "-x", process_name], capture_output=True, text=True, check=False
    )
    if result.returncode not in (0, 1):
        raise RuntimeProbeFailure(
            f"cannot inspect running {process_name} processes: {result.stderr.strip()}"
        )
    if result.returncode == 1:
        return []
    try:
        return [int(line) for line in result.stdout.splitlines() if line.strip()]
    except ValueError as error:
        raise RuntimeProbeFailure(
            f"pgrep returned an invalid PID for {process_name}: {result.stdout!r}"
        ) from error


def stop_processes(process_names: list[str]) -> None:
    pids = sorted({pid for name in process_names for pid in process_ids(name)})
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        remaining = sorted(
            {pid for name in process_names for pid in process_ids(name)}
        )
        if not remaining:
            return
        time.sleep(0.1)
    remaining = sorted({pid for name in process_names for pid in process_ids(name)})
    for pid in remaining:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        remaining = sorted(
            {pid for name in process_names for pid in process_ids(name)}
        )
        if not remaining:
            return
        time.sleep(0.05)
    raise RuntimeProbeFailure(
        f"Lorvex process(es) did not stop before production install: {remaining}"
    )


def executable_text_paths(pid: int) -> list[Path]:
    result = subprocess.run(
        [str(LSOF), "-a", "-p", str(pid), "-d", "txt", "-Fn"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    return [Path(line[1:]) for line in result.stdout.splitlines() if line.startswith("n/")]


def wait_for_exact_launch(
    process_name: str, expected_executable: Path, timeout: float = 15
) -> int:
    expected = expected_executable.resolve(strict=True)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for pid in process_ids(process_name):
            if any(
                candidate.resolve(strict=False) == expected
                for candidate in executable_text_paths(pid)
            ):
                return pid
        time.sleep(0.1)
    raise RuntimeProbeFailure(
        f"the exact installed executable did not launch within {timeout:g}s: {expected}"
    )


def terminate_pid(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def production_launch_command(installed_app: Path) -> list[str]:
    """Launch the installed candidate without restoring prior app state."""
    return [str(OPEN), "-F", "-n", str(installed_app)]


def parse_utc_instant(value: object, label: str) -> datetime:
    if not isinstance(value, str):
        raise RuntimeProbeFailure(f"{label} is missing or not a timestamp")
    try:
        instant = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise RuntimeProbeFailure(f"{label} is not a valid timestamp") from error
    if instant.tzinfo is None:
        raise RuntimeProbeFailure(f"{label} has no timezone")
    return instant


def clean_widget_snapshot_failure(
    payload: object, minimum_generation: int, reset_at: datetime
) -> str | None:
    if not isinstance(payload, dict):
        return "widget snapshot is not a JSON object"
    generation = payload.get("storage_generation")
    if not isinstance(generation, int) or isinstance(generation, bool):
        return "widget snapshot has no integer storage generation"
    if generation != minimum_generation:
        return "widget snapshot does not match the final destructive-reset generation"
    try:
        generated_at = parse_utc_instant(
            payload.get("generated_at"), "widget snapshot generated_at"
        )
    except RuntimeProbeFailure as error:
        return str(error)
    if generated_at < reset_at:
        return "widget snapshot was generated before the final destructive reset"
    for key in ("focus_tasks", "habits", "today_tasks"):
        if payload.get(key) != []:
            return f"clean widget snapshot still contains {key} rows"
    if "Smoke-test" in json.dumps(payload, sort_keys=True):
        return "clean widget snapshot still contains MCP smoke data"
    return None


def mcp_smoke_row_counts(database_path: Path) -> dict[str, int]:
    """Read the production DB read-only and prove the known smoke rows are absent."""
    try:
        database_uri = database_path.resolve(strict=True).as_uri() + "?mode=ro"
        connection = sqlite3.connect(database_uri, uri=True, timeout=5)
        try:
            queries = {
                "tasks": ("tasks", "title", "Smoke-test Swift MCP host"),
                "habits": ("habits", "name", "Smoke-test habit"),
                "lists": ("lists", "name", "Smoke-test list"),
            }
            return {
                label: int(
                    connection.execute(
                        f'SELECT COUNT(*) FROM "{table}" WHERE "{column}" = ?',
                        (value,),
                    ).fetchone()[0]
                )
                for label, (table, column, value) in queries.items()
            }
        finally:
            connection.close()
    except (OSError, sqlite3.Error, TypeError) as error:
        raise RuntimeProbeFailure(
            f"cannot verify MCP smoke-row absence in {database_path}"
        ) from error


def wait_for_clean_derived_state(
    reset_evidence_path: Path,
    evidence_dir: Path,
    timeout: float = 20,
) -> None:
    try:
        reset = json.loads(reset_evidence_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeProbeFailure(
            f"cannot read final reset evidence: {reset_evidence_path}"
        ) from error
    generation = reset.get("generation")
    if (
        not isinstance(generation, int)
        or isinstance(generation, bool)
        or generation <= 0
        or reset.get("databaseAbsentAfterReset") is not True
    ):
        raise RuntimeProbeFailure("final reset evidence has no completed generation")
    reset_at = parse_utc_instant(reset.get("resetAt"), "final reset resetAt")
    database_path = reset.get("databasePath")
    if not isinstance(database_path, str):
        raise RuntimeProbeFailure("final reset evidence has no database path")
    snapshot_path = Path(database_path).parent / "widget_snapshot_v3.json"

    deadline = time.monotonic() + timeout
    last_failure = "widget snapshot has not been published"
    snapshot: dict[str, object] | None = None
    while time.monotonic() < deadline:
        try:
            candidate = json.loads(snapshot_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            time.sleep(0.1)
            continue
        last_failure = clean_widget_snapshot_failure(candidate, generation, reset_at) or ""
        if not last_failure:
            snapshot = candidate
            break
        time.sleep(0.1)
    if snapshot is None:
        raise RuntimeProbeFailure(
            f"final clean-state derived surfaces did not reconcile: {last_failure}"
        )
    smoke_row_counts = mcp_smoke_row_counts(Path(database_path))
    if any(smoke_row_counts.values()):
        raise RuntimeProbeFailure(
            f"final production database still contains MCP smoke rows: {smoke_row_counts}"
        )

    atomic_text(
        evidence_dir / "installed-app-clean-derived-state.json",
        json.dumps(
            {
                "finalResetEvidence": str(reset_evidence_path),
                "databaseSmokeRowCounts": smoke_row_counts,
                "minimumStorageGeneration": generation,
                "snapshotGeneratedAt": snapshot["generated_at"],
                "snapshotPath": str(snapshot_path),
                "snapshotStorageGeneration": snapshot["storage_generation"],
                "smokeRowsPresent": False,
                "verifiedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
    )


def run_probe(args: argparse.Namespace) -> None:
    assert args.mounted_app is not None
    assert args.installed_app is not None
    assert args.evidence_dir is not None
    mounted_app: Path = args.mounted_app
    installed_app: Path = args.installed_app
    evidence_dir: Path = args.evidence_dir
    expected_executable = installed_app / "Contents" / "MacOS" / args.app_name
    expected_widget = installed_app / "Contents" / "PlugIns" / args.widget_appex_name
    if not expected_executable.is_file() or not os.access(expected_executable, os.X_OK):
        raise RuntimeProbeFailure(
            f"installed app executable is missing or not executable: {expected_executable}"
        )
    if not expected_widget.is_dir():
        raise RuntimeProbeFailure(f"installed widget is missing: {expected_widget}")

    mounted_digest = bundle_tree_digest(mounted_app)
    installed_digest = bundle_tree_digest(installed_app)
    if mounted_digest != installed_digest:
        raise RuntimeProbeFailure(
            "installed app content does not match the app mounted from the final DMG"
        )
    atomic_text(
        evidence_dir / "installed-app-content-identity.json",
        json.dumps(
            {
                "algorithm": "sha256-tree-v1",
                "installedApp": str(installed_app),
                "installedDigest": installed_digest,
                "mountedApp": str(mounted_app),
                "mountedDigest": mounted_digest,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
    )

    registration = subprocess.run(
        [str(LSREGISTER), "-f", str(installed_app)],
        capture_output=True,
        text=True,
        check=False,
    )
    atomic_text(
        evidence_dir / "installed-app-launchservices.txt",
        f"command: {LSREGISTER} -f {installed_app}\n"
        f"returnCode: {registration.returncode}\n"
        f"stdout:\n{registration.stdout}\nstderr:\n{registration.stderr}",
    )
    if registration.returncode != 0:
        raise RuntimeProbeFailure(
            "LaunchServices registration failed: "
            + (registration.stderr.strip() or str(registration.returncode))
        )

    launch_command = production_launch_command(installed_app)
    launch = subprocess.run(
        launch_command,
        capture_output=True,
        text=True,
        check=False,
    )
    if launch.returncode != 0:
        raise RuntimeProbeFailure(
            "installed app launch command failed: "
            + (launch.stderr.strip() or str(launch.returncode))
        )

    pid: int | None = None
    try:
        pid = wait_for_exact_launch(args.app_name, expected_executable)
        time.sleep(args.stability_seconds)
        try:
            os.kill(pid, 0)
        except ProcessLookupError as error:
            raise RuntimeProbeFailure(
                "installed app exited during the cold-launch stability window"
            ) from error

        resolved_paths = [
            path.resolve(strict=False) for path in executable_text_paths(pid)
        ]
        expected_resolved = expected_executable.resolve(strict=True)
        atomic_text(
            evidence_dir / "installed-app-process-paths.txt",
            f"pid: {pid}\nexpectedExecutable: {expected_resolved}\n"
            + "mappedTextPaths:\n"
            + "".join(f"  {path}\n" for path in resolved_paths),
        )
        if expected_resolved not in resolved_paths:
            raise RuntimeProbeFailure(
                f"launched PID {pid} no longer maps the installed executable"
            )

        procinfo = subprocess.run(
            ["launchctl", "procinfo", str(pid)],
            capture_output=True,
            text=True,
            check=False,
        )
        atomic_text(
            evidence_dir / "installed-app-runtime-procinfo.txt",
            f"command: launchctl procinfo {pid}\n"
            f"returnCode: {procinfo.returncode}\n"
            f"stdout:\n{procinfo.stdout}\nstderr:\n{procinfo.stderr}",
        )
        procinfo_supported, entitlements_validated = classify_procinfo_result(
            procinfo.returncode, procinfo.stdout, procinfo.stderr
        )

        plugin_output = ""
        plugin_path: Path | None = None
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            plugin = subprocess.run(
                [
                    str(PLUGINKIT),
                    "-m",
                    "-A",
                    "-D",
                    "-v",
                    "-i",
                    args.widget_bundle_id,
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            plugin_output = plugin.stdout + plugin.stderr
            if plugin.returncode not in (0, 1):
                raise RuntimeProbeFailure(
                    "pluginkit query failed: "
                    + (plugin.stderr.strip() or str(plugin.returncode))
                )
            plugin_path = matching_plugin_path(
                plugin_output, args.widget_bundle_id, expected_widget
            )
            if plugin_path is not None:
                break
            time.sleep(0.2)
        atomic_text(evidence_dir / "installed-widget-pluginkit.txt", plugin_output)
        if plugin_path is None:
            raise RuntimeProbeFailure(
                f"pluginkit did not register the exact installed widget: {expected_widget}"
            )

        if args.clean_reset_evidence is not None:
            wait_for_clean_derived_state(
                args.clean_reset_evidence,
                evidence_dir,
            )

        atomic_text(
            evidence_dir / "installed-app-runtime.json",
            json.dumps(
                {
                    "app": str(installed_app),
                    "coldLaunchStableSeconds": args.stability_seconds,
                    "entitlementsValidated": entitlements_validated,
                    "executable": str(expected_resolved),
                    "launchCommand": launch_command,
                    "pid": pid,
                    "pluginIdentifier": args.widget_bundle_id,
                    "pluginPath": str(plugin_path),
                    "procinfoSupported": procinfo_supported,
                    "verifiedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
        )
    finally:
        if pid is not None:
            terminate_pid(pid)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiesce-only", action="store_true")
    parser.add_argument("--mounted-app", type=Path)
    parser.add_argument("--installed-app", type=Path)
    parser.add_argument("--evidence-dir", type=Path)
    parser.add_argument("--app-name", default="Lorvex")
    parser.add_argument("--widget-bundle-id", default="com.lorvex.apple.focuswidget")
    parser.add_argument("--widget-appex-name", default="LorvexFocusWidget.appex")
    parser.add_argument("--process-name", action="append", default=[])
    parser.add_argument("--clean-reset-evidence", type=Path)
    parser.add_argument("--stability-seconds", type=float, default=3.0)
    args = parser.parse_args(argv)
    if args.stability_seconds < 0:
        parser.error("--stability-seconds must not be negative")
    if not args.process_name:
        args.process_name = [args.app_name]
    if not args.quiesce_only:
        for name in ("mounted_app", "installed_app", "evidence_dir"):
            if getattr(args, name) is None:
                parser.error(f"--{name.replace('_', '-')} is required")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        stop_processes(args.process_name)
        if not args.quiesce_only:
            run_probe(args)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"production installed-app runtime verification failed: {error}", file=sys.stderr)
        return 1
    if args.quiesce_only:
        print("Production install process quiescence passed")
    else:
        print(f"Production installed-app runtime verification passed: {args.installed_app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
