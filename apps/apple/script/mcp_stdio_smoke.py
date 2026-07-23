#!/usr/bin/env python3
"""Smoke-test the pure-Swift LorvexMCPHost over real MCP stdio JSON-RPC.

Drives the `LorvexMCPHost` binary backed by `SwiftLorvexCoreService` against a
fresh on-disk database. No Rust dylib, no `dev.seed_*` bridge fixtures: the host
opens an empty DB, applies `schema/schema.sql`, and the script exercises a
minimal create/list round-trip end to end.

Isolation depends on the binary's signed sandbox entitlement. An unsandboxed
dev binary honors `LORVEX_APPLE_DB_PATH` and runs against a disposable temp
directory. A sandboxed distributable ignores that override and must exercise
its real production App Group. That destructive release check is available
only with both `--reset-real-app-group` and
`LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1`: the harness stops Lorvex
processes, proves the container has no open handles, resets the store in place
under its production cutover lock, runs the round-trip, and resets it again.
It never moves, backs up, or restores the App Group directory.

Flow:
  build LorvexMCPHost -> resolve bin path -> isolate the store -> launch ->
  initialize -> notifications/initialized -> tools/list (assert > 0 tools) ->
  create_task (assert the ⟦user⟧ fence on the echoed title) ->
  list_tasks (assert the created task is present AND the full 7-key pagination
  envelope) -> get_task with a missing id (assert the {code, message, tool}
  error envelope with isError) -> create_habit and create_list (assert each
  returns its rich created object, not a bare {success:true}) ->
  assert the on-disk DB file exists.

Coverage rationale: the surface is 118 tools, far too many to exercise here;
`verify_mcp_tool_manifest.py` locks every tool's input-schema shape statically,
so this smoke instead proves the *runtime* contracts that static lock can't —
the security fence, the canonical pagination envelope, the error envelope, and
rich (full-object) write returns across the task/habit/list domains.

Exits non-zero on any failure with a clear `FAIL:` line; prints `PASS` lines for
each checked step and a final success summary.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import plistlib
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterator

from metadata_env import load_metadata


ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parents[1]
SCHEMA_PATH = REPO_ROOT / "schema" / "schema.sql"
PROTOCOL_VERSION = "2025-11-25"
DESTRUCTIVE_RESET_ENV = "LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET"


class McpSmokeFailure(RuntimeError):
    pass


def signed_entitlements(bin_path: Path) -> dict[str, Any]:
    """Return the binary's signed entitlements, failing closed on bad output.

    This mirrors `AppSandboxEnvironment.swift`'s authoritative signal: the
    kernel enforces App Sandbox from the signed entitlement, and a sandboxed
    helper ignores the development database override.
    """
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", "--xml", str(bin_path)],
        capture_output=True,
    )
    if result.returncode != 0:
        # A genuinely unsigned binary is an ordinary unsandboxed development
        # binary. A signed binary whose entitlement blob cannot be inspected is
        # not safe to classify as unsandboxed, because that would make the
        # smoke trust an ignored temp-path override and touch production data.
        verification = subprocess.run(
            ["codesign", "--verify", "--strict", str(bin_path)],
            capture_output=True,
        )
        if verification.returncode != 0:
            return {}
        raise McpSmokeFailure(
            f"cannot inspect signed entitlements for {bin_path}; refusing to launch"
        )
    if not result.stdout:
        # A valid ad-hoc/local-identity signature without any entitlements has
        # no entitlement blob at all. That is an ordinary unsandboxed helper:
        # the kernel cannot enforce App Sandbox when the entitlement is absent,
        # so the development path override remains effective. Still verify the
        # signature before classifying it; malformed signed artifacts continue
        # to fail closed instead of being launched against an ignored override.
        verification = subprocess.run(
            ["codesign", "--verify", "--strict", str(bin_path)],
            capture_output=True,
        )
        if verification.returncode != 0:
            raise McpSmokeFailure(
                f"codesign returned an empty entitlement blob for {bin_path}, "
                "and signature verification failed; refusing to launch"
            )
        return {}
    try:
        entitlements = plistlib.loads(result.stdout)
    except Exception as error:
        raise McpSmokeFailure(
            f"cannot parse signed entitlements for {bin_path}: {error}"
        ) from error
    if not isinstance(entitlements, dict):
        raise McpSmokeFailure(
            f"signed entitlements for {bin_path} are not a property-list dictionary"
        )
    return entitlements


def is_sandboxed_binary(bin_path: Path) -> bool:
    """Whether the kernel-enforced signed entitlement enables App Sandbox."""
    entitlements = signed_entitlements(bin_path)
    return bool(entitlements.get("com.apple.security.app-sandbox"))


def verify_sandboxed_release_binary(
    bin_path: Path, app_group_id: str, entitlements: dict[str, Any]
) -> None:
    """Statically prove the signed helper has the production storage grants."""
    require(
        entitlements.get("com.apple.security.app-sandbox") is True,
        "release MCP helper is not sandboxed",
    )
    app_groups = entitlements.get("com.apple.security.application-groups", [])
    require(
        isinstance(app_groups, list) and app_group_id in app_groups,
        f"release MCP helper is missing App Group {app_group_id!r}: {app_groups!r}",
    )
    result = subprocess.run(
        ["codesign", "--verify", "--strict", "--verbose=2", str(bin_path)],
        capture_output=True,
        text=True,
    )
    require(
        result.returncode == 0,
        f"release MCP helper signature verification failed: {result.stderr.strip()}",
    )


def process_ids(process_name: str) -> list[int]:
    result = subprocess.run(
        ["pgrep", "-x", process_name],
        capture_output=True,
        text=True,
    )
    require(
        result.returncode in (0, 1),
        f"cannot inspect running {process_name} processes: {result.stderr.strip()}",
    )
    if result.returncode == 1:
        return []
    try:
        return [int(line) for line in result.stdout.splitlines() if line.strip()]
    except ValueError as error:
        raise McpSmokeFailure(
            f"pgrep returned an invalid PID for {process_name}: {result.stdout!r}"
        ) from error


def stop_lorvex_processes(process_names: tuple[str, ...]) -> None:
    """Terminate known Lorvex processes and prove they have exited."""
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
    raise McpSmokeFailure(
        f"Lorvex process(es) did not stop before App Group reset: {remaining}"
    )


def open_app_group_handles(container: Path) -> list[str]:
    if not container.exists():
        return []
    result = subprocess.run(
        ["/usr/sbin/lsof", "-n", "-P", "+D", str(container)],
        capture_output=True,
        text=True,
    )
    # lsof returns 1 when it found no matching open files.
    require(
        result.returncode in (0, 1),
        f"cannot inspect App Group open handles: {result.stderr.strip()}",
    )
    require(
        not result.stderr.strip(),
        f"lsof could not prove App Group quiescence: {result.stderr.strip()}",
    )
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    if lines and lines[0].startswith("COMMAND"):
        lines = lines[1:]
    return lines


def require_quiescent_app_group(container: Path) -> None:
    handles = open_app_group_handles(container)
    require(
        not handles,
        "App Group still has open file handles after stopping Lorvex processes:\n"
        + "\n".join(handles),
    )


@contextlib.contextmanager
def exclusive_storage_lock(db_path: Path, timeout: float = 20) -> Iterator[None]:
    """Mirror the production `<db>.storage-lock` exclusive cutover protocol."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = Path(str(db_path) + ".storage-lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o644)
    try:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise McpSmokeFailure(
                        f"storage cutover lock is held by another process: {lock_path}"
                    )
                time.sleep(0.05)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def read_storage_generation(marker_path: Path) -> int:
    if not marker_path.exists():
        return 0
    try:
        payload = json.loads(marker_path.read_text(encoding="utf-8"))
        generation = payload["generation"]
    except Exception as error:
        raise McpSmokeFailure(
            f"storage generation marker is present but unreadable: {marker_path}"
        ) from error
    require(
        isinstance(generation, int) and not isinstance(generation, bool) and generation > 0,
        f"storage generation marker is invalid: {marker_path}",
    )
    return generation


