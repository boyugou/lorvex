# GitHub Issue Lifecycle Standard
This document defines the canonical issue lifecycle from intake to close, so execution state is queryable and repeatable across humans and agents.

---

## 1) Lifecycle States

Use these states in order. Skip only when explicitly justified in an issue comment.

1. **Intake**
2. **Design**
3. **Agent-ready**
4. **In progress**
5. **Ready for review**
6. **Done**

`Blocked` can be entered from any active state and must include blocker evidence + unblocking condition.

---

## 2) State Entry Criteria

### Intake

Minimum required:

- Problem statement or objective is explicit.
- Scope is bounded enough to triage (or explicitly marked as discussion-first).
- Base labels present: `tracker`, exactly one `priority-*`, and at least one type lane label (`type-task`/`type-quality`/`type-epic`/`maintenance`).

### Design

Enter when implementation intent is non-trivial and requires architecture/UX/tool-contract decisions.

Minimum required:

- Decision surface is listed (what choices must be made).
- Acceptance criteria draft exists (can be refined later).
- `needs-design` label is applied until design is accepted.

### Agent-ready

Enter only when work can execute without hidden context.

Minimum required:

- Clear acceptance criteria and verification commands.
- File or module ownership boundaries are explicit (at least at directory granularity).
- For non-trivial feature work, a current design artifact is linked and accepted before `agent-ready`.
- External research gate status is explicit:
  - `Evidence Note` linked when required, or
  - one-line `research not required` rationale.
- `needs-design` removed; `agent-ready` applied.

### In progress

Minimum required:

- Implementation started in a branch/commit/PR linked in issue comments.
- Owner/workstream noted when parallel streams exist.

### Ready for review

Minimum required:

- Implementation complete for current scope.
- Verification commands and outcomes posted.
- Known residual risks called out.
- Evidence permalink points to a same-repository GitHub issue/PR comment carrying the verification result, review waiver, or manual gate evidence.

### Done

Minimum required:

- Merged to `main`.
- Structured close-out comment posted (Outcome / What changed / Verification / Risk-Follow-up).
- Close-out comment includes `Evidence permalink: <same-repo GitHub issue/PR comment URL>` and `Commit: <git-sha reachable from origin/main>`.
- Close-out draft passes `npm run verify:issue-lifecycle-evidence -- --closeout-file <path>` when prepared locally.
- Posted closed issue passes `npm run verify:issue-lifecycle-evidence -- --issue <number>`.
- Tracker sync completed:
  - GitHub issue state/comments updated,
  - `ROADMAP.md` / feature docs updated when milestone or shipped status changed.
  The GitHub issue tracker is the canonical execution queue.

---

## 3) Required Label Taxonomy Per Issue

Every executable issue should include:

- `tracker`
- Exactly one priority label (`priority-p0` / `priority-p1` / `priority-p2`)
- At least one type lane label (`type-task` / `type-quality` / `type-epic` / `maintenance`)
- Stream label when applicable (`stream-*`)
- Readiness label (`needs-design` or `agent-ready`) for non-trivial items,
  unless an inherent blocker label applies (`blocked`, `blocked-external`,
  `discussion`, or `type-epic`)

The live open queue is checked by `npm run verify:open-issue-lifecycle`.
That verifier reads open issues through `gh issue list --state open` and
enforces the label taxonomy above. The `maintenance` label is a type lane,
not a stream label; multiple type lane labels are allowed when each one adds
useful routing signal. `blocked-external` is for tracker issues that are
waiting on account, DNS, billing, plan, or upstream provider state; it is
not `agent-ready` until that external condition clears. Open issues without
`tracker` fail unless they carry a documented non-executable exemption such
as `discussion`.
Legacy readiness-label backfill waivers
must stay explicit in `scripts/verify/open_issue_lifecycle_exceptions.json`;
the waiver file may only document missing readiness labels, never missing or
ambiguous priority/type labels.

---

## 4) Transition Checklist (Controller/Owner)

Use this checklist before moving lifecycle state:

- Scope still matches the issue title/body.
- Acceptance criteria are still current.
- Linked docs are up to date (or update is explicitly deferred with rationale).
- Subagent output (if any) has passed explicit controller acceptance review.
- Blockers are recorded as evidence, not implied in chat.

---

## 5) Blocked State Rules

When entering `Blocked`, include all fields:

- `Blocker`: what is blocking execution now.
- `Why blocked now`: concrete dependency or environment limitation.
- `Evidence`: commands/logs/manual gate status.
- `Unblock condition`: exact event needed to resume.
- `Fallback`: next executable issue selected to avoid idle time.

Manual-only validation gates should remain open with evidence and should not halt coding throughput.

---

## 6) Post-Merge Sync Ritual (Mandatory)

Run this after each merged implementation cycle:

1. Post structured issue update comment (or close-out comment).
2. Re-triage top executable open issues.
3. For local close-out drafts, run `npm run verify:issue-lifecycle-evidence -- --closeout-file <path>` before posting; for posted closed issues, use `npm run verify:issue-lifecycle-evidence -- --issue <number>`.
   The bare verifier, `npm run verify:issue-lifecycle-evidence`, is intentionally not contract-only: it scans the most recent closed issues and fails if any lack structured evidence. Use `npm run verify:issue-lifecycle-evidence -- --contract-only` only when validating the docs/sample contract without touching GitHub issue state.
4. Align queue docs when state changed:
   - `ROADMAP.md` (if milestone/track status changed)
   - `docs/design/FEATURES.md` or the relevant current design doc (if feature state changed)
   The GitHub issue tracker is the canonical active queue.

This ritual is the anti-drift mechanism; do not defer it to "later cleanup."

---

## 7) Process Retrospective Trigger

Write a process/strategy retrospective only when it changes how the project should operate or prevents repeated waste. Typical triggers:

- Two or more implementation cycles hit the same friction point.
- A norm should be kept, changed, or removed based on fresh evidence.
- A blocker or near-miss exposes a systemic gap in tooling, verification, or handoff.
- A maintenance/refactor change materially alters the development operating model.

Retrospective output must include:

- What slowed throughput.
- Which norms helped/hurt.
- One concrete rule keep/change/remove decision.
- Follow-up action with issue link.

Capture the result on the linked issue by default. Use `docs/execution/templates/process-retrospective.md.tmpl` as an issue/PR comment draft or local scratch aid when a durable norm update is warranted. Do not create quota-driven standalone repo artifacts.
