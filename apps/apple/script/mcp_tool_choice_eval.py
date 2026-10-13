#!/usr/bin/env python3
"""Checks that an assistant, given only the MCP tool catalog, picks the right Lorvex tool.

The catalog's descriptions are the product for an AI client: a vague or overlapping
description sends an assistant to the wrong tool. This script makes that measurable.

  script/mcp_tool_choice_eval.py prepare <out-dir> [--host <LorvexMCPHost>]
      Starts the built MCP host against a disposable database, reads `tools/list` and the
      server instructions, and writes into <out-dir>:
        server_instructions.txt  what the server tells a client
        catalog.txt              every tool as a client sees it (name, access, description, params)
        scenarios.json           the user requests in script/mcp_tool_choice_scenarios.json
        tools_list.json          the full `tools/list` result, for `check`
      Give the first three files to a fresh assistant (a sub-agent that may read only those) and
      ask for the ordered tool calls it would make per request, as
      [{"id": 1, "calls": [{"tool": "create_task", "args": {...}}], "decisive": "create_task",
        "doubt": ""}].

  script/mcp_tool_choice_eval.py check <out-dir> <answers.json>
      Reports how many requests got an accepted tool as the decisive call (or among the
      calls), which requests did not, the doubts the assistant raised, and every proposed call
      whose arguments break the tool's input schema (unknown tool, missing required argument,
      unknown argument, a value outside an enum, a wrong JSON type).

A request's accepted tools are a judgement, so a mismatch is a question, not a failure: read the
two descriptions and decide whether the assistant or the scenario was wrong. Re-run after adding
or rewording a tool. Build the host first: `swift build --product LorvexMCPHost`.
"""

from __future__ import annotations

import argparse
import json
import os
import select
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
SCENARIOS = SCRIPT_DIR / "mcp_tool_choice_scenarios.json"
APP_DIR = SCRIPT_DIR.parent
READ_TIMEOUT_SECONDS = 60


def load_scenarios() -> list[dict[str, Any]]:
    return json.loads(SCENARIOS.read_text(encoding="utf-8"))


def compact_catalog(tools: list[dict[str, Any]]) -> str:
    """The tools as an assistant reads them, without the schema's JSON noise."""
    blocks: list[str] = []
    for tool in tools:
        schema = tool.get("inputSchema") or {}
        required = set(schema.get("required") or [])
        params: list[str] = []
        for name, spec in (schema.get("properties") or {}).items():
            if name == "idempotency_key":
                continue
            kind = spec.get("type", "any")
            if kind == "array":
                kind = f"array<{(spec.get('items') or {}).get('type', 'any')}>"
            text = f"{name}{'*' if name in required else ''}:{kind}"
            if spec.get("enum"):
                text += "{" + "|".join(map(str, spec["enum"])) + "}"
            description = (spec.get("description") or "").strip()
            if description:
                text += f" — {description}"
            params.append(text)
        access = "read" if (tool.get("annotations") or {}).get("readOnlyHint") else "write"
        blocks.append(
            f"### {tool['name']} [{access}]\n{(tool.get('description') or '').strip()}\n"
            f"params: {'; '.join(params) if params else '(none)'}"
        )
    return "\n\n".join(blocks)


def _json_type_matches(kind: str | list[str], value: Any) -> bool:
    kinds = kind if isinstance(kind, list) else [kind]
    for one in kinds:
        if one == "string" and isinstance(value, str):
            return True
        if one == "integer" and isinstance(value, int) and not isinstance(value, bool):
            return True
        if one == "number" and isinstance(value, (int, float)) and not isinstance(value, bool):
            return True
        if one == "boolean" and isinstance(value, bool):
            return True
        if one == "array" and isinstance(value, list):
            return True
        if one == "object" and isinstance(value, dict):
            return True
        if one == "null" and value is None:
            return True
    return False


def schema_problems(tools: dict[str, dict[str, Any]], call: dict[str, Any]) -> list[str]:
    """What is wrong with one proposed call, judged against the tool's input schema."""
    name = call.get("tool", "")
    tool = tools.get(name)
    if tool is None:
        return [f"{name}: no such tool"]
    schema = tool.get("inputSchema") or {}
    properties = schema.get("properties") or {}
    arguments = call.get("args") or {}
    problems: list[str] = []
    for required in schema.get("required") or []:
        if required not in arguments:
            problems.append(f"{name}: missing required argument {required}")
    for key, value in arguments.items():
        spec = properties.get(key)
        if spec is None:
            problems.append(f"{name}: unknown argument {key}")
            continue
        if spec.get("enum") and value not in spec["enum"]:
            problems.append(f"{name}: {key}={value!r} is not one of {spec['enum']}")
        elif "type" in spec and not _json_type_matches(spec["type"], value):
            problems.append(f"{name}: {key}={value!r} is not of type {spec['type']}")
    return problems