def write_storage_generation(marker_path: Path, generation: int) -> None:
    payload = {
        "generation": generation,
        "updatedAt": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    temporary = marker_path.with_name(
        f".{marker_path.name}.tmp-{os.getpid()}-{time.monotonic_ns()}"
    )
    data = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    try:
        with temporary.open("xb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, marker_path)
        directory_fd = os.open(marker_path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        temporary.unlink(missing_ok=True)


def reset_real_app_group_state(db_path: Path) -> int:
    """Irreversibly erase managed state using the production generation lock."""
    marker_path = Path(str(db_path) + ".storage-generation")
    storage_lock_path = Path(str(db_path) + ".storage-lock")
    with exclusive_storage_lock(db_path):
        next_generation = read_storage_generation(marker_path) + 1
        # The generation bump is durable before any data disappears, matching
        # ManagedStorageGeneration.resetDatabase's fail-closed ordering.
        write_storage_generation(marker_path, next_generation)

        # Match the production reset's critical ordering: remove WAL/SHM before
        # the main database, so a sidecar deletion failure cannot leave a stale
        # WAL ready to replay after the old database has already disappeared.
        for path in (Path(str(db_path) + "-wal"), Path(str(db_path) + "-shm")):
            path.unlink(missing_ok=True)
        db_path.unlink(missing_ok=True)

        for child in db_path.parent.iterdir():
            if child in (marker_path, storage_lock_path):
                continue
            # Lock files carry no user data, and deleting a lock pathname can
            # split mutual exclusion if an unexpected holder appears.
            if child.name.endswith(".lock") or child.name.endswith("-lock"):
                continue
            if child.is_dir() and not child.is_symlink():
                shutil.rmtree(child)
            else:
                child.unlink(missing_ok=True)
        directory_fd = os.open(db_path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        return next_generation


@contextlib.contextmanager
def db_isolation(bin_path: Path, app_group_id: str, schema_path: Path) -> Iterator[
    tuple[Path, dict[str, str]]
]:
    """Yield a disposable database for one unsandboxed development smoke.

    An unsandboxed dev binary (`package_local.sh`, plain `swift build`) honors
    the `LORVEX_APPLE_DB_PATH`/`LORVEX_APPLE_SCHEMA_PATH` dev overrides, so a
    disposable temp directory is enough isolation.

    A sandboxed binary is handled by `real_app_group_smoke_isolation`, which
    requires an explicit destructive opt-in. This default helper therefore has
    no code path that can touch the real App Group.
    """
    del bin_path, app_group_id
    with tempfile.TemporaryDirectory(prefix="lorvex-mcp-smoke-") as tmp:
        db_path = Path(tmp) / "lorvex.db"
        yield db_path, {
            "LORVEX_APPLE_DB_PATH": str(db_path),
            "LORVEX_APPLE_SCHEMA_PATH": str(schema_path),
        }


@contextlib.contextmanager
def real_app_group_smoke_isolation(
    bin_path: Path,
    app_group_id: str,
    process_names: tuple[str, ...],
) -> Iterator[tuple[Path, dict[str, str]]]:
    """Reset and exercise the real App Group without backup or restoration."""
    require(
        os.environ.get(DESTRUCTIVE_RESET_ENV) == "1",
        f"sandboxed MCP smoke irreversibly erases local Lorvex data; set "
        f"{DESTRUCTIVE_RESET_ENV}=1 together with --reset-real-app-group",
    )
    require(
        app_group_id.startswith("group.")
        and "/" not in app_group_id
        and "\\" not in app_group_id
        and app_group_id not in ("group.", ".", ".."),
        f"refusing destructive reset for invalid App Group identifier: {app_group_id!r}",
    )
    entitlements = signed_entitlements(bin_path)
    verify_sandboxed_release_binary(bin_path, app_group_id, entitlements)
    container = Path.home() / "Library" / "Group Containers" / app_group_id / "Lorvex"
    stop_lorvex_processes(process_names)
    require_quiescent_app_group(container)
    before_generation = reset_real_app_group_state(container / "db.sqlite")
    print(
        "PASS: irreversibly reset the real Lorvex App Group "
        f"(generation {before_generation})"
    )
    try:
        yield container / "db.sqlite", {}
    finally:
        stop_lorvex_processes(process_names)
        require_quiescent_app_group(container)
        after_generation = reset_real_app_group_state(container / "db.sqlite")
        print(
            "PASS: removed MCP smoke data from the real Lorvex App Group "
            f"(generation {after_generation}); prior data was not restored"
        )


def run(command: list[str]) -> str:
    result = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def send(process: subprocess.Popen[str], message: dict[str, Any]) -> None:
    assert process.stdin is not None
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def read_response(
    process: subprocess.Popen[str], request_id: int, timeout: float = 10.0
) -> dict[str, Any]:
    assert process.stdout is not None
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 0.1)
        if not ready:
            continue
        line = process.stdout.readline()
        if not line:
            break
        payload = json.loads(line)
        if payload.get("id") == request_id:
            if "error" in payload:
                raise McpSmokeFailure(
                    f"request {request_id} returned error: {payload['error']}"
                )
            return payload
    raise McpSmokeFailure(f"timed out waiting for response id {request_id}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise McpSmokeFailure(message)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reset-real-app-group",
        action="store_true",
        help=(
            "for a sandboxed release helper, stop Lorvex processes and irreversibly "
            "erase the real App Group before and after the smoke; also requires "
            f"{DESTRUCTIVE_RESET_ENV}=1"
        ),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    metadata = load_metadata()
    mcp_host_product = metadata.get("MCP_HOST_PRODUCT", "LorvexMCPHost")
    marketing_version = metadata.get("MARKETING_VERSION", "1.0.0")

    require(SCHEMA_PATH.exists(), f"missing schema at {SCHEMA_PATH}")

    mcp_host_binary = os.environ.get("MCP_HOST_BINARY")
    if mcp_host_binary:
        bin_path = Path(mcp_host_binary)
    else:
        run(["swift", "build", "--product", mcp_host_product])
        bin_path = Path(run(["swift", "build", "--show-bin-path"])) / mcp_host_product
    require(bin_path.exists(), f"missing MCP host binary at {bin_path}")
    print(f"PASS: built MCP host binary at {bin_path}")

    app_group_id = metadata.get("APP_GROUP_ID", "group.com.lorvex.apple")
    sandboxed = is_sandboxed_binary(bin_path)
    if sandboxed:
        require(
            args.reset_real_app_group,
            "refusing to launch a sandboxed MCP helper against real local data; "
            "release verification must pass --reset-real-app-group and explicitly "
            f"set {DESTRUCTIVE_RESET_ENV}=1",
        )
        isolation = real_app_group_smoke_isolation(
            bin_path,
            app_group_id,
            (
                metadata.get("APP_NAME", "Lorvex"),
                mcp_host_product,
                metadata.get("WIDGET_EXECUTABLE", "LorvexFocusWidget"),
            ),
        )
    else:
        isolation = db_isolation(bin_path, app_group_id, SCHEMA_PATH)
    with isolation as (db_path, env_overrides):
        return run_smoke(bin_path, marketing_version, db_path, env_overrides)


def run_smoke(
    bin_path: Path,
    marketing_version: str,
    db_path: Path,
    env_overrides: dict[str, str],
) -> int:
    process = subprocess.Popen(
        [str(bin_path)],
        cwd=ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={
            **os.environ,
            "NSUnbufferedIO": "YES",
            **env_overrides,
        },
    )

    try:
        send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {},
                    "clientInfo": {
                        "name": "lorvex-smoke",
                        "version": marketing_version,
                    },
                },
            },
        )
        initialize = read_response(process, 1)
        require(
            initialize["result"]["capabilities"].get("tools") is not None,
            "initialize did not advertise tools capability",
        )
        print("PASS: initialize advertised tools capability")

        send(
            process,
            {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
        )

        send(process, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools_response = read_response(process, 2)
        tools = tools_response["result"]["tools"]
        require(len(tools) > 0, "tools/list returned no tools")
        # The Swift host advertises the full catalog; accept >0 so the
        # smoke stays robust if the catalog grows, while logging the exact count.
        print(f"PASS: tools/list returned {len(tools)} tools")

        send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 9,
                "method": "tools/call",
                "params": {"name": "list_tasks", "arguments": {}},
            },
        )
        initially_listed = read_response(process, 9)
        initial_tasks = initially_listed["result"]["structuredContent"]["tasks"]
        require(
            initial_tasks == [],
            "smoke database was not empty before the first mutation; refusing to "
            "exercise a non-reset store",
        )
        print("PASS: smoke database starts with no tasks")

        created_title = "Smoke-test Swift MCP host"
        fenced_created_title = f"⟦user⟧{created_title}⟦/user⟧"
        send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {
                    "name": "create_task",
                    "arguments": {
                        "title": created_title,
                        "notes": "Created by script/mcp_stdio_smoke.py",
                    },
                },
            },
        )
        created = read_response(process, 3)
        created_content = created["result"]["structuredContent"]
        require(
            created_content["title"] == fenced_created_title,
            f"create_task returned wrong title: {created_content.get('title')!r}",
        )
        created_id = created_content["id"]
        print(f"PASS: create_task created task {created_id}")

        send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {"name": "list_tasks", "arguments": {}},
            },
        )
        listed = read_response(process, 4)
        listed_content = listed["result"]["structuredContent"]
        listed_ids = [task["id"] for task in listed_content["tasks"]]
        require(
            created_id in listed_ids,
            "list_tasks did not return the created task",
        )
        print("PASS: list_tasks returned the created task")

        # The canonical pagination envelope (MCPPaginationEnvelope.swift) must
        # ride alongside the domain `tasks` array on every paginated read, with
        # all seven keys present so AI clients page with one vocabulary.
        pagination_keys = {
            "total_matching",
            "returned",
            "limit",
            "offset",
            "next_offset",
            "next_cursor",
            "truncated",
        }
        missing_pagination = sorted(pagination_keys - listed_content.keys())
        require(
            not missing_pagination,
            f"list_tasks is missing pagination envelope key(s): {missing_pagination}",
        )
        require(
            listed_content["returned"] == len(listed_content["tasks"]),
            "list_tasks 'returned' count does not match the tasks page length",
        )
        print(f"PASS: list_tasks carries the {len(pagination_keys)}-key pagination envelope")

        # Error path: a handler-level failure must surface as the structured
        # {code, message, tool} error envelope with isError, not a JSON-RPC error
        # and not a silent empty result. get_task without an id is a deterministic
        # validation failure that never touches the store.
        send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 6,
                "method": "tools/call",
                "params": {"name": "get_task", "arguments": {}},
            },
        )
        errored = read_response(process, 6)
        error_result = errored["result"]
        require(
            error_result.get("isError") is True,
            "get_task with no id did not set isError on the result",
        )
        error_envelope = error_result["structuredContent"]
        missing_error_keys = sorted({"code", "message", "tool"} - error_envelope.keys())
        require(
            not missing_error_keys,
            f"error envelope is missing key(s): {missing_error_keys}",
        )
        require(
            error_envelope["tool"] == "get_task",
            f"error envelope names the wrong tool: {error_envelope.get('tool')!r}",
        )
        print(f"PASS: get_task invalid-arg returned the {{code, message, tool}} error envelope "
              f"(code={error_envelope['code']!r})")

        # Rich returns: writes across domains must return the full created object,
        # never a bare {success: true}. create_task above already proved the task
        # domain; spot-check the habit and list domains too.
        for tool_name, arguments, label in (
            ("create_habit", {"name": "Smoke-test habit"}, "habit"),
            ("create_list", {"name": "Smoke-test list"}, "list"),
        ):
            send(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": 7 if tool_name == "create_habit" else 8,
                    "method": "tools/call",
                    "params": {"name": tool_name, "arguments": arguments},
                },
            )
            written = read_response(process, 7 if tool_name == "create_habit" else 8)
            written_content = written["result"]["structuredContent"]
            require(
                isinstance(written_content, dict) and written_content.get("id"),
                f"{tool_name} did not return a rich object with an id: {written_content!r}",
            )
            require(
                "name" in written_content and written_content != {"success": True},
                f"{tool_name} returned a thin/success-only payload: {written_content!r}",
            )
            print(f"PASS: {tool_name} returned a rich {label} object (id={written_content['id']})")

        require(db_path.exists(), f"on-disk db was not created at {db_path}")
        print(f"PASS: on-disk db exists at {db_path}")

        print("MCP stdio smoke passed (swift core)")
        return 0
    finally:
        process.terminate()
        stderr_tail = ""
        try:
            _, stderr_tail = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            _, stderr_tail = process.communicate(timeout=2)
        if stderr_tail and process.returncode not in (0, None, -15):
            print(stderr_tail, file=sys.stderr)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"FAIL: MCP stdio smoke failed: {error}", file=sys.stderr)
        raise SystemExit(1)
