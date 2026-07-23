#!/usr/bin/env python3
"""Seed a Lorvex database with realistic demo data through the real MCP write path.

Drives the `LorvexMCPHost` binary over stdio JSON-RPC (the same transport the app's
assistant uses), so every row is created through `SwiftLorvexCoreService` with the
proper `ai_changelog` entries — no hand-written SQL, no bypassing of invariants.

Creates a handful of lists, a varied set of tasks (priorities, due dates including
overdue and today, tags, estimates, notes, checklists, completed items), today's
focus selection, and a few habits — enough to exercise and visually verify every
task surface (Today, Tasks, Lists, Habits) with lifelike content.

Usage:
  script/seed_demo_data.py                 # seed Lorvex-managed local storage
  script/seed_demo_data.py --db /path/to/db.sqlite
  script/seed_demo_data.py --fresh         # back up any existing DB and seed an empty one

The MCP `planned_date` argument maps to the model's `dueDate`, so it drives both the
scheduled/Today surfaces and the overdue styling.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]          # apps/apple
REPO_ROOT = ROOT.parents[1]
SCHEMA_PATH = REPO_ROOT / "schema" / "schema.sql"
PROTOCOL_VERSION = "2025-11-25"
DEFAULT_DB = Path.home() / "Library" / "Application Support" / "Lorvex" / "db.sqlite"

# Anchor the demo to the real today so the relative labels the app derives
# ("today", "tomorrow", "2d ago", overdue styling) stay accurate no matter when
# the demo database is seeded, rather than drifting from a hardcoded date.
TODAY = dt.date.today()


def day(offset: int) -> str:
    return (TODAY + dt.timedelta(days=offset)).isoformat()


# --- demo content -----------------------------------------------------------
# Each task: title, notes, priority(1-3), plan(day offset or None), tags, est(min),
#            list (None = Inbox), done(bool), focus(bool), checklist[(text, done)]
# (name, description, hex color, SF Symbol icon)
LISTS = [
    ("Work", "Projects, reviews, and shipping work", "#AF52DE", "briefcase.fill"),
    ("Personal", "Errands, health, and life admin", "#34C759", "house.fill"),
    ("Travel", "Trips, bookings, and logistics", "#30B0C7", "airplane"),
    ("Reading", "Books and articles to finish", "#FF2D92", "book.fill"),
]

TASKS: list[dict[str, Any]] = [
    dict(title="Draft the Q3 planning brief", notes="Pull last quarter's numbers before drafting the narrative.",
         priority=1, plan=-2, tags=["planning", "writing"], est=90, list="Work", focus=True,
         checklist=[("Gather Q2 metrics", True), ("Outline three priorities", True),
                    ("Draft the narrative section", False), ("Circulate for review", False)]),
    dict(title="Review pull requests for the sync engine", notes="Focus on the conflict-resolution path.",
         priority=2, plan=0, tags=["code-review"], est=45, list="Work", focus=True),
    dict(title="Prepare the sprint demo", notes="", priority=2, plan=0, tags=["meeting"], est=30, list="Work"),
    dict(title="Reply to the design feedback thread", notes="", priority=3, plan=0, tags=["design"], list="Work",
         checklist=[("Read all comments", True), ("Reply to Alex", False), ("Resolve resolved threads", False),
                    ("Share updated mocks", False), ("Schedule follow-up", False)]),
    dict(title="Write the incident postmortem", notes="Blameless. Timeline + three action items.",
         priority=1, plan=1, tags=["reliability"], est=60, list="Work"),
    dict(title="Update the onboarding copy", notes="", priority=3, plan=None, tags=["writing"], list="Work"),
    dict(title="Send the weekly status update", notes="", priority=2, plan=0, tags=["comms"], list="Work", done=True),

    dict(title="Book a dentist appointment", notes="Overdue — call before noon.",
         priority=2, plan=-3, tags=["health"], list="Personal"),
    dict(title="Call mom", notes="", priority=2, plan=0, tags=["family"], list="Personal", focus=True),
    dict(title="Plan the weekend hike", notes="Check the trail conditions and pack water.",
         priority=3, plan=5, tags=["outdoors"], list="Personal"),
    dict(title="Renew gym membership", notes="", priority=3, plan=None, list="Personal"),

    dict(title="Book the offsite venue", notes="Need capacity for 24 and A/V.",
         priority=2, plan=1, tags=["offsite"], est=20, list="Travel"),
    dict(title="Confirm the flight to Seattle", notes="", priority=1, plan=3, tags=["flights"], est=15, list="Travel"),
    dict(title="Pack the carry-on", notes="", priority=3, plan=2, list="Travel"),

    dict(title="Finish DDIA — chapter 7", notes="Transactions: weak isolation levels.",
         priority=3, plan=4, tags=["learning"], est=40, list="Reading"),
    dict(title="Read the SwiftUI release notes", notes="", priority=3, plan=None, tags=["learning"],
         list="Reading", done=True),

    dict(title="Try the new espresso recipe", notes="", priority=3, plan=None),
    dict(title="Research a standing desk", notes="Compare three options under $500.", priority=3, plan=6, tags=["home"]),
]

# (name, cue, target_count, hex color, SF Symbol icon)
HABITS = [
    ("Morning meditation", "After waking up, before coffee", 1, "#5E5CE6", "brain.head.profile"),
    ("Drink water", "Throughout the day", 8, "#0A84FF", "drop.fill"),
    ("Read 20 minutes", "Before bed", 1, "#FF9500", "book.fill"),
    ("Walk 8,000 steps", "", 1, "#34C759", "figure.walk"),
]


# --- MCP plumbing -----------------------------------------------------------
class SeedError(RuntimeError):
    pass


def run(command: list[str]) -> str:
    result = subprocess.run(command, cwd=ROOT, check=True, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout.strip()


class Host:
    def __init__(self, proc: subprocess.Popen[str]) -> None:
        self.proc = proc
        self._id = 0

    def _send(self, message: dict[str, Any]) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()

    def _read(self, request_id: int, timeout: float = 20.0) -> dict[str, Any]:
        assert self.proc.stdout is not None
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.proc.stdout], [], [], 0.1)
            if not ready:
                continue
            line = self.proc.stdout.readline()
            if not line:
                break
            payload = json.loads(line)
            if payload.get("id") == request_id:
                if "error" in payload:
                    raise SeedError(f"request {request_id} error: {payload['error']}")
                return payload
        raise SeedError(f"timed out waiting for response id {request_id}")

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        self._id += 1
        rid = self._id
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        return self._read(rid)

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        self._send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def call(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        resp = self.request("tools/call", {"name": name, "arguments": arguments})
        result = resp.get("result", {})
        # The rich object lives in `structuredContent`; the `content` text is a
        # human-readable summary ("Created task: …"), not always JSON.
        if isinstance(result.get("structuredContent"), (dict, list)):
            return result["structuredContent"]
        for item in result.get("content") or []:
            if item.get("type") == "text":
                try:
                    return json.loads(item["text"])
                except json.JSONDecodeError:
                    return {"text": item["text"]}
        return {}


def first_id(obj: Any) -> str:
    """Recursively find the first `id` value in a tool response object."""
    if isinstance(obj, dict):
        for key in ("task", "list", "habit"):
            if key in obj and isinstance(obj[key], dict) and "id" in obj[key]:
                return str(obj[key]["id"])
        if "id" in obj:
            return str(obj["id"])
        for v in obj.values():
            found = first_id(v)
            if found:
                return found
    if isinstance(obj, list):
        for v in obj:
            found = first_id(v)
            if found:
                return found
    return ""


def seed(host: Host) -> None:
    host.request("initialize", {
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "lorvex-seed", "version": "1.0"},
    })
    host.notify("notifications/initialized")

    list_ids: dict[str, str] = {}
    for name, desc, color, icon in LISTS:
        res = host.call("create_list", {"name": name, "description": desc})
        lid = first_id(res)
        list_ids[name] = lid
        host.call("update_list", {"id": lid, "color": color, "icon": icon})
    print(f"PASS: created {len(list_ids)} lists")

    focus_ids: list[str] = []
    for spec in TASKS:
        res = host.call("create_task", {"title": spec["title"], "notes": spec.get("notes", "")})
        tid = first_id(res)
        if not tid:
            raise SeedError(f"no id for task {spec['title']!r}")

        update: dict[str, Any] = {"id": tid, "title": spec["title"], "priority": spec["priority"]}
        if spec.get("plan") is not None:
            update["planned_date"] = day(spec["plan"])
        if spec.get("tags"):
            update["tags_set"] = spec["tags"]
        if spec.get("est") is not None:
            update["estimated_minutes"] = spec["est"]
        host.call("update_task", update)

        if spec.get("list"):
            host.call("move_task_to_list", {"id": tid, "list_id": list_ids[spec["list"]]})
        for text, done in spec.get("checklist", []):
            task = host.call("add_task_checklist_item", {"task_id": tid, "text": text})
            if done:
                item = next((c for c in task.get("checklist_items", []) if c.get("text") == text), None)
                if item and item.get("id"):
                    host.call("toggle_task_checklist_item", {"item_id": item["id"], "completed": True})
        if spec.get("done"):
            host.call("complete_task", {"id": tid})
        if spec.get("focus"):
            focus_ids.append(tid)

    print(f"PASS: created {len(TASKS)} tasks")

    if focus_ids:
        host.call("set_current_focus", {"date": day(0), "task_ids": focus_ids})
        print(f"PASS: set today's focus ({len(focus_ids)} tasks)")

    habit_ids: list[tuple[str, int]] = []
    for name, cue, target, color, icon in HABITS:
        args: dict[str, Any] = {"name": name, "target_count": target}
        if cue:
            args["cue"] = cue
        res = host.call("create_habit", args)
        hid = first_id(res)
        if hid:
            host.call("update_habit", {"id": hid, "color": color, "icon": icon})
            habit_ids.append((hid, target))
    print(f"PASS: created {len(habit_ids)} habits")

    # Backfill ~3 weeks of completion history so the heatmaps and streaks render
    # with real texture instead of empty grids. Deterministic pattern: a weekly
    # rest day (every 6th day back), full target on the last week for a current
    # streak, a lighter count on older days.
    logged = 0
    for hid, target in habit_ids:
        for d in range(1, 22):  # d days ago
            if d % 6 == 0:
                continue
            count = target if d <= 7 else max(1, target - 4)
            for _ in range(count):
                host.call("complete_habit", {"id": hid, "date": day(-d)})
                logged += 1
    print(f"PASS: logged {logged} habit completions across the past 3 weeks")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="database file to seed")
    parser.add_argument("--fresh", action="store_true",
                        help="back up any existing DB and seed a fresh empty one")
    args = parser.parse_args()

    if not SCHEMA_PATH.exists():
        raise SeedError(f"missing schema at {SCHEMA_PATH}")

    db_path: Path = args.db
    db_path.parent.mkdir(parents=True, exist_ok=True)

    if args.fresh:
        stamp = TODAY.strftime("%Y%m%d") + "-" + str(int(time.time()))
        for suffix in ("", "-wal", "-shm"):
            existing = Path(str(db_path) + suffix)
            if existing.exists():
                backup = Path(str(db_path) + suffix + f".bak-{stamp}")
                shutil.move(str(existing), str(backup))
                print(f"backed up {existing.name} -> {backup.name}")

    bin_path = os.environ.get("MCP_HOST_BINARY")
    if bin_path:
        host_bin = Path(bin_path)
    else:
        run(["swift", "build", "--product", "LorvexMCPHost"])
        host_bin = Path(run(["swift", "build", "--show-bin-path"])) / "LorvexMCPHost"
    if not host_bin.exists():
        raise SeedError(f"missing MCP host binary at {host_bin}")

    proc = subprocess.Popen(
        [str(host_bin)], cwd=ROOT,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        env={**os.environ, "NSUnbufferedIO": "YES",
             "LORVEX_APPLE_DB_PATH": str(db_path), "LORVEX_APPLE_SCHEMA_PATH": str(SCHEMA_PATH)},
    )
    try:
        seed(Host(proc))
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
    print(f"\nSeeded demo data into {db_path}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SeedError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
