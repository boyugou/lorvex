# CLAUDE.md — Project Instructions

This is **Lorvex**, an AI-native personal planning system. Read `../../docs/vision/DESIGN_PHILOSOPHY.md` before making any architectural decisions. See `docs/INDEX.md` for a full reading guide.
`docs/execution/` is reserved for durable governance/checklist/playbook docs; reusable templates belong under `docs/execution/templates/`; one-off evidence belongs in issue/PR comments, CI artifacts, or `artifacts/manual-gates/`. Generated facts live in `docs/reference/REPO_FACTS.md`. Repo-tracked implementation plans are deprecated; active planning belongs in issue/PR text or local scratch, and durable outcomes must be folded back into canonical docs.
For issue-state governance, use `docs/execution/ISSUE_LIFECYCLE.md` as the canonical transition and evidence standard.

**License:** Apache-2.0

---

## Tech Stack

- **Framework**: Tauri 2.x (Rust backend + React frontend)
- **UI**: React 19 + TypeScript + Tailwind CSS 4 + TanStack Query v5
- **Database**: SQLite via `rusqlite` (app + MCP runtime), shared WAL-mode DB
- **MCP Server**: Rust binary in `mcp-server/`, stdio transport via `rmcp`
- **Shared types**: `@lorvex/shared` workspace package (TypeScript types)
- **Package manager**: Use `npm` (workspace monorepo)
- **Python**: Use `uv` if any Python scripts are needed
- **No embedded AI runtime in the app.** No Anthropic SDK, no in-app model, no app-owned AI orchestration. Lorvex is a task manager + MCP server; intelligence comes from external MCP-capable assistant clients.

## Project Structure

High-level layout (see `docs/reference/REPO_FACTS.md` for live counts; use `Glob` to enumerate files in a crate; per-crate paths change faster than this doc can track):

