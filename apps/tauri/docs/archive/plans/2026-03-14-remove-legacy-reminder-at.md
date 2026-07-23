# Remove Legacy `reminder_at` Column — Implementation Plan

> Archived historical document. Preserved for reference only; not part of the current implementation contract.


> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the legacy `tasks.reminder_at` column and all backward-compatibility shims, making `task_reminders` table the single canonical reminder model.

**Architecture:** The `reminder_at` column was the original single-reminder field (migration 001). Migration 012 added the `task_reminders` table for multi-reminder support. Currently both paths are written to simultaneously via a compatibility bridge. This plan removes the legacy column, the bridge, and all references — making `task_reminders` the sole source of truth.

**Tech Stack:** Rust (MCP server + Tauri backend), TypeScript (frontend types), SQLite migrations

**Rationale:** CLAUDE.md norm 10: "Do not preserve backward compatibility, compatibility shims, or legacy behavior unless a current product/runtime requirement explicitly demands it." Alpha stage — no external users depending on the field.

---

## Task 1: Migration 019 — Drop `reminder_at` column

**Files:**
- Create: `db/migrations/019_remove_reminder_at.sql`
- Modify: `mcp-server/src/db/migrations.rs`
- Modify: `app/src-tauri/src/db.rs` (or `db/migrations.rs`)
- Modify: `app/src-tauri/src/commands/tests/mod.rs`

- [ ] **Step 1:** Create migration SQL
  ```sql
  -- Migration 019: Remove legacy reminder_at column from tasks table.
  -- The task_reminders table (migration 012) is the canonical reminder model.
  -- The reminder_at column was a backward-compatibility shim that is no longer needed.
  ALTER TABLE tasks DROP COLUMN reminder_at;
  -- Drop the partial index on the removed column (migration 003).
  DROP INDEX IF EXISTS idx_tasks_reminder_at;
  ```

- [ ] **Step 2:** Add migration to MCP server runner (`mcp-server/src/db/migrations.rs`)
  - Add conditional: `if table_has_column(conn, "tasks", "reminder_at")? { execute migration 019 }`
  - Also drop index if exists

- [ ] **Step 3:** Add migration to Tauri app runner (`app/src-tauri/src/db.rs` or `db/migrations.rs`)
  - Same conditional pattern

- [ ] **Step 4:** Add migration to test setup (`app/src-tauri/src/commands/tests/mod.rs`)

- [ ] **Step 5:** Verify: `cargo test --manifest-path mcp-server/Cargo.toml`
- [ ] **Step 6:** Verify: `cargo test --manifest-path app/src-tauri/Cargo.toml`
- [ ] **Step 7:** Commit

## Task 2: Remove from MCP server contracts and write paths

**Files:**
- Modify: `mcp-server/src/server_contract/task.rs` — remove `reminder_at` from `CreateTaskArgs`, `UpdateTaskArgs`, `BatchUpdateTaskPatch`
- Modify: `mcp-server/src/server_task_mutations/shared/draft.rs` — remove `reminder_at` field from `TaskInsertDraft`
- Modify: `mcp-server/src/server_task_mutations/shared/prepared.rs` — remove from INSERT SQL and params
- Modify: `mcp-server/src/server_task_mutations/create.rs` — remove `legacy_reminder_at` parameter from `insert_task_reminders()`
- Modify: `mcp-server/src/server_task_mutations/update/patch.rs` — remove `reminder_at` from update SQL builder
- Modify: `mcp-server/src/server_task_batch/update/patch.rs` — remove `reminder_at` from batch update

- [ ] **Step 1:** Remove `reminder_at` field from `CreateTaskArgs` struct
- [ ] **Step 2:** Remove `reminder_at` field from `UpdateTaskArgs` struct
- [ ] **Step 3:** Remove `reminder_at` field from `BatchUpdateTaskPatch` struct
- [ ] **Step 4:** Remove `reminder_at` from `TaskInsertDraft` and both `From` impls
- [ ] **Step 5:** Remove `reminder_at` from `prepare_task_insert()` SQL and params
- [ ] **Step 6:** Simplify `insert_task_reminders()` — remove `legacy_reminder_at` parameter, only accept `reminders`
- [ ] **Step 7:** Remove `reminder_at` from update patch builder
- [ ] **Step 8:** Remove `reminder_at` from batch update patch builder
- [ ] **Step 9:** Verify: `cargo check --manifest-path mcp-server/Cargo.toml`
- [ ] **Step 10:** Verify: `cargo clippy --manifest-path mcp-server/Cargo.toml -- -D warnings`
- [ ] **Step 11:** Commit

## Task 3: Remove compatibility bridge in set_reminders

**Files:**
- Modify: `mcp-server/src/server_task_lifecycle/writes/set_reminders.rs` — remove the UPDATE tasks SET reminder_at bridge

