# Naming System Index

This directory is the canonical naming design for Lorvex.

It exists because the codebase now has multiple naming layers that serve
different jobs:

- schema and sync entity names must stay stable
- MCP and CLI names must stay precise and machine-friendly
- app/UI copy should be human-readable
- historical tool names and docs still need compatibility handling

The goal of this directory is to prevent the same concept from drifting across
App, CLI, MCP, sync payloads, docs, and user-facing copy.

## Document Map

- [`FOUNDATIONS.md`](FOUNDATIONS.md)
  Global naming model, layer definitions, decision rules, and anti-patterns.
- [`PLANNING.md`](PLANNING.md)
  Today pool, current focus, focus schedule, reviews, briefing, rationale.
- [`TASK_SYSTEM.md`](TASK_SYSTEM.md)
  Tasks, lists, habits, statuses, priorities, projects, and removed inbox terms.
- [`AI_SURFACES.md`](AI_SURFACES.md)
  App, CLI, MCP, TUI, host vs surface, authority, setup language.
- [`MEMORY_NOTES.md`](MEMORY_NOTES.md)
  Memory, notes_for_ai, annotations, AI activity.
- [`CALENDAR_TIME.md`](CALENDAR_TIME.md)
  Canonical calendar events, provider mirrors, blocking ranges, working hours, day semantics.
- [`SYNC_RUNTIME.md`](SYNC_RUNTIME.md)
  Entity types, outbox/inbox, leases, local runtime state, authority, device identity.

## Reading Order

Recommended order:

1. `FOUNDATIONS.md`
2. `PLANNING.md`
3. `AI_SURFACES.md`
4. `SYNC_RUNTIME.md`
5. `TASK_SYSTEM.md`
6. `MEMORY_NOTES.md`
7. `CALENDAR_TIME.md`

## Primary Source Files Audited

These docs were written against actual code and current docs, not only product discussion.

- `lorvex-domain/src/naming/`
- `lorvex-domain/src/preference_keys/`
- `lorvex-domain/src/memory/`
- `lorvex-domain/src/naming/entity/`
- `lorvex-runtime/src/capabilities/mod.rs`
- `lorvex-runtime/src/local_state/mod.rs`
- `lorvex-runtime/src/mcp_authority.rs`
- `lorvex-runtime/src/sync_owner/`
- `lorvex-cli/src/cli/`
- `lorvex-cli/src/commands/`
- `lorvex-cli/src/render/`
- `lorvex-cli/src/tui/`
- `mcp-server/src/focus/current/`
- `mcp-server/src/focus/schedule/`
- `mcp-server/src/tasks/day_query/today.rs`
- `mcp-server/src/memory/`
- `mcp-server/src/system/logs/ai_changelog.rs`
- `mcp-server/src/reviews/daily/`
- `app/src-tauri/src/mcp_runtime.rs`
- `app/src-tauri/src/commands/planning/`
- `app/src-tauri/src/commands/overview.rs`
- `app/src-tauri/src/commands/reviews.rs`
- `app/src-tauri/src/commands/memory/`
- `app/src-tauri/src/commands/diagnostics/changelog.rs`
- `lorvex-store/src/calendar_timeline/queries/`
- `lorvex-store/src/schema/001_schema.sql`
- `docs/design/DATA_MODEL.md`
- `docs/design/FEATURES.md`
- `docs/design/UX.md`
- `docs/design/PER_VIEW_CONTENT_STRATEGY.md`
- `docs/design/COPY_GUIDELINES.md`
- `docs/setup/ASSISTANT_MCP_SETUP.md`

## Naming Decision Priority

When names conflict, resolve them in this order:

1. Canonical domain meaning
2. Sync/runtime stability
3. MCP/operator precision
4. User-facing clarity
5. Legacy compatibility

## Migration Rule

These docs do not require immediate schema renames.

The default migration strategy is:

- keep canonical entity/table names stable
- improve UI copy first
- improve MCP descriptions second
- add compatibility aliases only when needed
- only rename schema/runtime identifiers if the existing canonical term is truly wrong