```
lorvex/
├── shared/                 # @lorvex/shared — TypeScript types mirroring the SQLite schema
├── lorvex-domain/          # Pure domain logic (no unconditional IO/storage deps; feature-gated
│                             rusqlite typed-id SQL bindings): HLC, naming constants, merge rules,
│                             query predicates, tag normalization, FTS sanitization, timezone math,
│                             calendar/habit/memory/preference/recurrence types, validation
├── lorvex-sync-payload/    # Forward-compat sync payload primitives (depends on domain):
│                             payload_shadow (sync_payload_shadow CRUD + LWW
│                             merge/redirect) and attendee_shadow
│                             (calendar_event_attendee_shadow CRUD). Sits below
│                             store + sync so both can consume these types
│                             without forming a cycle (#4350).
├── lorvex-store/           # SQLite storage (depends on domain + sync-payload + rusqlite):
│                             connection + pool, migration (single consolidated schema;
│                             see schema/README), repositories, blob storage + fetch queue,
│                             FTS projection, export/import, calendar timeline, checklists,
│                             task ownership repair, per-entity payload_loaders
│                             (canonical JSON-row builders consumed by workflow
│                             mutations + sync enqueue paths)
├── lorvex-workflow/        # Cross-surface workflow operations (depends on domain + store):
│                             changelog, lifecycle, task_deferral, recurrence_config,
│                             habit_reminder_ops, status_side_effects, memory_ops, reseed,
│                             dependency_validation, task_enrichment, note_summary,
│                             timezone, calendar_event/ (per-concern subtree:
│                             create, update, load, attendees, recurrence_skeleton),
│                             calendar_subscription, calendar_normalization,
│                             calendar_recurrence_scope, daily_review_date,
│                             list_reorganize, overview, reminder_anchor,
│                             weekly_review, mutation + mutation_extras (canonical
│                             mutation executor + flush trait every surface drives),
│                             and the task_* family — task_create/ (subtree:
│                             input, wire, prepared, advice, date_parse,
│                             orchestrator, effects, child_inserts), task_update/
│                             (subtree: input/effects/...), task_response,
│                             task_archive, task_permanent_delete, task_checklist,
│                             task_recurrence, task_reminders, task_ai_notes,
│                             task_bookkeeping,
│                             task_batch_create, task_batch_cancel, task_batch_update,
│                             task_lifecycle_undo — owns the canonical SQL mutations +
│                             business rules every consumer surface (mcp, app, cli,
│                             sync apply) shares
├── lorvex-sync/            # Sync protocol layer (depends on domain + sync-payload + store):
│                             envelope wire format, outbox + coalesce + enqueue,
│                             tombstone CRUD + redirect, conflict log, pending FK-retry inbox,
│                             apply/ pipeline (aggregate, edge, child, day_scoped, tag, blob),
│                             canonicalization, version_stamp, retention,
│                             payload_build/aggregate (canonical envelope composition
│                             for the four aggregate roots that embed materialized
│                             child rows: current_focus, focus_schedule, daily_review,
│                             calendar_event)
├── lorvex-runtime/         # Shared operating model (DB locator, device identity, sync leases,
│                             MCP host authority, capability profiles, local_change_seq)
├── lorvex-cli/             # Agent-first CLI (thin main.rs + commands/ handlers)
├── lorvex-mcp-derive/      # Internal proc-macro crate (#3373): derive macros backing
│                             mcp-server contract validation. Pure compile-time codegen
│                             (`proc-macro = true`); no runtime surface, single consumer
│                             (`mcp-server`).
├── mcp-server/             # Rust MCP server (stdio): top-level lib.rs / main.rs entry +
│                             contract.rs + contract_validate.rs (arg/response shapes),
│                             db.rs / error.rs / json_row.rs / public_api.rs / time.rs
│                             helpers, and per-domain folder subtrees (calendar/,
│                             contract/, db/, focus/, habits/, lists/, memory/,
│                             preferences/, query/, reviews/, runtime/,
│                             server/, shutdown/, system/, tasks/, workflow/) — each
│                             owning its handlers via a sibling `router.rs` (workflow
│                             further splits into `workflow/router/<topic>.rs` per-area
│                             siblings). Flat-tree consolidation completed in #3370.
│                             bin/ runtime output.
├── scripts/                # build + verify + manual-gate runners (see scripts/README.md)
├── skill/                  # OpenClaw / ClawHub skill bundle (workflow guidance + tool reference)
├── app/                    # Tauri 2 desktop app
│   ├── src/                # React 19 + TS frontend — main.tsx, App.tsx, index.css,
│   │                         lib/ (ipc, hooks, platform, i18n, sync, theme, tasks, ...),
│   │                         components/ (view entry points + domain folders: today-view,
│   │                         task-detail, calendar, quick-capture, settings, ...)
│   └── src-tauri/          # Rust backend — lib.rs (builder + handlers), commands/ (IPC tree),
│                             hlc, invariants, platform/ (biometrics, badge, spotlight,
│                             notification_actions, native-calendar per OS, window mgmt)
├── docs/                   # Vision, design, execution governance, setup guides, archive
├── CLAUDE.md               # Agent instructions (this file)
├── CONTRIBUTING.md         # Coding standards + verification commands
├── README.md               # Project overview
├── ROADMAP.md              # Current status + next work
└── LICENSE                 # Apache-2.0
```

Canonical mutable repo counts are generated in `docs/reference/REPO_FACTS.md` (regenerate via `npm run docs:repo-facts`). When working in a specific crate, use `Glob` to list its current file inventory — paths change faster than this doc can track.

## Core Design Rules

1. **AI-first, not human-first.** The MCP server is the primary write interface. The UI is primarily a read interface with minimal human actions.
2. **Every MCP write operation must log to `ai_changelog`.** No exceptions.
3. **The conversation with the AI is the review layer.** Tasks are created directly with `open` status. The AI assistant and user discuss intent in conversation before creating tasks. The Inbox UI/review surface has been removed — the schema-seeded `inbox` default list ID remains only as a bootstrap/default-routing artifact (still referenced from schema seeds, default-list routing, and historical setup docs); it is not a review queue or product surface.
4. **Tasks sort by the canonical key `priority_effective ASC, due_date ASC NULLS LAST, id ASC`.** Per-view subsorts (today pool, weekly review, high-priority undated) extend this clause when the view's user expectation demands a different leading axis. See `docs/design/DATA_MODEL.md` → "Sort Keys" for the full catalog and the rule for adding new divergences. The AI manages priority dynamically — no computed urgency formula.
5. **Rich return values from MCP tools.** Every write operation returns the complete updated object(s). Never `{success: true}`.
6. **`ai_notes` is AI-only.** Visually distinct in UI, not human-editable.
7. **Duration estimation is important.** It enables scheduling.
8. **UI/UX quality over code minimalism.** For user-facing design work, never optimize for the shortest or simplest code. Invest extra code, extra components, extra polish — animations, spacing, visual hierarchy, ergonomic interactions — whenever it produces a better human experience. Code brevity is a virtue in backend logic; in UI, the virtue is how it looks and feels.
9. **All contact paths route through GitHub. Permanent policy — Lorvex has no email mailbox and will not provision one.** No `security@`, `conduct@`, `contact@`, or any other `@lorvex.app` address exists or is planned. Every contact-bearing doc (SECURITY.md, SUPPORT.md, CODE_OF_CONDUCT.md, README, in-app help, App Store copy, footer text, error-toast escalation prompts, anywhere) must route to GitHub: private security advisories for security/conduct, public issue templates for bugs/features/questions. Do NOT introduce or reintroduce any `@lorvex.app` email reference — there is no future inbox waiting in the wings, so any email reference is a permanent dead contact path.

