#!/usr/bin/env python3
"""Lets an assistant carry out whole requests against a seeded Lorvex store, and records what it cost.

`mcp_tool_choice_eval.py` asks which tool an assistant would pick from the catalog. This script
covers what that cannot: an assistant doing a person's request end to end with the real server,
so the number of calls, the size of every result, the errors, and the assistant's own account of
what got in its way can be read afterwards.

  script/mcp_assistant_session.py seed <store-dir> [--host <LorvexMCPHost>]
      Creates <store-dir> with a database holding one fictional person's week (five lists, 44
      tasks, 14 calendar events, four habits, three memory notes), written through the MCP tools.
      The day the seed runs is the person's "today".

  script/mcp_assistant_session.py copy <store-dir> <new-store-dir>
      A copy of a store, so each request starts from the same state.

  script/mcp_assistant_session.py brief <store-dir> <request-id>
      Prints the instructions for a fresh sub-agent that plays the person's assistant: the request
      (from script/mcp_assistant_session_requests.json), the commands below with <store-dir>
      filled in, and the report it must return. Give it to a sub-agent that may use only those
      commands.

  script/mcp_assistant_session.py instructions <store-dir>
  script/mcp_assistant_session.py tools <store-dir>
  script/mcp_assistant_session.py schema <store-dir> <tool> [<tool>…]
  script/mcp_assistant_session.py call <store-dir> <tool> '<json arguments>'   ("-" reads standard input)
      What an assistant sees: the server's instructions, every tool's name and first sentence,
      a tool's full description and input schema, and the result of one call. `call` prints the
      structured payload as JSON, or the text when a result has none; an error result starts
      with "ERROR: ". Each command is appended to <store-dir>/calls.jsonl.

  script/mcp_assistant_session.py summary <store-dir>
      The calls made on a store: how many, how many failed or carried warnings, the bytes
      received, and one line per call.

The host must be the SwiftPM-built binary (`swift build --product LorvexMCPHost`); a packaged,
sandboxed host would open the real App Group and is refused.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import select
import shutil
import sqlite3
import subprocess
import sys
import time
import zoneinfo
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
APP_DIR = SCRIPT_DIR.parent
SCHEMA_PATH = APP_DIR.parents[1] / "schema" / "schema.sql"
REQUESTS = SCRIPT_DIR / "mcp_assistant_session_requests.json"
PROTOCOL_VERSION = "2025-11-25"
READ_TIMEOUT_SECONDS = 60.0
SEED_ZONE = "America/Los_Angeles"
FENCE_MARKERS = ("⟦user⟧", "⟦/user⟧")


def default_host() -> Path:
    output = subprocess.run(
        ["swift", "build", "--show-bin-path"], cwd=APP_DIR, check=True, capture_output=True, text=True
    ).stdout.strip()
    return Path(output) / "LorvexMCPHost"


class Store:
    """One store directory: its database, the host that serves it, and its call log."""

    def __init__(self, directory: Path) -> None:
        self.directory = directory
        self.database = directory / "lorvex.db"
        self.log = directory / "calls.jsonl"
        self.session = directory / "session.json"

    def host(self) -> Path:
        if not self.session.exists():
            sys.exit(f"{self.directory} is not a store: run `seed` or `copy` first.")
        return Path(json.loads(self.session.read_text(encoding="utf-8"))["host"])

    def record(self, entry: dict[str, Any]) -> None:
        with self.log.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"at": round(time.time(), 2), **entry}, ensure_ascii=False) + "\n")


class Client:
    """A stdio MCP client for one store."""

    def __init__(self, host: Path, database: Path) -> None:
        if ".app/" in str(host):
            sys.exit(
                "refusing to run a packaged (sandboxed) host: it would open the real App Group. "
                "Use the SwiftPM-built binary."
            )
        if not host.exists():
            sys.exit(f"no host at {host}: run `swift build --product LorvexMCPHost`.")
        environment = {
            **os.environ,
            "NSUnbufferedIO": "YES",
            "LORVEX_APPLE_DB_PATH": str(database),
            "LORVEX_APPLE_SCHEMA_PATH": str(SCHEMA_PATH),
        }
        self.process = subprocess.Popen(
            [str(host)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            env=environment,
        )
        self.next_id = 0
        self.info = self.request(
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "mcp-assistant-session", "version": "1"},
            },
        )["result"]
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _send(self, message: dict[str, Any]) -> None:
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        assert self.process.stdout is not None
        self.next_id += 1
        request_id = self.next_id
        self._send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        deadline = time.monotonic() + READ_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.process.stdout], [], [], 0.1)
            if not ready:
                continue
            line = self.process.stdout.readline()
            if not line:
                break
            payload = json.loads(line)
            if payload.get("id") == request_id:
                return payload
        sys.exit(f"the MCP host did not answer {method}")

    def tools(self) -> list[dict[str, Any]]:
        tools: list[dict[str, Any]] = []
        cursor: str | None = None
        while True:
            page = self.request("tools/list", {"cursor": cursor} if cursor else {})["result"]
            tools.extend(page["tools"])
            cursor = page.get("nextCursor")
            if not cursor:
                return tools

    def call(self, tool: str, arguments: dict[str, Any]) -> tuple[bool, Any, list[str]]:
        """Whether the result is an error, its structured payload (or None), and its text blocks."""
        reply = self.request("tools/call", {"name": tool, "arguments": arguments})
        if "error" in reply:
            return True, None, [json.dumps(reply["error"], ensure_ascii=False)]
        result = reply["result"]
        texts = [block.get("text", "") for block in result.get("content", []) if block.get("type") == "text"]
        return bool(result.get("isError")), result.get("structuredContent"), texts

    def close(self) -> None:
        assert self.process.stdin is not None
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()


def first_sentence(text: str) -> str:
    text = " ".join(text.split())
    cut = text.find(". ")
    sentence = text if cut < 0 else text[: cut + 1]
    return sentence if len(sentence) <= 200 else sentence[:197] + "…"


def summarize(rows: list[dict[str, Any]], argument_width: int = 150) -> str:
    """The totals of a call log, then one line per command."""
    calls = [row for row in rows if row["command"] == "call"]
    lines = [
        f"{len(rows)} commands, {len(calls)} tool calls, "
        f"{sum(1 for row in calls if row.get('isError'))} errors, "
        f"{sum(1 for row in calls if row.get('warnings'))} with warnings, "
        f"{sum(row.get('bytes', 0) for row in rows)} bytes received "
        f"({sum(row.get('bytes', 0) for row in calls)} from tool results)"
    ]
    for row in rows:
        size = f"{row.get('bytes', 0):>6}B"
        if row["command"] == "call":
            flag = "ERR " if row.get("isError") else ("WARN" if row.get("warnings") else "    ")
            arguments = json.dumps(row.get("args"), ensure_ascii=False)[:argument_width]
            lines.append(f"  {flag} {row.get('tool')} {size}  {arguments}")
            if row.get("isError"):
                lines.append(f"        -> {(row.get('result') or row.get('clientError') or '')[:300]}")
            if row.get("warnings"):
                lines.append(f"        -> {row['warnings']}")
        elif row["command"] == "schema":
            lines.append(f"       schema {size}  {' '.join(row.get('tools', []))}")
        else:
            lines.append(f"       {row['command']} {size}")
    return "\n".join(lines)


def seed(store: Store, host: Path) -> int:
    """Writes the fictional week into a new store. Returns the number of failed calls."""
    if store.directory.exists():
        sys.exit(f"{store.directory} already exists; seed into a new directory.")
    store.directory.mkdir(parents=True)
    store.session.write_text(json.dumps({"host": str(host)}), encoding="utf-8")
    zone = zoneinfo.ZoneInfo(SEED_ZONE)
    today = datetime.datetime.now(zone).date()

    def day(offset: int) -> str:
        return (today + datetime.timedelta(days=offset)).isoformat()

    def done_at(offset: int, hour: int) -> str:
        local = datetime.datetime.combine(today + datetime.timedelta(days=offset), datetime.time(hour, 0), zone)
        return local.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    client = Client(host, store.database)
    failures = 0

    def call(tool: str, arguments: dict[str, Any]) -> dict[str, Any]:
        nonlocal failures
        is_error, structured, texts = client.call(tool, arguments)
        if is_error:
            failures += 1
            print(f"FAIL {tool}: {json.dumps(structured, ensure_ascii=False)[:400] if structured else texts}")
        return structured or {}

    call("complete_setup", {"working_hours": "09:00-17:30", "timezone": SEED_ZONE})

    lists: dict[str, str] = {}
    for name, icon, color, description in [
        ("Work", "briefcase", "#3B82F6", "Product management at the day job"),
        ("Home", "house", "#22C55E", "House, family, money"),
        ("Podcast", "mic", "#A855F7", "The weekend podcast: episodes, guests, sponsors"),
        ("Errands", "cart", "#F59E0B", "Things to do while out"),
        ("Reading", "book", "#64748B", "Books and papers"),
    ]:
        lists[name] = call(
            "create_list", {"name": name, "icon": icon, "color": color, "description": description}
        )["id"]

    def task(title: str, list_name: str | None = None, **fields: Any) -> dict[str, Any]:
        entry = {"title": title, **fields}
        if list_name:
            entry["list_id"] = lists[list_name]
        return entry

    def captured(text: str) -> dict[str, Any]:
        return task(text, raw_input=text)

    tasks = [
        task("Send Q4 roadmap draft to Priya", "Work", due_date=day(0), priority=1, estimated_minutes=60),
        task("Review Dana's pricing proposal", "Work", due_date=day(-1), priority=2, estimated_minutes=30),
        task(
            "Prepare slides for Wednesday's customer call",
            "Work",
            due_date=day(1),
            priority=1,
            estimated_minutes=120,
            checklist=["Outline", "Usage charts", "Pricing slide", "Dry run"],
        ),
        task("Reply to legal about the vendor contract", "Work", due_date=day(-3), priority=1, estimated_minutes=20),
        task("File October expense report", "Work", due_date=day(-4), priority=3, estimated_minutes=15),
        task(
            "Write interview feedback for the backend candidate",
            "Work",
            due_date=day(1),
            priority=2,
            estimated_minutes=25,
        ),
        task("Draft 2027 hiring plan", "Work", due_date=day(-2), priority=2, estimated_minutes=90),
        task("Update onboarding doc for new PMs", "Work", priority=3),
        task("Get offsite budget approved", "Work", due_date=day(2), priority=2, estimated_minutes=20),
        task("Book team offsite venue", "Work", due_date=day(10), priority=2, estimated_minutes=45),
        task("Prep notes for 1:1 with Sam", "Work", planned_date=day(0), estimated_minutes=15),
        task(
            "Analyze churn dashboard numbers",
            "Work",
            status="in_progress",
            priority=2,
            estimated_minutes=45,
            notes="Q3 vs Q4 cohorts. Half done: enterprise segment left.",
        ),
        task("Follow up with Acme on renewal", "Work", due_date=day(4), priority=1, estimated_minutes=15),
        task("Clean up the Jira backlog", "Work", status="someday"),
        task("Send weekly status update", "Work", status="completed", completed_at=done_at(-3, 16)),
        task("Review launch checklist with QA", "Work", status="completed", completed_at=done_at(-4, 11)),
        task("Approve design for settings page", "Work", status="completed", completed_at=done_at(-5, 15)),
        task("Renew car registration", "Home", due_date=day(4), priority=1, estimated_minutes=20),
        task("Call plumber about the kitchen leak", "Home", due_date=day(0), priority=2, estimated_minutes=10),
        task("Schedule dentist appointment", "Home", due_date=day(-6), priority=3, estimated_minutes=10),
        task("Buy birthday gift for Mom", "Home", due_date=day(5), priority=2),
        task("Pay electricity bill", "Home", due_date=day(1), priority=2, estimated_minutes=5),
        task("Fix the squeaky door", "Home", status="someday"),
        task("Plan Thanksgiving menu", "Home", due_date=day(1), priority=2, estimated_minutes=30),
        task("Take out recycling", "Home", due_date=day(1), estimated_minutes=5),
        task("Order turkey", "Home", status="completed", completed_at=done_at(-2, 10)),
        task("Edit episode 12 audio", "Podcast", due_date=day(5), priority=2, estimated_minutes=120),
        task("Write show notes for episode 12", "Podcast", due_date=day(6), estimated_minutes=40),
        task("Email guest for episode 14 scheduling", "Podcast", due_date=day(0), priority=2),
        task("Research sponsors list", "Podcast"),
        task("Renew podcast hosting plan", "Podcast", due_date=day(14), estimated_minutes=10),
        task("Pick up dry cleaning", "Errands", planned_date=day(0), estimated_minutes=15),
        task("Return package at the post office", "Errands", due_date=day(2), estimated_minutes=20),
        task("Get flu shot", "Errands", due_date=day(4), estimated_minutes=30),
        task("Finish The Manager's Path, chapters 5 and 6", "Reading", status="someday"),
        task("Read the cohort retention paper Dana sent", "Reading", estimated_minutes=40),
        # Quick captures left in the inbox, nothing decided.
        captured("look into standing desk"),
        captured("ask Priya about budget for a contractor"),
        captured("passport renewal???"),
        captured("idea: weekly digest email for customers"),
        captured("book flights for December trip"),
        captured("Dana mentioned a new analytics vendor, check it"),
        captured("cancel gym membership"),
        captured("thank-you note to Lee"),
    ]
    created = call("batch_create_tasks", {"tasks": tasks}).get("results") or []
    ids: dict[str, str] = {}
    for row in created:
        title = row["title"]
        for marker in FENCE_MARKERS:
            title = title.replace(marker, "")
        ids[title] = row["id"]
    print(f"tasks created: {len(created)} of {len(tasks)}")

    if created:
        call(
            "update_task",
            {"id": ids["Book team offsite venue"], "depends_on": [ids["Get offsite budget approved"]]},
        )
        call(
            "update_task",
            {"id": ids["Write show notes for episode 12"], "depends_on": [ids["Edit episode 12 audio"]]},
        )
        call(
            "delegate_task",
            {
                "id": ids["Email guest for episode 14 scheduling"],
                "request": "Draft the email for me and propose two recording slots next week "
                "that are free on my calendar.",
            },
        )
        hiring_plan = ids["Draft 2027 hiring plan"]
        call("defer_task", {"id": hiring_plan, "until_date": day(-1), "structured_reason": "low_energy"})
        call("defer_task", {"id": hiring_plan, "until_date": day(0), "structured_reason": "not_today"})
        call(
            "set_task_recurrence",
            {"task_id": ids["Take out recycling"], "recurrence": {"freq": "WEEKLY", "byday": ["TU"]}},
        )
        call(
            "set_task_ai_notes",
            {
                "task_id": ids["Reply to legal about the vendor contract"],
                "notes": "Legal asked for a yes/no on the liability cap. Blocking the vendor start date.",
            },
        )

    def event(title: str, offset: int, start: str | None = None, end: str | None = None, **fields: Any) -> dict:
        entry: dict[str, Any] = {"title": title, "start_date": day(offset), **fields}
        if start and end:
            entry.update(start_time=start, end_time=end)
        else:
            entry["all_day"] = True
        return entry

    events = [
        event("Team standup", 0, "09:30", "09:45", recurrence={"freq": "WEEKLY", "byday": ["MO", "TU", "WE"]}),
        event("1:1 with Sam", 0, "14:00", "14:30"),
        event("School pickup", 0, "17:15", "17:45", recurrence={"freq": "WEEKLY", "byday": ["MO", "WE"]}),
        event("Product review", 1, "10:00", "11:30"),
        event("Lunch with Alex", 1, "12:30", "13:30", location="Tartine"),
        event("Interview: backend candidate (debrief)", 1, "15:00", "15:30"),
        event("Customer call: Northwind", 2, "11:00", "12:00"),
        event("Budget review with finance", 2, "15:00", "16:00"),
        event("Thanksgiving", 3),
        event("Day off", 4),
        event("Record episode 13", 5, "10:00", "11:30"),
        event("Quarterly planning", 7, "13:00", "16:00"),
        event("Design sync", 8, "11:00", "11:45"),
        event("All-hands", 9, "10:00", "11:00"),
    ]
    made = call("batch_create_calendar_events", {"events": events})
    print(f"events created: {len(made.get('results') or [])} of {len(events)}")

    habits: dict[str, str] = {}
    for spec in [
        {"name": "Morning run", "frequency_type": "times_per_week", "per_period_target": 3, "icon": "figure.run"},
        {"name": "Read 20 minutes", "frequency_type": "daily", "icon": "book", "cue": "After dinner"},
        {"name": "Drink water", "frequency_type": "daily", "target_count": 8, "icon": "drop"},
        {"name": "Weekly review", "frequency_type": "weekly", "weekdays": [6], "icon": "checklist"},
    ]:
        habits[spec["name"]] = call("create_habit", spec).get("id", "")
    for offset, names in [
        (-1, ["Read 20 minutes"]),
        (-2, ["Morning run", "Read 20 minutes"]),
        (-3, ["Read 20 minutes"]),
        (-4, ["Morning run"]),
    ]:
        call("batch_complete_habits", {"date": day(offset), "habit_ids": [habits[name] for name in names]})

    call(
        "write_memory",
        {
            "key": "user_profile",
            "content": "Maya. Product manager at a B2B software startup; reports to Priya. Hosts a small "
            "interview podcast, recorded on Saturday mornings. Does focused work best before noon; "
            "prefers meetings after lunch. Picks up her kid from school on Mondays and Wednesdays at 17:15.",
        },
    )
    call(
        "write_memory",
        {
            "key": "routines",
            "content": "Morning plan: at most three priority items for the day. Keep 12:00-13:00 free for "
            "lunch. Errands go after 17:00 or on the way to school pickup. Never plan work on a day off.",
        },
    )
    call(
        "write_memory",
        {
            "key": "list_summaries",
            "content": "Work: the day job. Home: house, family, money. Podcast: episodes, guests, sponsors. "
            "Errands: things done while out. Reading: books and papers. Inbox: unsorted quick captures.",
        },
    )
    print("overview stats:", json.dumps(call("get_overview", {}).get("stats")))
    client.close()
    return failures


def copy_store(source: Store, target: Store) -> None:
    if target.directory.exists():
        sys.exit(f"{target.directory} already exists; copy into a new directory.")
    host = source.host()
    target.directory.mkdir(parents=True)
    # SQLite's backup carries the write-ahead log's contents with it.
    with sqlite3.connect(source.database) as original, sqlite3.connect(target.database) as duplicate:
        original.backup(duplicate)
    target.session.write_text(json.dumps({"host": str(host)}), encoding="utf-8")


def brief(store: Store, request_id: str) -> str:
    requests = {entry["id"]: entry for entry in json.loads(REQUESTS.read_text(encoding="utf-8"))}
    if request_id not in requests:
        sys.exit(f"no request named {request_id}; the requests are: {', '.join(requests)}")
    command = f"{Path(__file__).resolve()} "
    target = str(store.directory.resolve())
    return f"""This is a usability test of an MCP server. You play an AI assistant that a person has \
