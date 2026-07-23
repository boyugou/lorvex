use super::manifest::{CONTENT_TABLES, SYNC_INFRASTRUCTURE_PRESERVED};
use super::tombstones::enqueue_aggregate_root_tombstones;

pub(super) fn finalize_reset_transaction<T>(
    conn: &rusqlite::Connection,
    result: &Result<T, String>,
) -> Result<(), String> {
    // the previous implementation issued
    // `COMMIT; PRAGMA foreign_keys = ON` (or `ROLLBACK; PRAGMA …`) as
    // a single `execute_batch`. If the first statement failed, the
    // second never ran — the shared writer connection was left with
    // `foreign_keys = OFF`, silently skipping FK enforcement on every
    // subsequent write until the process restarted.
    //
    // Separate the two statements so the PRAGMA restore is
    // unconditional, then surface any PRAGMA-restore failure as a
    // distinct "connection poisoned" signal that the caller can
    // escalate (it's a strictly worse state than the original
    // commit/rollback failure).
    let outcome = match result {
        Ok(_) => conn
            .execute_batch("COMMIT")
            .map_err(|e| format!("Failed to finalize reset commit: {e}")),
        Err(error) => conn
            .execute_batch("ROLLBACK")
            .map_err(|e| format!("{error}; rollback failed: {e}")),
    };
    let pragma_outcome = conn
        .execute_batch("PRAGMA foreign_keys = ON")
        .map_err(|e| format!("CRITICAL: failed to restore foreign_keys = ON after reset: {e}"));
    match (outcome, pragma_outcome) {
        (Ok(()), Ok(())) => Ok(()),
        (Ok(()), Err(pragma_err)) => Err(pragma_err),
        (Err(tx_err), Ok(())) => Err(tx_err),
        (Err(tx_err), Err(pragma_err)) => Err(format!("{tx_err}; then {pragma_err}")),
    }
}