---

## Coding Standards

See `CONTRIBUTING.md` for coding standards, naming conventions, and verification commands.

---

## Development Workflow

**止于至善 — Pursue perfection ceaselessly.** Every improvement is worth making. Version numbers are for release tracking only — they never justify deferring work.

### Principles

1. **Be fully autonomous.** Analyze, decide, execute. Only pause for truly irreversible high-risk decisions.
2. **Think deeply before building.** Deliberation > execution. Trace through every use case before deciding.
3. **Quality over velocity.** Getting the foundation right matters more than shipping fast.
4. **Go deep.** Every analysis must trace all code paths, sync implications, and edge cases.
5. **Push back.** Have agency. Don't blindly agree.
6. **Search docs before implementing unfamiliar APIs.** Tauri v2 → v2.tauri.app; Tailwind 4 → tailwindcss.com; objc2 → docs.rs. Use `context7` MCP tool when available.
7. **Eliminate redundancy.** Remove duplicate code paths, stale abstractions, dead code.
8. **Record ALL issues in GitHub.** No severity filter. Don't rely on memory or TODO comments.
9. **Self-review every implementation.** Two passes before committing: (1) bugs/typos, (2) dead code/stale comments.
10. **i18n is mandatory.** All user-visible strings need keys in the source locale `app/src/locales/en.json` and every strict-parity locale enforced by `npm run verify:i18n` (the per-locale JSON catalogs are the source of truth). `types.generated.ts` is codegen output from `npm run codegen:locale-types`; the other `.ts` files in `app/src/locales/` (`registry.ts`, `runtime.ts`, `index.ts`) are hand-written.
11. **Never take shortcuts.** Always pursue the most comprehensive, thorough, and optimal solution — never the simplest or safest. When fixing a bug, also clean up all related dead code, stale state, and unused imports. When refactoring, go all the way — don't stop halfway because the diff is getting large. The amount of code changed is irrelevant; what matters is the result.
12. **Current pre-public-release schema policy: no backward compatibility.** Never preserve pre-public-release schema/runtime drift. Always pursue the cleanest, most optimal solution. Freely rename, restructure, delete, and rewrite without compatibility shims, re-exports, or migration paths. Version numbers are release labels, not current data-format promises. Future post-public-release compatibility guarantees require an explicit accepted policy and numbered migrations.
13. **Always push after commit.** Push to remote immediately after every `git commit`. Never let commits accumulate locally.

### Before Starting Work

1. Read `ROADMAP.md` "In Progress" section and recent commits (`git log --oneline -30`).
2. Check open GitHub issues (`gh issue list --state open`).
3. Read the FULL issue thread before acting (`gh issue view <number> --comments`).
4. Every non-trivial implementation must map to a GitHub issue.

### Execution Priority

Rank by: correctness risk > user trust > UX quality > maintenance leverage.

### Issue Closure Rules (MANDATORY)

These rules are non-negotiable.

1. **NEVER close an issue unless EVERY criterion is met with verifiable evidence.** The agent cannot decide an issue is "not worth doing" or "post-1.0."
2. **NEVER defer work based on version numbers or milestones.** Every open issue is work that should be done.
3. **If incomplete, leave OPEN.** Comment with progress. Create tracking issues for remaining work.
4. **Cite specific commit hashes when closing.** No commit reference = not done.
5. **NEVER fabricate commit hashes.**

### After Completing Work