connected to their task manager, Lorvex. The test studies how well an assistant can carry out a \
person's request with this server's tools, so behave exactly as you would as that person's \
assistant: do the request well, with as few calls as it honestly takes.

Your only access to the server is this command, run with the Bash tool:

  {command}instructions {target}
      the server's instructions to you
  {command}tools {target}
      every tool: its name and the first sentence of its description
  {command}schema {target} <tool> [<tool>…]
      the full description and input schema of the named tools
  {command}call {target} <tool> '<json arguments>'
      call a tool; prints the result you receive ("ERROR: " starts an error result)
  {command}call {target} <tool> - <<'JSON'
  {{...}}
  JSON
      the same, with the JSON arguments on standard input (use this when the JSON holds an apostrophe)

Start with `instructions` and `tools`: a real client would have given you both. Read a tool's \
schema before the first time you call it.

Rules:
- Use only that command. Do not read or search any file, do not look at any repository or at the \
command's own source, and do not use any other tool. Do not start other agents.
- The data is a disposable test copy of one person's tasks, so make the changes a good assistant \
would really make.
- The person cannot answer questions during this turn. Where you would normally ask first, follow \
the server's instructions about when to confirm, and say in your reply what you left for them to \
decide.
- Stop after at most 45 calls.

The person's message to you:

