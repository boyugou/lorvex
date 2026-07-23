# `commands/tasks/` — wrapper-vs-inner contract

Task lifecycle and batch commands in this subtree follow a uniform
two-layer split so the SQL body can be exercised against a
caller-supplied connection in tests while the production entry point
still runs the post-commit side effects the desktop UI depends on.

## Layering

For every public `#[tauri::command]` write in this subtree there are
(up to) three layers:

1. **Outer Tauri command** — e.g. `cancel_task`,
   `batch_complete_tasks`, `complete_task`, `defer_task`,
   `permanent_delete_task`, `purge_cancelled_tasks`. Owns IPC
   ownership of the args, opens the shared connection via
   `get_conn()`, delegates to the inner, and stringifies the
   `AppError` for the IPC boundary.

2. **`*_inner` (`fn _inner`)** — same signature minus the
   `String`-flattened error. Runs the inner-with-conn against the
   shared connection and then layers the post-commit, non-SQL side
   effects:
   - Spotlight reindex / remove (`platform::spotlight::apply_actions`)
   - Jump list refresh on Windows
   - Any other surface-only effect that must NOT run in a unit test
     against an in-memory SQLite database (because the platform layer
     would touch the user's installed indices)

   The `_inner` layer is the natural seam for the production code
   path; tests skip it.

3. **`*_with_conn_inner` / `*_with_conn`** (`pub(crate)`) — the
   transactional body. Takes `conn: &rusqlite::Connection` plus the
   command args, runs the full mutation under
   `with_immediate_transaction` (or a caller-supplied tx if already
   open), returns the rich result type. Tests invoke this layer
   directly against an in-memory database; production code reaches
   it only via the matching `_inner`.

   The boundary is exactly "no platform side effects" — the inner
   may still emit event-bus messages, since those are dispatched by
   the per-row mutation executor inside the transaction body, not by
   the wrapper.

## Why split this way

- Spotlight / Jump List APIs require a real OS surface and would
  panic or no-op unhelpfully in unit tests.
- Tests need to drive the SQL body against a fresh in-memory
  connection and assert on the returned rows; threading the
  connection through is cheaper than mocking the platform layer.
- Some inner layers (notably `batch_complete_tasks_with_conn_inner`
  and `complete_task_with_conn_inner`) also return the set of
  task IDs that should be removed from Spotlight, so the outer
  `_inner` is the only place that needs to know about the
  Spotlight action — the SQL layer stays platform-agnostic.

## Members

The following pairs follow this contract today:

| Outer command                 | Inner (no side effects)                     |
|------------------------------|---------------------------------------------|
| `batch_cancel_tasks`          | `batch_cancel_tasks_with_conn`              |
| `batch_complete_tasks`        | `batch_complete_tasks_with_conn_inner`      |
| `batch_move_tasks`            | `batch_move_tasks_with_conn`                |
| `batch_defer_tasks`           | `batch_defer_tasks_with_conn`               |
| `batch_reopen_tasks`          | `batch_reopen_tasks_with_conn`              |
| `defer_task` / `defer_task_until` / `reset_task_deferral` / `restore_task_deferral` | `*_with_conn` |
| `cancel_task`                 | `cancel_task_with_conn`                     |
| `purge_cancelled_tasks`       | `purge_cancelled_tasks_with_conn`           |
| `permanent_delete_task`       | `permanent_delete_task_with_conn`           |
| `complete_task`               | `complete_task_with_conn_inner`             |