1. Update `ROADMAP.md` and `docs/design/FEATURES.md` status tags.
2. Run the full verification command set from
   [`CONTRIBUTING.md` → "Verification Commands"](CONTRIBUTING.md#verification-commands).
   The canonical list there covers every workspace crate, the MCP harness,
   the runtime bundle, the repo-governance bundle, and the desktop app —
   in roughly the right order for a clean local pass.
3. Commit with descriptive message. Push.

### Common Pitfalls

- **Dynamic Tailwind classes don't work.** Use static lookup maps.
- **`border-border` is not valid.** Use `border-surface-3`.
- **Rust commands are wired in ONE place:** the `#[tauri::command]` definition itself. The `generate_handler![]` list in `lib.rs` is auto-generated by `app/src-tauri/build.rs` (#3315) — never hand-edit it.
- **IPC must be typed in TWO places:** the Rust command signature and the `ipc.ts` wrapper. Components consume `ipc.ts` and aren't a separate wiring step.
- **Schema changes must trace through ALL paths:** MCP server, Tauri app, TypeScript types, sync apply, tests.
- **Frontend imports use the `@/*` path alias** (introduced in #3449) — `@/` maps to `app/src/` (wired in `app/tsconfig.json` paths and `app/vite.config.ts` resolve.alias). Prefer `@/lib/...` / `@/components/...` over deep relative paths; short within-folder relative imports (`./types`) remain idiomatic.
- **CSS custom properties have a canonical catalog.** Every new `--token` belongs in [`docs/design/DESIGN_TOKENS.md`](docs/design/DESIGN_TOKENS.md) — name, role, when to use, when not. The catalog is the contract; an undocumented token drifts on the next theme retune.

### Subagent Dispatch

1. One issue, one bounded objective per subagent.
2. No opportunistic follow-on work. Stop and return after the task.
3. Controller owns acceptance review. Never auto-accept subagent output.

### Post-Implementation Verification (MANDATORY)

After every fix or implementation, launch a dedicated reviewer subagent to:
1. **Verify completeness:** Has the fix been fully and correctly applied across all affected surfaces?
2. **Check related code:** Are there similar, related, or adjacent code paths that have the same problem?
3. **File new issues:** If the reviewer finds any new issues (even in unrelated code), create GitHub issues immediately.

This is non-negotiable. No fix is considered done until a fresh reviewer confirms it.

### Continuous Review Loop

When all issues seem done, cycle through: code reading, UX simplification, dead code scan, type consistency, sync completeness, i18n/a11y, security, documentation freshness, feature ideation.

---

## Key Documents

See `docs/INDEX.md` for the full reading guide.

**Start here:** `ROADMAP.md` (current status + what to work on next)
**Vision:** `docs/vision/VISION.md`, `../../docs/vision/DESIGN_PHILOSOPHY.md`
**Technical:** `docs/design/ARCHITECTURE.md`, `docs/design/DATA_MODEL.md`, `docs/design/FEATURES.md`
**Operations:** `../../docs/design/AI_OPERATING_MODEL.md`, `docs/design/COMMAND_PALETTE.md`

---

## Building a DMG (Notarized)

**IMPORTANT: Distribution DMGs MUST be signed and notarized.** Without notarization, macOS Gatekeeper blocks the app on other people's machines ("Move to Trash" dialog, or app won't launch even after allowing in System Settings). Unsigned local smoke-test DMGs are allowed only for same-machine packaging validation and must not be distributed.

**CI release trigger boundary:** Ordinary branch pushes do not package or publish, and `main` pushes run verification only. Release packaging and publishing are opt-in through protected release tags (`v*`, `mac-v*`) or explicit GitHub Actions manual dispatch with `release_mode` set to `dry-run`, `artifacts`, or `publish`; see `docs/execution/CI_RELEASE_TRIGGER_POLICY.md` and `docs/design/DISTRIBUTION.md`.

**Setup:** Copy `.env.build.example` or create `.env.build` in the repo root (this file is gitignored):

```bash
# .env.build — Apple code signing + notarization credentials
export APPLE_SIGNING_IDENTITY="$APPLE_SIGNING_IDENTITY"   # SHA-1 hash of your Developer ID certificate
export APPLE_ID="$APPLE_ID"                                 # Your Apple ID email
export APPLE_PASSWORD="$APPLE_PASSWORD"                     # App-specific password (appleid.apple.com → App-Specific Passwords)
export APPLE_TEAM_ID="$APPLE_TEAM_ID"                       # Your Apple Developer Team ID
```

**Build:**

```bash
# The build script sources .env.build automatically if present.
# Without credentials, it produces an unsigned DMG (fine for local testing).
bash scripts/build_dmg.sh

# Output: app/src-tauri/target/universal-apple-darwin/release/bundle/dmg/Lorvex_<version>_universal.dmg
```

**Prerequisites:** Rust toolchain, Node.js, npm install completed. The build script creates a Universal Binary (aarch64 + x86_64) and uses `lipo` to combine them.

The Tauri macOS build is a Developer ID developer/reference build. Do not add App Store, iCloud/CloudKit, or iOS/iPadOS provisioning requirements back to this tree; those belong to the Swift app under `apps/apple`.

**Common failure:** If `build_dmg.sh` fails, retry — it can be a transient disk/signing issue. Check that no Lorvex.app process is running (it locks the bundle directory).

## Building a Windows Installer (Signed)

Windows builds produce an NSIS installer (`.exe`). Without Authenticode signing, Windows SmartScreen will warn users when they run the installer.

**Setup:** For local Windows signing, either install the Authenticode
certificate into the Windows certificate store and add its SHA-1 thumbprint to
`.env.build`, or point `.env.build` at a password-protected PFX file/base64 PFX
so the build helper can import it temporarily:

```bash
# Windows code signing (Authenticode)
export WINDOWS_CERTIFICATE_THUMBPRINT=""  # SHA-1 thumbprint of the installed Authenticode certificate
export WINDOWS_CERTIFICATE_FILE=""        # Optional local .pfx path; alternative to pre-installed store cert
export WINDOWS_CERTIFICATE=""             # Optional base64 .pfx; alternative to WINDOWS_CERTIFICATE_FILE
export WINDOWS_CERTIFICATE_PASSWORD=""    # Required when WINDOWS_CERTIFICATE_FILE or WINDOWS_CERTIFICATE is set
```

**Config:** `app/src-tauri/tauri.conf.json` already has `digestAlgorithm` and `timestampUrl` configured under `bundle.windows`. Keep the committed `certificateThumbprint` value unset; the local build helper injects the thumbprint only for the duration of the build and restores the config on exit.

**Build:**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1 -Bundle nsis
# Output: app/src-tauri/target/release/bundle/nsis/Lorvex_<version>_x64-setup.exe
```

Manual `certificateThumbprint` edits are only a fallback for debugging the helper itself.

**CI:** The release workflow imports the PFX/base64 certificate from GitHub Secrets (`WINDOWS_CERTIFICATE`, `WINDOWS_CERTIFICATE_PASSWORD`, `WINDOWS_CERTIFICATE_THUMBPRINT`), derives the thumbprint from the imported PFX, validates it against the configured expected thumbprint, and injects the imported thumbprint into `tauri.conf.json` at build time. The local helper mirrors that behavior when `WINDOWS_CERTIFICATE_FILE` or base64 `WINDOWS_CERTIFICATE` is set: it imports the PFX into `Cert:\CurrentUser\My`, derives or validates the thumbprint, restores `tauri.conf.json`, and removes the imported certificate/private key on exit. See `docs/design/DISTRIBUTION.md` for full setup instructions.

**Prerequisites:** Rust toolchain, Node.js, npm install completed, and an Authenticode certificate (OV or EV) from a trusted CA.

## Sync Setup

The Tauri line no longer owns CloudKit/iCloud setup. The retired Tauri
CloudKit schema/container can be abandoned. Tauri currently has no active cloud
sync transport; export/import is the supported backup and transfer path. Future
non-Apple cloud providers should reuse the provider-neutral sync envelope/apply
model rather than reintroducing iCloud/CloudKit assumptions.

## MCP Server Setup

On macOS, the default shared DB path for both the MCP server and the Tauri app is `~/Library/Application Support/Lorvex/db.sqlite`.

- **Installed app users:** Open Lorvex → Settings → Assistant MCP → copy the displayed `command` and `args` into your assistant's MCP configuration.
- **Source checkout developers:** Run `npm run -w app prepare:mcp -- --debug`, then point your MCP config to `<repo>/mcp-server/bin/lorvex-mcp-server`.

See [docs/setup/ASSISTANT_MCP_SETUP.md](docs/setup/ASSISTANT_MCP_SETUP.md) for full setup instructions and a ready-to-paste prompt for your AI agent.