"{requests[request_id]['message']}"

When you are done, return exactly these two sections and nothing else:

REPLY TO THE PERSON
What you would say to them (plain text, as short as a good assistant would make it).

NOTES ON THE TOOLS
A frank numbered list of every point where the server made the job harder or where you were \
unsure: a tool or argument name you guessed wrong, a schema you had to read twice, a result that \
was unclear, missing something you needed, or much larger than you needed, a call you had to \
repeat, a fact you could not find, a behavior that surprised you. For each: the tool, what you \
expected, what happened. Also say which calls gave you exactly what you needed. Ignore problems \
caused by shell quoting. If nothing got in your way, say so; do not pad the list.
"""


def run_client_command(store: Store, command: str, rest: list[str]) -> str:
    client = Client(store.host(), store.database)
    try:
        if command == "instructions":
            out = client.info.get("instructions", "")
            store.record({"command": command, "bytes": len(out.encode())})
            return out
        if command == "tools":
            out = "\n".join(f"{tool['name']}: {first_sentence(tool.get('description', ''))}" for tool in client.tools())
            store.record({"command": command, "bytes": len(out.encode())})
            return out
        if command == "schema":
            by_name = {tool["name"]: tool for tool in client.tools()}
            parts = []
            for name in rest:
                tool = by_name.get(name)
                parts.append(
                    json.dumps(
                        {"name": name, "description": tool.get("description"), "inputSchema": tool.get("inputSchema")},
                        ensure_ascii=False,
                    )
                    if tool
                    else f"no tool named {name}"
                )
            out = "\n".join(parts)
            store.record({"command": command, "tools": rest, "bytes": len(out.encode())})
            return out
        if not rest:
            sys.exit("call needs a tool name")
        tool_name = rest[0]
        raw = rest[1] if len(rest) > 1 else "{}"
        try:
            arguments = json.loads(sys.stdin.read() if raw == "-" else raw)
        except json.JSONDecodeError as error:
            store.record({"command": "call", "tool": tool_name, "clientError": f"arguments are not JSON: {error}"})
            sys.exit(f"arguments are not JSON: {error}")
        started = time.monotonic()
        is_error, structured, texts = client.call(tool_name, arguments)
        body = (
            json.dumps(structured, ensure_ascii=False, sort_keys=True) if structured is not None else "\n".join(texts)
        )
        store.record(
            {
                "command": "call",
                "tool": tool_name,
                "args": arguments,
                "isError": is_error,
                "bytes": len(body.encode()),
                "seconds": round(time.monotonic() - started, 3),
                "warnings": structured.get("warnings") if isinstance(structured, dict) else None,
                "result": body if is_error else body[:300],
            }
        )
        return ("ERROR: " if is_error else "") + body
    finally:
        client.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["seed", "copy", "brief", "instructions", "tools", "schema", "call", "summary"])
    parser.add_argument("store", type=Path)
    parser.add_argument("rest", nargs="*")
    parser.add_argument("--host", type=Path, help="the SwiftPM-built LorvexMCPHost (default: swift build --show-bin-path)")
    arguments = parser.parse_args()
    store = Store(arguments.store)

    if arguments.command == "seed":
        failures = seed(store, arguments.host or default_host())
        print(f"failed calls: {failures}")
        return 1 if failures else 0
    if arguments.command == "copy":
        if len(arguments.rest) != 1:
            sys.exit("copy needs the new store directory")
        copy_store(store, Store(Path(arguments.rest[0])))
        return 0
    if arguments.command == "brief":
        if len(arguments.rest) != 1:
            sys.exit("brief needs a request id")
        print(brief(store, arguments.rest[0]))
        return 0
    if arguments.command == "summary":
        rows = [json.loads(line) for line in store.log.read_text(encoding="utf-8").splitlines() if line.strip()]
        print(summarize(rows))
        return 0
    print(run_client_command(store, arguments.command, arguments.rest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