/// Pure DB-side reset core. Extracted from [`super::reset_all_data`] so the
/// transactional state machine (begin TX with FK off → emit per-aggregate
/// tombstones → bulk wipe → commit + restore PRAGMAs → catch_unwind
/// guard) can be exercised against a test connection without going
/// through the global `get_conn()` pool or the Tauri command dispatcher.
///
/// Returns `(tables_cleared, entities_tombstoned)`.
pub(super) fn reset_all_data_db(conn: &rusqlite::Connection) -> Result<(usize, usize), String> {
    // in dev, verify the preserved-tables list still
    // matches the live schema BEFORE we begin the wipe transaction.
    // A schema-rename that drops one of these tables would leave the
    // post-reset DB in a state where the next sync cycle has no
    // outbox to push against — silent breakage. The drift test
    // catches the case at CI time, but a debug-build user (`cargo
    // run`) gets the same protection at runtime.
    debug_assert!(
        SYNC_INFRASTRUCTURE_PRESERVED.iter().all(|table| {
            conn.query_row(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?1",
                rusqlite::params![*table],
                |_| Ok(()),
            )
            .is_ok()
        }),
        "SYNC_INFRASTRUCTURE_PRESERVED references a table that does not exist in the live schema; \
         the preserved-tables list has drifted from the schema"
    );

    // Run all deletions in a single transaction with FK disabled.
    // If any DELETE fails, the entire reset is rolled back.
    //
    // route the BEGIN IMMEDIATE (and the paired
    // `foreign_keys = OFF` pragma, which must scope to the same
    // connection as the transaction) through `with_busy_retry` so a
    // sibling MCP writer racing for the writer lock triggers the
    // standard retry+jitter loop rather than surfacing
    // `SQLITE_BUSY` directly to the user. We cannot use
    // `with_immediate_transaction` here because the helper does not
    // set `foreign_keys = OFF` before BEGIN, and the reset requires
    // FK disabled for the out-of-order DELETEs — see the panic-safety
    // comment below.
    lorvex_store::with_busy_retry(lorvex_store::DEFAULT_RETRY_BUDGET, || {
        conn.execute_batch("PRAGMA foreign_keys = OFF; BEGIN IMMEDIATE;")
    })
    .map_err(|e| format!("Failed to begin reset transaction: {e}"))?;

    // Panic-safety: we cannot reuse `with_immediate_transaction` here
    // because the reset specifically requires `foreign_keys = OFF` so
    // the out-of-order DELETEs don't trip FK constraints. That means
    // the rest of the transaction lifetime is managed by hand — and a
    // panic inside the body (e.g. allocation failure in `format!`, or
    // a panic from a future callsite change) would leave the shared
    // writer connection with an OPEN transaction AND
    // `foreign_keys = OFF`, breaking every subsequent writer until the
    // process restarts. Wrap the body in `catch_unwind`, always
    // restore both invariants before resuming, and then re-raise so
    // the crash still surfaces to the user.
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // BEFORE the bulk DELETE, walk every syncable
        // aggregate-root table and emit an `OP_DELETE` envelope per
        // row. Each envelope coalesces into `sync_outbox` and writes a
        // matching row into `sync_tombstones` (via the shared
        // `enqueue_payload_delete` core). Both tables are deliberately
        // absent from `CONTENT_TABLES` so the just-emitted state
        // survives the wipe; the next sync cycle pushes the deletes
        // to peers, who run their cascade-tombstone logic on apply to
        // sweep edges and child collections.
        let entities_tombstoned = enqueue_aggregate_root_tombstones(conn)?;

        let mut cleared = 0;
        for table in CONTENT_TABLES {
            // defense-in-depth identifier guard. Every
            // entry in `CONTENT_TABLES` is a `&'static str` literal
            // today, but a future contributor adding a dynamically-
            // sourced table name (a `format!` site is the classic
            // SQL-injection trap) would silently bypass the parser. The
            // assert refuses anything outside the strict `[A-Za-z0-9_]+`
            // alphabet so the next regression is loud, not silent.
            lorvex_domain::assert_safe_sql_identifier(table);
            // The `lists` clear is special-cased because the
            // `trg_lists_before_delete` trigger refuses to drop the
            // `inbox` sentinel (it's the canonical fallback target
            // for orphaned tasks, seeded once by migration 001 and
            // never re-seeded). Skipping `id='inbox'` matches the
            // discipline `clear_canonical_tables_for_reseed` already
            // uses for the same reason. The trigger's
            // re-home-to-inbox UPDATE is a no-op here because
            // `tasks` was already cleared earlier in CONTENT_TABLES.
            let where_clause = if *table == "lists" {
                " WHERE id != 'inbox'"
            } else {
                ""
            };
            conn.execute(&format!("DELETE FROM {table}{where_clause}"), [])
                .map_err(|e| format!("Failed to clear {table}: {e}"))?;
            cleared += 1;
        }

        Ok::<(usize, usize), String>((cleared, entities_tombstoned))
    }));

    let result = match result {
        Ok(inner) => inner,
        Err(payload) => {
            // Release the open TX and restore foreign_keys = ON
            // before surfacing the panic, otherwise the connection
            // pool is poisoned. Ignore individual errors — we're
            // already in failure mode and the SQLite state cannot
            // get worse than it is right now. Issue the
            // two statements separately so a failing ROLLBACK
            // doesn't prevent the PRAGMA restore.
            let _ = conn.execute_batch("ROLLBACK");
            let _ = conn.execute_batch("PRAGMA foreign_keys = ON");
            // Extract the panic payload's message (matching
            // `String` and `&'static str` panics that downstream
            // callers commonly produce) and return it as a typed
            // `Err`. `resume_unwind`-ing instead would let the
            // Tauri command runtime catch the panic and surface it
            // as an opaque "panic in command" error — the user
            // would get no actionable message and tests asserting
            // typed errors couldn't observe the actual failure
            // cause. The SQLite invariants are already restored
            // above, so the connection pool stays healthy.
            let message = if let Some(s) = payload.downcast_ref::<String>() {
                s.clone()
            } else if let Some(s) = payload.downcast_ref::<&'static str>() {
                (*s).to_string()
            } else {
                "reset transaction body panicked with a non-string payload".to_string()
            };
            return Err(format!("reset transaction body panicked: {message}"));
        }
    };

    finalize_reset_transaction(conn, &result)?;
    result
}
