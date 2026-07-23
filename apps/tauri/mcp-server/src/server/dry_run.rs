//! Dry-run dispatch for destructive batch tools (issue #2370).
//!
//! Branches between a committing call and a dry-run preview call: the
//! preview path runs the closure inside an always-rolled-back savepoint,
//! writes a single `<tool>_preview` row to `ai_changelog`, and merges
//! `"dry_run": true` into the response payload so the assistant can
//! programmatically detect preview output.
//!
//! See the inline doc comment on `dispatch_dry_run` for the closure
//! side-effect contract — closures must keep mutations either inside
//! SQLite (covered by the savepoint rollback) or monotonic-only in
//! process state. The
//! `dry_run_preserves_monotonic_hlc_after_rollback` regression test
//! pins the HLC half of that contract.

use rusqlite::Connection;

use super::LorvexMcpServer;

impl LorvexMcpServer {
    /// Branch between a committing call and a dry-run preview call
    /// (issue #2370 — destructive batch tools need a "plan then
    /// confirm" flow before the assistant commits).
    ///
    /// The closure returns the raw mutation JSON response. On dry-run,
    /// the helper:
    ///   1. Runs the closure inside a savepoint.
    ///   2. Rolls the savepoint back unconditionally.
    ///   3. Extracts the entity ids the mutation would have touched
    ///      from the JSON payload via `entity_ids_extractor`.
    ///   4. Writes a single `<tool>_preview` row to `ai_changelog`
    ///      (no outbox enqueue).
    ///   5. Returns the original payload with `"dry_run": true` merged
    ///      at the top level.
    ///
    /// `summary_builder` returns the action portion of the audit
    /// summary — e.g. `"delete task abc"` or `"create 3 task(s)"`.
    /// The helper prepends `"[preview] Would "` so every preview row
    /// in `ai_changelog` carries the same canonical prefix without
    /// each call site having to repeat it.
    ///
    /// # Closure side-effect contract
    ///
    /// The savepoint covers SQL writes only. Side effects that bypass
    /// SQLite — process-wide statics, connection-bound thread-locals,
    /// global counters — are NOT rolled back. Authors of dry-run-
    /// eligible closures MUST keep mutations either:
    ///
    ///   - inside SQLite (so the savepoint rollback covers them), or
    ///   - monotonic-only in process state, where surviving advances
    ///     past the rollback are harmless.
    ///
    /// Surveyed today (commit time):
    ///
    ///   - `generate_hlc_version` advances the process-wide
    ///     `HLC_STATE` mutex. The advance survives rollback, but HLC
    ///     monotonicity is preserved (the next real generate is still
    ///     strictly greater than every persisted HLC). The advance
    ///     just "wastes" some HLC numbers that were never written.
    ///     Acceptable.
    ///   - `bump_local_change_seq` writes via SQL inside the savepoint
    ///     (uses `RETURNING` against `local_counters`); the
    ///     rollback covers it. Acceptable.
    /// - The local-event observer only fires from the sync apply
    ///   pipeline, never from MCP write tools. Not reachable under
    ///   dry-run.
    ///
    /// Any future helper that writes to a process-wide static, an
    /// in-memory cache, or any non-SQLite-tracked state MUST be
    /// flagged here and either (a) made transactional via a SQLite-
    /// backed equivalent or (b) explicitly guarded against dry-run
    /// callers. The `dry_run_preserves_monotonic_hlc_after_rollback`
    /// regression test pins the HLC half of this contract.
    pub(crate) fn dispatch_dry_run<F>(
        &self,
        dry_run: bool,
        tool_name: &'static str,
        entity_type: &'static str,
        summary_builder: impl FnOnce(&serde_json::Value) -> String,
        entity_ids_extractor: impl FnOnce(&serde_json::Value) -> Vec<String>,
        f: F,
    ) -> Result<String, String>
    where
        F: FnOnce(&Connection) -> Result<String, crate::error::McpError>,
    {
        use crate::error::McpError;
        use crate::runtime::change_tracking::write_preview_audit_entry;

        if !dry_run {
            return self.with_conn_typed(f);
        }

        self.with_conn(|conn| {
            // Run the mutation inside a savepoint that ALWAYS rolls
            // back — `with_savepoint_then_rollback` from
            // `lorvex-store::transaction` covers the panic-safety +
            // unique-name + busy-retry contract that the previous
            // hand-rolled `SAVEPOINT mcp_tool_dry_run` shape lacked.
            // A panic inside `f` would have left the savepoint frame
            // dangling on the connection; the helper rolls it back
            // BEFORE the unwind resumes.
            let raw =
                lorvex_store::with_savepoint_then_rollback(conn, "mcp_dry_run", |conn| f(conn))
                    .map_err(String::from)?;

            let mut parsed: serde_json::Value = serde_json::from_str(&raw).map_err(|e| {
                String::from(McpError::Serialization(format!(
                    "dry-run response parse: {e}"
                )))
            })?;

            let summary = format!("[preview] Would {}", summary_builder(&parsed));
            let entity_ids = entity_ids_extractor(&parsed);
            write_preview_audit_entry(conn, tool_name, entity_type, &summary, &entity_ids)
                .map_err(String::from)?;

            // Merge `dry_run: true` into the top level of the
            // response so the assistant can programmatically detect
            // preview output.
            if let Some(obj) = parsed.as_object_mut() {
                obj.insert("dry_run".to_string(), serde_json::Value::Bool(true));
            } else {
                parsed = serde_json::json!({ "dry_run": true, "preview": parsed });
            }

            serde_json::to_string(&parsed).map_err(|e| {
                String::from(McpError::Serialization(format!(
                    "dry-run response encode: {e}"
                )))
            })
        })
    }
}