def check_answers(
    tools_list: list[dict[str, Any]],
    scenarios: list[dict[str, Any]],
    answers: list[dict[str, Any]],
) -> dict[str, Any]:
    """Scores the answers against the accepted tools and the tools' schemas."""
    tools = {tool["name"]: tool for tool in tools_list}
    by_id = {answer["id"]: answer for answer in answers}
    matched = 0
    mismatches: list[dict[str, Any]] = []
    doubts: list[dict[str, Any]] = []
    problems: list[str] = []
    missing: list[int] = []
    for index, scenario in enumerate(scenarios, start=1):
        answer = by_id.get(index)
        if answer is None:
            missing.append(index)
            continue
        calls = answer.get("calls") or []
        called = [call.get("tool") for call in calls]
        accepted = scenario["accepted"]
        if answer.get("decisive") in accepted or any(tool in accepted for tool in called):
            matched += 1
        else:
            mismatches.append(
                {
                    "id": index,
                    "request": scenario["request"],
                    "accepted": accepted,
                    "decisive": answer.get("decisive"),
                    "calls": called,
                    "doubt": answer.get("doubt", ""),
                }
            )
        if answer.get("doubt"):
            doubts.append({"id": index, "doubt": answer["doubt"]})
        for call in calls:
            problems.extend(f"#{index} {problem}" for problem in schema_problems(tools, call))
    return {
        "total": len(scenarios),
        "matched": matched,
        "mismatches": mismatches,
        "missing": missing,
        "doubts": doubts,
        "schema_problems": problems,
    }


def _read_message(process: subprocess.Popen[str]) -> dict[str, Any]:
    assert process.stdout is not None
    ready, _, _ = select.select([process.stdout], [], [], READ_TIMEOUT_SECONDS)
    if not ready:
        raise TimeoutError("the MCP host did not answer in time")
    line = process.stdout.readline()
    if not line:
        raise RuntimeError("the MCP host closed its output")
    return json.loads(line)


def read_catalog(host: Path) -> tuple[str, list[dict[str, Any]]]:
    """The server instructions and every tool from `tools/list`, over stdio, against a disposable store."""
    if ".app/" in str(host):
        sys.exit(
            "refusing to run a packaged (sandboxed) host: it would open the real App Group. "
            "Use the SwiftPM-built binary."
        )
    with tempfile.TemporaryDirectory(prefix="lorvex-tool-eval-") as database_dir:
        environment = dict(os.environ)
        environment["LORVEX_APPLE_DB_PATH"] = str(Path(database_dir) / "lorvex.sqlite")
        process = subprocess.Popen(
            [str(host)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=environment,
            text=True,
        )
        assert process.stdin is not None

        def send(message: dict[str, Any]) -> None:
            process.stdin.write(json.dumps(message) + "\n")
            process.stdin.flush()

        try:
            send(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2025-06-18",
                        "capabilities": {},
                        "clientInfo": {"name": "mcp-tool-choice-eval", "version": "1"},
                    },
                }
            )
            instructions = _read_message(process)["result"].get("instructions", "")
            send({"jsonrpc": "2.0", "method": "notifications/initialized"})
            tools: list[dict[str, Any]] = []
            cursor: str | None = None
            request_id = 2
            while True:
                params = {"cursor": cursor} if cursor else {}
                send({"jsonrpc": "2.0", "id": request_id, "method": "tools/list", "params": params})
                request_id += 1
                result = _read_message(process)["result"]
                tools.extend(result["tools"])
                cursor = result.get("nextCursor")
                if not cursor:
                    break
            return instructions, tools
        finally:
            process.terminate()
            process.wait(timeout=10)


def default_host() -> Path:
    output = subprocess.run(
        ["swift", "build", "--show-bin-path"],
        cwd=APP_DIR,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    return Path(output) / "LorvexMCPHost"


def prepare(out_dir: Path, host: Path) -> None:
    if not host.exists():
        sys.exit(f"{host} does not exist; run `swift build --product LorvexMCPHost` first")
    instructions, tools = read_catalog(host)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "server_instructions.txt").write_text(instructions, encoding="utf-8")
    (out_dir / "catalog.txt").write_text(compact_catalog(tools), encoding="utf-8")
    (out_dir / "tools_list.json").write_text(json.dumps(tools, indent=1), encoding="utf-8")
    requests = [
        {"id": index, "request": scenario["request"]}
        for index, scenario in enumerate(load_scenarios(), start=1)
    ]
    (out_dir / "scenarios.json").write_text(json.dumps(requests, indent=1), encoding="utf-8")
    print(f"{len(tools)} tools and {len(requests)} requests written to {out_dir}")


def check(out_dir: Path, answers_path: Path) -> int:
    tools = json.loads((out_dir / "tools_list.json").read_text(encoding="utf-8"))
    answers = json.loads(answers_path.read_text(encoding="utf-8"))
    report = check_answers(tools, load_scenarios(), answers)
    print(f"{report['matched']}/{report['total']} requests got an accepted tool")
    for item in report["mismatches"]:
        print(
            f"\n#{item['id']} {item['request']}\n"
            f"  accepted {item['accepted']}; decisive {item['decisive']}; calls {item['calls']}\n"
            f"  doubt: {item['doubt']}"
        )
    if report["missing"]:
        print(f"\nno answer for requests {report['missing']}")
    if report["doubts"]:
        print("\nDoubts the assistant raised:")
        for item in report["doubts"]:
            print(f"  #{item['id']}: {item['doubt']}")
    print(f"\n{len(report['schema_problems'])} proposed call(s) break a tool's input schema")
    for problem in report["schema_problems"]:
        print(f"  {problem}")
    return 1 if report["schema_problems"] or report["missing"] else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare_parser = commands.add_parser("prepare")
    prepare_parser.add_argument("out_dir", type=Path)
    prepare_parser.add_argument("--host", type=Path, help="the LorvexMCPHost binary (default: the SwiftPM build)")
    check_parser = commands.add_parser("check")
    check_parser.add_argument("out_dir", type=Path)
    check_parser.add_argument("answers", type=Path)
    arguments = parser.parse_args()
    if arguments.command == "prepare":
        prepare(arguments.out_dir, arguments.host or default_host())
        return 0
    return check(arguments.out_dir, arguments.answers)


if __name__ == "__main__":
    sys.exit(main())
