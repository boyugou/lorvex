# MCP End-to-End Validation (Assistant Workflows)

Purpose: validate the real desktop operator path (assistant -> MCP -> SQLite -> app) before release.

This document is intentionally workflow-oriented instead of tool-count-oriented to avoid doc drift. It validates one critical surface of the product, not the whole product definition by itself.

## Scope

Validate these assistant clients against the same local Lorvex data:
- Claude Desktop
- Claude Code
- Codex

Out of scope:
- Apple Swift app behavior
- remote/provider sync stress tests; the current Tauri release has no active
  cloud sync transport

## Preflight

1. Ensure app + MCP build artifacts are current.
2. Ensure each client points to the same MCP server + DB location.
3. Start with a known data baseline (fresh DB copy or snapshot import).
4. Keep app open on Today + Calendar views during validation for visual confirmation.

## Canonical Workflow Scripts

Use these prompts as operator scripts. They are written to exercise full lifecycle, not isolated tools.

### WF-1 Capture
Prompt:
"Please capture these as separate tasks: renew visa this week, email landlord about lease, refactor BT inference folder today high priority."

Expected MCP sequence (typical):
- create_task (multiple)
- optional update_task for metadata normalization

Pass criteria:
- tasks appear in app without manual refresh
- priority/due/list fields are valid and parseable
- no validation error loop

### WF-2 Triage
Prompt:
"Review task list: verify AI-created tasks are in correct lists, cancel obvious noise."

Expected MCP sequence (typical):
- search_tasks
- cancel_task

Pass criteria:
- cancelled tasks removed from active views correctly
- accepted tasks land in expected lists/status
- cancelled tasks are not shown in active views

### WF-3 Plan
Prompt:
"Build my today plan with the top focus tasks and save it."

Expected MCP sequence (typical):
- get_overview / get_upcoming_tasks
- set_current_focus
- optional propose_daily_schedule + save_focus_schedule

Pass criteria:
- Today focus section updates
- ordering is stable and no duplicate task cards
- priority/focus metadata remains consistent

### WF-4 Execute + Corrections
Prompt:
"Mark first focus task done, defer one low-value task to tomorrow, then reopen the task I just completed."

Expected MCP sequence (typical):
- complete_task
- defer_task
- reopen_task

Pass criteria:
- state transitions are reversible and reflected in UI
- reopened task returns to active sections
- no stale/ghost rows across Today/All Tasks

### WF-5 Review + Learn
Prompt:
"Write today's daily review (wins, blockers, energy, next action), then summarize what changed today."

Expected MCP sequence (typical):
- add_daily_review or amend_daily_review
- get_daily_review / get_review_history
- get_ai_changelog or get_overview

Pass criteria:
- review persists and is queryable
- changelog summary is coherent
- no missing-field failures on structured review payload

## Error Taxonomy + Repro Cases

| Code | Category | Repro Trigger | Expected Behavior | Severity |
|---|---|---|---|---|
| E-VAL-001 | input validation mismatch | send numeric field as invalid string | tool returns clear validation error once; assistant self-corrects | High |
| E-VAL-002 | date/time format mismatch | malformed ISO or timezone token | explicit error with field path; no partial write | High |
| E-TOOL-001 | missing capability | ask assistant to do unsupported operation | assistant reports the missing tool and points to GitHub Issues for tracking | Medium |
| E-STATE-001 | stale view perception | rapid write sequence then immediate read | next read reflects committed state; no contradictory status | High |
| E-DB-001 | sqlite busy/contention | concurrent write-like commands in quick burst | retry or deterministic failure message; no silent data loss | High |
| E-UX-001 | tool friction/context bloat | broad query over huge task set | assistant narrows query scope instead of context explosion | Medium |
| E-CONF-001 | MCP client config drift | wrong command/cwd/runtime path | connection check fails fast with actionable setup guidance | High |

### Minimal Repro Format

When filing a failure, include:
- client (`Claude Desktop` / `Claude Code` / `Codex`)
- exact prompt
- tool call sequence (or transcript)
- error text
- expected vs actual
- whether issue reproduces on second run

## Release Gate Checklist

A release candidate passes MCP E2E gate only if all checks below pass.

### Connectivity
- [ ] Claude Desktop connects and can call `get_overview`
- [ ] Claude Code connects and can call `get_overview`
- [ ] Codex connects and can call `get_overview`

### Workflow Completion
- [ ] WF-1 Capture passes on all clients
- [ ] WF-2 Triage passes on all clients
- [ ] WF-3 Plan passes on all clients
- [ ] WF-4 Execute + Corrections passes on all clients
- [ ] WF-5 Review + Learn passes on all clients

### Failure Handling
- [ ] At least one E-VAL repro is tested and recovered by assistant
- [ ] At least one E-CONF repro is tested and setup guidance is correct
- [ ] No blocker-level unresolved defects remain

### Evidence
- [ ] Attach transcript snippets for each client
- [ ] Attach at least one app screenshot proving UI state after WF-4
- [ ] Link created issues for any non-blocking defects

## Reusable Evidence Template

Use the MCP gate template to avoid rewriting issue comments from scratch.

- Template: `docs/execution/templates/manual-gate-mcp-e2e.md.tmpl`
- Generate a local report scaffold:

```bash
npm run docs:manual-gate:report -- --template mcp-e2e --date YYYY-MM-DD --issue <current-issue> --commit <git-sha>
```

Use exactly one current evidence target: `--issue <current-issue>`, `--pr <current-pr>`, or `--release-target <release-target>`.

- Verify template + checklist references before posting:

```bash
npm run verify:manual-gate-templates
npm run verify:manual-gate-evidence
```

Default output path:
`artifacts/manual-gates/mcp-e2e/YYYY-MM-DD/<target-slug>.md`

Do not commit generated evidence. Attach the relevant report path, screenshots, and transcripts in the linked issue/PR discussion. Fill `Evidence permalink` with the posted GitHub issue/PR comment URL before treating the gate as complete.

Freshness policy:
- Manual gate evidence is considered fresh for 14 days from the report date.
- Release flow enforces freshness + required fields with:

```bash
npm run verify:manual-gate-evidence -- --enforce-release
```

## Operator Notes

- Prefer semantic tools over raw field patching when both exist.
- Keep queries scoped (list/date/status) for large datasets.
- If repeated friction appears, open a tracker issue on GitHub.

## Automation Bridge Coverage (#224)

Automated subset (repeatable smoke):

```bash
npm run manual-gate:smoke
```

This command automates the deterministic MCP E2E subset:
- MCP contract + representative workflow integration checks
- bounded payload/latency scale budget checks (1k/10k datasets)
- report emission (machine-readable + human-readable)

Still manual by design:
- cross-client real operator execution across Claude Desktop / Claude Code / Codex
- WF-1..WF-5 transcript quality and UX judgment
- visual screenshot evidence after workflow transitions
