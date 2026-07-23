# Contributing to Lorvex

Thank you for your interest in contributing to Lorvex! This guide covers how to set up your development environment, our coding standards, and the contribution process.

## Development Setup

### Prerequisites

- macOS 14+ (Sonoma or later), Windows 10+, or Linux
- Node.js 22+ (`engines: ">=22 <27"` in `package.json`) and npm 10+
- Rust 1.86+ (workspace MSRV pinned in `Cargo.toml`; install via [rustup.rs](https://rustup.rs))
- Xcode Command Line Tools (macOS): `xcode-select --install`

### Getting Started

```bash
git clone https://github.com/boyugou/ai-native-todo.git lorvex
cd lorvex
npm ci
```

### Running in Development

```bash
npm run -w app tauri:dev
```

The one-click install scripts under `scripts/update_and_install*` are only for local install smoke or packaging smoke from a source checkout. They are not the default inner development loop.
Top-level files in `scripts/` are human-facing entrypoints only. Internal automation is organized under `scripts/generate/`, `scripts/lib/`, `scripts/manual-gate/`, `scripts/mcp/`, `scripts/release/`, and `scripts/verify/`; non-entrypoint data fixtures live under `scripts/fixtures/`. Prefer the canonical `npm run ...` commands over calling `.mjs` files directly.

### Preparing the Local MCP Runtime (source checkout MCP testing)

```bash
npm run -w app prepare:mcp -- --debug
```

### Verification Overview

The generated **Verification Commands** section below is the canonical
completion matrix. During iteration, run the smallest focused test that covers
your change, then run the relevant generated matrix slice before submitting.
Use `npm run verify:ci-typecheck` as the default TypeScript/static gate; it
expands through `npm run verify:repo-governance` plus the frontend static
contracts and MCP harness typecheck.

### MCP Integration Tests

```bash
npm run test:mcp:integration
```

Run all checks before submitting a PR.

Documentation governance references:
- `docs/reference/REPO_FACTS.md` (generated mutable inventory facts)
- `docs/execution/templates/` (reusable execution/manual-gate templates; do not promote templates into the top-level execution reading path)
- `artifacts/manual-gates/` (gitignored home for local manual-gate evidence; do not commit one-off reports under `docs/execution/`)

## Project Structure

See `CLAUDE.md` for the full project structure. The key principle: **three thin adapter surfaces (`mcp-server`, `app/src-tauri`, `lorvex-cli`) share one SQLite database**, layered on top of the workspace crates (`lorvex-domain`, `-runtime`, `-store`, `-workflow`, `-sync`, plus the internal `lorvex-mcp-derive` proc macro and the adapter crates) with shared domain logic enforced by compiler-level crate boundaries.

### Rust Crate Architecture

```
lorvex-domain  (pure logic — no unconditional IO/storage deps; rusqlite is feature-gated for typed-id SQL bindings)
     ↑
lorvex-runtime (cross-surface runtime: DB locator, device identity, sync ownership, MCP authority)
     ↑
lorvex-store   (SQLite: migrations, repositories, blob storage, projections)
     ↑
lorvex-workflow (cross-surface workflow ops: changelog, lifecycle, task deferral,
                 recurrence config, habit reminder ops, status side effects, memory ops,
                 reseed, note_summary — shared mutation primitives every surface calls)
     ↑
lorvex-sync    (sync protocol: outbox, envelope, merge, tombstones, adapters)
     ↑         ↑         ↑
mcp-server    app/src-tauri  lorvex-cli   (thin adapters)
```

`lorvex-mcp-derive` is an internal proc-macro workspace crate used by
`mcp-server` contract validation at compile time; it has no runtime surface.

The flow is `store → workflow → {mcp, app, cli, sync apply}`: storage primitives stay in `lorvex-store`, but any mutation that must enforce shared business rules (validation, status side-effects, changelog logging, version stamping) goes through `lorvex-workflow` so every surface stays convergent.

| Crate | Responsibility | Key Rule |
|-------|---------------|----------|
| `lorvex-domain` | Entity types, validation, HLC, merge policy, canonical naming, query predicates | **No unconditional IO/storage deps**; `rusqlite` is allowed only behind the existing `rusqlite` feature for typed-id SQL bindings |
| `lorvex-runtime` | DB path resolution, device identity, local change sequence, sync ownership leases, MCP host authority | Shared operating model for both App and CLI |
| `lorvex-store` | SQLite connection, migration framework, shared repositories, blob filesystem, projection maintenance | Repositories accept `&Connection`, not `&Mutex<Connection>` |
| `lorvex-workflow` | Cross-surface workflow operations: changelog, task lifecycle, deferral, recurrence config, habit reminder ops, status side effects, memory ops, reseed, note_summary | Owns the canonical SQL mutations + business rules every consumer surface must share |
| `lorvex-sync` | Sync outbox, envelope format, tombstones, conflict log, pending inbox, apply pipeline, payload canonicalization | All write operations enqueue to `sync_outbox` via coalesced enqueue helper |
| `lorvex-mcp-derive` | Internal proc-macro crate for MCP contract validation derives | Compile-time codegen only; no runtime surface |
| `lorvex-cli` | Agent-first CLI companion: queries, mutations, TUI, MCP install, setup/doctor | Delegates to store/workflow/sync/runtime; typed `CliError` enum |
| `mcp-server` | MCP tool router, AI-facing parameter parsing + response formatting | No business logic — delegates to store repositories and workflow ops |
| `app/src-tauri` | Tauri IPC commands, platform modules, UI-facing formatting | No business logic — delegates to store repositories and workflow ops |

### All Codebases

| Codebase | Language | Role |
|----------|----------|------|
| `app/src/` | React + TypeScript | UI dashboard (read-heavy) |
| `app/src-tauri/src/` | Rust | IPC commands, DB access for the UI |
| `mcp-server/src/` | Rust | AI write interface (assistant clients connect here via MCP) |
| `scripts/tests/contracts/` | Node test + fixtures | Contract suites for docs, workflow, platform, and UI/runtime static guards |
| `scripts/tests/runtime/` | Node test | Runtime/script regression tests for staging helpers |
| `scripts/tests/mcp/` | TypeScript | Black-box MCP contract/integration/benchmark harness |

## Coding Standards

### TypeScript (Frontend)

- **Functional components only.** No class components.
- **Default export for the primary component of each file.** Named exports are fine for helpers and secondary colocated components, but the repo convention for top-level component files is a primary default export.
- **One component per file** for top-level views. Small sub-components can live in the same file.
- **Use TanStack Query** for all data fetching. Never call IPC functions directly in components — go through `useQuery` / `useMutation`.
- **Use `usePreference` hook** (`app/src/lib/query/usePreference.ts`) for reading and writing single preference keys. It encapsulates the query/invalidation pattern with typed parsing helpers (`parseBool`, `parseJson`, `parseString`). Never hand-roll `useQuery(['preference', key])` + `setPreference` when `usePreference` can do it.
- **Use centralized query-key helpers** in `app/src/lib/query/queryKeys.ts` for high-traffic cache invalidation paths. Avoid ad-hoc key head variants. For invalidating 3+ query key heads at once, use `invalidateByKeyHeadSet()` to collapse into a single cache traversal instead of N separate `invalidateQueries` calls.
- **IPC wrappers in `app/src/lib/ipc/`** — every Tauri `invoke()` call must have a typed wrapper in the owning domain module (for example `tasks/queries.ts`, `tasks/mutations/lifecycle.ts`, `calendar.ts`, `settings.ts`, or `runtime.ts`). Components never call `invoke()` directly and must not import through a root IPC barrel.
- **Shared types in `app/src/lib/types.ts`** — view types and other cross-component types go here.
- **Use the `@/*` path alias for imports rooted at `app/src/`** (introduced in #3449). `import { foo } from '@/lib/i18n'` is preferred over deep relative paths like `../../../lib/i18n`. The alias is wired in both `app/tsconfig.json` (`paths`) and `app/vite.config.ts` (`resolve.alias`); short within-folder relative imports (`./types`, `./McpSetupSection.logic`) remain idiomatic.
- **Prefer Tailwind utility classes and shared tokens.** No CSS modules or styled-components; inline styles are allowed only when the value is runtime-driven or cannot be expressed with the current static utility/token contract.
- **No dynamic Tailwind classes.** `text-${color}` does not work with JIT. Use a lookup map with full static class strings instead.
- **Avoid `any`**. Use `unknown` + type narrowing if the type is genuinely uncertain.

### TypeScript (MCP Harness)

- **Keep TypeScript out of the runtime path.** `scripts/tests/mcp/` is only for black-box harnesses that spawn the Rust binary.
- **Root scripts are canonical.** Add MCP harness commands to the repo root `package.json`, not a nested package file under `mcp-server/`.
- **Prefer contract/integration coverage** over implementation-coupled unit tests for the MCP runtime.
- **Fixtures belong next to the harness** under `scripts/tests/mcp/fixtures/`.

### Scripts / Verification Layout

- **Keep human entrypoints obvious.** Shell/PowerShell files that maintainers run directly stay at the top level of `scripts/`.
- **Internal automation belongs in subdirectories.** Use `scripts/generate/`, `scripts/lib/`, `scripts/manual-gate/`, `scripts/mcp/`, `scripts/release/`, and `scripts/verify/` instead of adding more top-level `.mjs` files.
- **Fixture data belongs in `scripts/fixtures/`.** SQL seed data such as `scripts/fixtures/seed.sql` and `scripts/fixtures/seed_scale.sql` is not an executable entrypoint.
- **Contract fixtures live with the contract suite.** Static verifier fixtures belong under `scripts/tests/contracts/fixtures/`, not a shared top-level fixture dump.

### `Patch<T>` for partial updates

Partial-update payloads (PATCH-style mutations on the MCP server, IPC
commands, CLI write-ops, sync apply, and shared `*_ops` helpers) use the
`Patch<T>` enum from `lorvex-domain` (`lorvex_domain::Patch`) across
`lorvex-store`, `lorvex-cli`, `mcp-server`, `lorvex-workflow`, and the
Tauri adapters. `Patch<T>` is the single source of truth for three-state
partial-update semantics; reach for it directly.

`Patch<T>` encodes three states explicitly:

| State          | Meaning                                  | JSON wire form |
|----------------|------------------------------------------|----------------|
| `Patch::Unset` | Field absent — leave the existing value  | key omitted    |
| `Patch::Clear` | Field explicitly cleared                 | `null`         |
| `Patch::Set(v)`| Field set to `v`                         | `v`            |

Use `#[serde(default, skip_serializing_if = "Patch::is_unset")]` on every
PATCH field so missing keys round-trip as `Unset` and absent fields stay
off the wire. Never reintroduce `Option<Option<T>>` for three-state
semantics — the compiler will not stop you, but it makes call sites
ambiguous (`Some(Some(x))` vs `Some(None)`) and defeats the point of the
migration. See the module-level docs in `lorvex-domain/src/patch.rs` for
the full contract, including the `JsonSchema` impl that preserves the
historical `Optional<T> | null` shape MCP consumers expect.

### Rust (MCP Runtime)

- **One runtime only.** `mcp-server/src/` is the canonical MCP implementation; do not reintroduce a parallel TypeScript runtime path.
- **Tool handlers live in per-domain `<domain>/router.rs` modules.** After the #3370 / #3312 flat-tree refactor, every MCP tool lives in a router file owned by its domain folder (`tasks/router.rs`, `calendar/router.rs`, …; the `workflow/` domain further splits into `workflow/router/<topic>.rs` siblings). New tools are registered through the `mcp_tools! { write/read/raw … }` declarative macro (see `mcp-server/src/server/tool_macros.rs`) — do not hand-roll `#[tool(...)]` glue.
- **Every write operation must log to `ai_changelog`** and preserve existing sync/changelog invariants.
- **Rich return values.** Return complete updated object payloads, not `{ success: true }`.
- **Run `cargo check` / `cargo test`** against `mcp-server/Cargo.toml` when changing runtime behavior.

### Rust (Tauri Backend)

- **Keep the IPC command surface rooted in `commands.rs`**. Large Tauri backend domains may be split into `app/src-tauri/src/commands/` submodules, but commands should still be defined or re-exported through the `commands` module tree and follow the existing pattern `#[tauri::command] pub fn command_name(...)`.
- **Return `Result<T, String>` only at the outer Tauri command boundary**. Internal helpers should use `AppResult<T>` / `AppError`; convert typed failures at the IPC boundary with `.map_err(String::from)` or `String::from(error)` so the JSON `CommandError` string envelope from `app/src-tauri/src/error/boundary.rs` and `app/src-tauri/src/error/envelope.rs` is preserved. Do not teach or copy bare `.map_err(|e| e.to_string())` for Tauri commands; first convert non-`AppError` diagnostics into the closest `AppError` variant, then cross the IPC boundary through `String::from`.
- **Use `serde` derive macros** for all structs passed across the IPC boundary.
- **SQL in commands is fine** — we don't need an ORM layer. Use parameterized queries (`params![]`) always.
- **Command registration is generated.** The `generate_handler![]` list in `lib.rs` is auto-generated by `app/src-tauri/build.rs`; add or re-export the `#[tauri::command]` through the `commands` module tree and let the build script refresh the handler list.
- **Run `~/.cargo/bin/cargo clippy`** and fix all warnings before submitting.

### CSS / Tailwind

- **Color tokens** are defined in `app/src/index.css` (Tailwind CSS 4 `@theme` directive). Use semantic names: `text-text-primary`, `bg-surface-2`, `text-accent`, `text-danger`, `text-warning`, `text-success`.
- **Never use `border-border`**. The correct border color token is `border-surface-3`.
- **Spacing convention**: `px-8` for main content horizontal padding. `space-y-8` between sections. `space-y-1.5` between task cards.
- **Typography**: Section headers use `text-xs font-medium uppercase tracking-widest`. Body text uses `text-sm`.
- **When adding a CSS custom property**: document the new `--token` in [`docs/design/DESIGN_TOKENS.md`](docs/design/DESIGN_TOKENS.md) so the catalog stays canonical (name, role, when to use, when not). An undocumented token drifts on the next theme retune.

### Naming Conventions

| Item | Convention | Example |
|------|-----------|---------|
| React components | PascalCase | `TaskCard.tsx`, `QuickCapture.tsx` |
| TypeScript functions | camelCase | `getDailyPlan()`, `sortTasks()` |
| Rust functions | snake_case | `get_daily_plan()`, `is_setup_complete()` |
| Rust structs | PascalCase | `DailyPlanRow`, `WeeklyReview` |
| IPC command names | snake_case | `get_overview`, `quick_capture` |
| Database columns | snake_case | `due_date`, `defer_count` |
| CSS class tokens | kebab-case | `text-text-primary`, `bg-surface-2` |
| File names | PascalCase for components, camelCase for utils | `TaskCard.tsx`, `ipc.ts` |
| Commit messages | Conventional | `feat:`, `fix:`, `refactor:`, `docs:`, `chore:` |
| Branch names | kebab-case | `feat/weekly-review`, `fix/today-pool-sort` |

### Versioning

Semver labels use `MAJOR.MINOR.PATCH` and currently identify build artifacts,
release channels, and updater metadata. The current package version is not a data-format stability guarantee while Lorvex is still pre-public-release.

Current schema policy:
- Pre-release schema changes may rewrite the consolidated `001_schema.sql`
  baseline directly.
- Do not add backward-compatibility shims, re-export aliases, or migration paths
  for development-only schema drift.
- Future post-public-release compatibility guarantees must be documented as an
  explicit policy and backed by numbered migrations plus verification gates.

### TypeScript Strictness

Both `app/tsconfig.json` and `scripts/tests/mcp/tsconfig.json` enable
`noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`. Treat every array
index and record lookup as nullable until a runtime assertion has proved it
exists; use the MCP harness `requireArrayItem`, `requireRecordValue`, or
`requireValue` helpers when a test payload is expected to contain a specific row
or key. Optional properties must be omitted when absent rather than set to
`undefined`.

### Verification Commands

Run these before considering work complete:

<!-- verification-matrix:contributing:start -->
```bash
# Default CI TypeScript/static gate
npm run verify:ci-typecheck

# Frontend unit tests (CI gate)
npm run -w app test:unit

# Playwright smoke (CI gate; local for UI changes)
npm run -w app test:e2e:smoke

# Playwright visual regression (blocking CI/release gate; pinned Linux snapshots)
npm run -w app test:e2e:visual

# MCP integration harness (full/local runtime coverage)
npm run test:mcp:integration

# MCP runtime Rust coverage
npm run test:mcp:migrations
~/.cargo/bin/cargo check --manifest-path mcp-server/Cargo.toml
~/.cargo/bin/cargo clippy --manifest-path mcp-server/Cargo.toml -- -D warnings
~/.cargo/bin/cargo test --manifest-path mcp-server/Cargo.toml

# Prepared MCP runtime bundle (only when packaging/staged binary paths change)
npm run -w app prepare:mcp -- --debug
npm run verify:mcp-runtime-bundle

# Rust (desktop app)
~/.cargo/bin/cargo check --manifest-path app/src-tauri/Cargo.toml --all-targets
~/.cargo/bin/cargo clippy --manifest-path app/src-tauri/Cargo.toml --all-targets -- -D warnings
~/.cargo/bin/cargo test --manifest-path app/src-tauri/Cargo.toml

# Rust (CLI + shared crates)
~/.cargo/bin/cargo check -p lorvex-cli
~/.cargo/bin/cargo clippy -p lorvex-cli -- -D warnings
~/.cargo/bin/cargo test -p lorvex-cli
~/.cargo/bin/cargo test -p lorvex-runtime
~/.cargo/bin/cargo test -p lorvex-domain
~/.cargo/bin/cargo test -p lorvex-store
~/.cargo/bin/cargo test -p lorvex-workflow
~/.cargo/bin/cargo test -p lorvex-sync
~/.cargo/bin/cargo test -p lorvex-mcp-derive

# Full workspace (recommended before milestones)
~/.cargo/bin/cargo clippy --workspace --all-targets -- -D warnings
~/.cargo/bin/cargo test --workspace
```
<!-- verification-matrix:contributing:end -->

`npm run verify:ci-typecheck` includes `npm run verify:shellcheck`.
Local machines without `shellcheck` skip that sub-gate with an explicit warning
so lightweight checkouts still work. GitHub Actions is fail-closed: CI installs
`shellcheck` before the static gate, and a missing binary makes
`verify:shellcheck` fail instead of silently passing.

`npm run verify:ci-typecheck` also includes `npm run verify:cargo-dead-code`.
Local machines without `cargo` skip that sub-gate with an explicit warning so
frontend-only checkouts still work. GitHub Actions is fail-closed for Cargo: CI
installs Rust before the static gate, and a missing `cargo` binary makes
`verify:cargo-dead-code` fail instead of silently passing.

`npm run verify:ci-typecheck` also includes `npm run verify:cargo-machete`.
Local machines without `cargo machete` skip that sub-gate with an explicit
warning so frontend-only checkouts still work. GitHub Actions installs `cargo-machete`
before the static gate, and a missing binary makes
`verify:cargo-machete` fail instead of silently passing. Prefer deleting stale
Cargo.toml entries when the gate reports them. If cargo-machete flags a real
dependency that it cannot observe, add a narrow `[package.metadata.cargo-machete]`
`ignored = ["crate-name"]` entry in that package manifest with a nearby comment
explaining the false positive.

Note: `cargo` may not be in PATH. Use `~/.cargo/bin/cargo` or set `PATH="$HOME/.cargo/bin:$PATH"`.

## Dependency Maintenance

This repository has no automated dependency-update bot wired up; version bumps
are manual. Review release notes and use the normal verification matrix for
the touched ecosystem before merging a bump. For security-sensitive updates,
treat them as security work: inspect the advisory, keep the patch narrowly
focused, and run the relevant audit gate (`npm audit` or
`bash scripts/ci/cargo_audit_with_policy.sh`) in addition to the standard
checks.

Do not batch a security fix into a broad routine version bump unless the advisory
resolution is exactly that bump and the evidence comment links the advisory,
upstream release notes, and verification output.

## Pull Request Process

### Issue-First Workflow (Required)

Before starting non-trivial implementation:

1. Open or link a GitHub issue that defines scope and acceptance criteria.
2. Ensure the issue maps to `ROADMAP.md`. The active backlog lives in the GitHub issue tracker.
3. If scope is unclear, keep the issue in `Intake` / `Design`, add the canonical `needs-design` label, and resolve scope before coding.
4. If an actionable task originates from chat/user feedback and is non-trivial, convert it into an issue first, then implement.
5. Follow lifecycle gates in `docs/execution/ISSUE_LIFECYCLE.md` (`Intake -> Design -> Agent-ready -> In progress -> Ready for review -> Done`), including evidence requirements for each transition.

Do not run implementation from chat memory alone. The issue tracker is the task-level source of truth.

1. **Fork and create a branch** from `main`. Use descriptive branch names such as `feat/weekly-review`, `fix/focus-mode-index`, or `docs-update-readme`.

2. **Keep PRs focused.** One feature or fix per PR. If you find unrelated issues, file them separately.

3. **Run the applicable checks below before pushing.** Use the full canonical matrix above for release-sized or cross-surface changes.
   <!-- verification-matrix:contributing-pr:start -->
   ```bash
   npm run verify:ci-typecheck
   npm run -w app test:unit
   npm run -w app test:e2e:smoke
   npm run -w app test:e2e:visual
   npm run test:mcp:migrations
   npm run test:mcp:integration
   npm run -w app prepare:mcp -- --debug
   npm run verify:mcp-runtime-bundle
   ~/.cargo/bin/cargo check --manifest-path mcp-server/Cargo.toml
   ~/.cargo/bin/cargo clippy --manifest-path mcp-server/Cargo.toml -- -D warnings
   ~/.cargo/bin/cargo test --manifest-path mcp-server/Cargo.toml
   ~/.cargo/bin/cargo check --manifest-path app/src-tauri/Cargo.toml --all-targets
   ~/.cargo/bin/cargo clippy --manifest-path app/src-tauri/Cargo.toml --all-targets -- -D warnings
   ~/.cargo/bin/cargo test --manifest-path app/src-tauri/Cargo.toml
   ```
   <!-- verification-matrix:contributing-pr:end -->

   CI and release triggers are governed by
   `docs/execution/CI_RELEASE_TRIGGER_POLICY.md`. CI runs in two tiers:
   - **Fast PR checks (default):** runs on every PR update for quick feedback.
   - **Full checks (optional on PR):** add label `ci:full` to the PR to run the full matrix.
   - **Full checks (automatic):** always run on `main` pushes as verification only.
   - **Manual override:** Actions -> `CI` -> `Run workflow` and set `full_checks=true` (or `false`).
   - **Release packaging:** never runs from an ordinary `main` push. Prepare the
     appropriate release tag and dispatch the release workflow from that tag ref.

4. **Write a clear PR description** explaining what changed and why.

5. **Update docs** if your change affects architecture/API/behavior. Check `CLAUDE.md`, `ROADMAP.md`, and execution docs.
   - Documentation governance references:
     - `docs/reference/REPO_FACTS.md` (generated mutable inventory source)
   - Do not add repo-tracked dated execution docs. One-off evidence belongs in issue/PR comments, CI artifacts, or `artifacts/manual-gates/`.
   - For user-facing copy changes, run through `docs/design/COPY_GUIDELINES.md` checklist (assistant-agnostic wording + Chinese `AI 助理` rule).
6. **Close or update linked issues** in the same PR. If partial, leave explicit follow-up checklist in issue comments. In subagent workflows, this responsibility stays with the PR owner/controller, not individual worker subagents.
7. **No silent close.** Before closing an issue, add a structured conclusion comment (Outcome / What changed / Verification / Risk or follow-up issue) with `Evidence permalink` and `Commit` fields. Evidence links must point to this repository, and commit SHAs must resolve locally and be reachable from `origin/main`. Validate local close-out drafts with `npm run verify:issue-lifecycle-evidence -- --closeout-file <path>`; after posting, `npm run verify:issue-lifecycle-evidence -- --issue <number>` verifies the closed issue evidence. The bare `npm run verify:issue-lifecycle-evidence` scans recent closed issues; use `--contract-only` only for docs/sample contract checks. If any planned review is pending/timed out, resolve it or explicitly waive with rationale before close.
8. **Run post-merge sync ritual.** After merge, sync issue state/comments plus `ROADMAP.md`/feature docs as defined in `docs/execution/ISSUE_LIFECYCLE.md`.

## Commit Messages

Use conventional commit format:

```
feat: add weekly review view with stalled project detection
fix: clamp today pool sort index to prevent out-of-bounds
refactor: extract shared View type to lib/types.ts
docs: update CLAUDE.md with current component list
chore: add clippy to CI workflow
```

Prefix types: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `perf`.

## Architecture Principles

Before making changes, read `docs/vision/DESIGN_PHILOSOPHY.md`. The key principles:

1. **AI-first.** The MCP server is the primary write interface. The UI is a read-focused dashboard.
2. **Conversation is the review layer.** The AI assistant discusses task intent with the user before creating. Tasks are created directly as `open` status.
3. **Priority is AI-managed (P1-P3).** The AI sets and adjusts task priority dynamically based on context.
4. **Duration is first-class.** Every task should have a time estimate.
5. **Asymmetric configuration.** AI gets more config knobs than humans.

## Questions?

Open a GitHub issue with the concrete question/context and keep it in `Intake` / `needs-design`, or check the existing docs in `/docs`.

## Text-First Contributions

Lorvex treats high-quality issues as first-class contributions.
If you don't want to write code, detailed bug reports and feature specs are still highly valuable and can be implemented directly by coding agents.

When a PR implements your issue, maintainers should include:

- `Closes #<issue>`
- `Suggested-by: @<username>` (in PR body or commit message)