- [ ] **Step 1:** Remove the backward-compat UPDATE statement and its comment
- [ ] **Step 2:** Verify: `cargo test --manifest-path mcp-server/Cargo.toml`
- [ ] **Step 3:** Commit

## Task 4: Remove from recurrence spawn and duplicate

**Files:**
- Modify: `mcp-server/src/server_task_recurrence/spawn.rs` — remove `reminder_at` from spawned task copy
- Modify: `mcp-server/src/server_task_lifecycle/writes/duplicate.rs` — remove `reminder_at` from INSERT SELECT

- [ ] **Step 1:** Remove `reminder_at` from recurrence spawn INSERT
- [ ] **Step 2:** Remove `reminder_at` from duplicate INSERT SELECT
- [ ] **Step 3:** Verify: `cargo test --manifest-path mcp-server/Cargo.toml`
- [ ] **Step 4:** Commit

## Task 5: Remove from import

**Files:**
- Modify: `mcp-server/src/server_import/work_items.rs` — remove `reminder_at` from bulk task import

- [ ] **Step 1:** Remove `reminder_at` from import INSERT and field list
- [ ] **Step 2:** Verify: `cargo test --manifest-path mcp-server/Cargo.toml`
- [ ] **Step 3:** Verify: `npm run test:mcp:integration` (import/export roundtrip test)
- [ ] **Step 4:** Commit

## Task 6: Remove from Tauri backend

**Files:**
- Modify: `app/src-tauri/src/commands/shared/models.rs` — remove from Task struct
- Modify: `app/src-tauri/src/commands/shared/constants.rs` — remove from TASK_COLS
- Modify: `app/src-tauri/src/commands/shared/task_rows.rs` — remove from row extraction
- Modify: `app/src-tauri/src/commands/task_commands/updates.rs` — remove from UPDATABLE_TASK_FIELDS
- Modify: `app/src-tauri/src/commands/sync_apply/task.rs` — remove from sync apply
- Modify: `app/src-tauri/src/commands/data_snapshot/export.rs` — remove from snapshot export
- Modify: `app/src-tauri/src/commands/data_snapshot/import/lists_tasks.rs` — remove from snapshot import

- [ ] **Step 1-7:** Remove `reminder_at` from each file
- [ ] **Step 8:** Verify: `cargo check --manifest-path app/src-tauri/Cargo.toml`
- [ ] **Step 9:** Verify: `cargo clippy --manifest-path app/src-tauri/Cargo.toml -- -D warnings`
- [ ] **Step 10:** Verify: `cargo test --manifest-path app/src-tauri/Cargo.toml`
- [ ] **Step 11:** Commit

## Task 7: Remove from TypeScript types

**Files:**
- Modify: `shared/src/types.ts` — remove from Task type (if present)
- Modify: `app/src/lib/ipc/tasks/models.ts` — remove `reminder_at` from Task interface

- [ ] **Step 1:** Remove from shared types
- [ ] **Step 2:** Remove from frontend types
- [ ] **Step 3:** Verify: `cd app && npx tsc --noEmit`
- [ ] **Step 4:** Commit

## Task 8: Update MCP tool contract fixture and integration tests

- [ ] **Step 1:** Regenerate MCP tool contract fixture: `npm run generate:mcp-tool-fixture`
- [ ] **Step 2:** Verify: `npm run test:mcp:integration`
- [ ] **Step 3:** Verify: `npm run test:mcp:migrations`
- [ ] **Step 4:** Commit

## Task 9: Update documentation

**Files:**
- Modify: `docs/design/DATA_MODEL.md` — remove `reminder_at` from schema docs
- Modify: `docs/design/MCP_TOOLS.md` — remove from create_task parameters
- Modify: `docs/design/FEATURES.md` — update reminder model description

- [ ] **Step 1:** Update DATA_MODEL.md schema listing
- [ ] **Step 2:** Update MCP_TOOLS.md tool parameters
- [ ] **Step 3:** Verify: `npm run verify:markdown-links`
- [ ] **Step 4:** Commit

## Task 10: Final verification

- [ ] **Step 1:** Run full verification suite:
  ```bash
  cd app && npx tsc --noEmit
  cargo clippy --manifest-path mcp-server/Cargo.toml -- -D warnings
  cargo clippy --manifest-path app/src-tauri/Cargo.toml -- -D warnings
  cargo test --manifest-path mcp-server/Cargo.toml
  cargo test --manifest-path app/src-tauri/Cargo.toml
  npm run test:mcp:integration
  npm run test:mcp:migrations
  npm run verify:repo-governance
  ```
- [ ] **Step 2:** Update issue #701 with final resolution
- [ ] **Step 3:** Final commit and push
