//! [`ensure_database_ready`] orchestrator.
//!
//! Runs the SQL-migration step on a worker thread, blocking the main
//! thread up to [`MIGRATION_DIALOG_THRESHOLD`] before raising the
//! native progress dialog. Panics on any fatal error so the process
//! exits before Tauri builds — there is no recovery path that doesn't
//! risk silently shipping a half-migrated DB to the UI.

use crate::db;

use super::migration_gate::{
    spawn_migration_progress_dialog, wait_for_migration_with_progress, MIGRATION_DIALOG_THRESHOLD,
};
use super::migration_progress::{
    persist_migration_progress_events_best_effort, record_migration_progress_event,
    should_persist_migration_progress_events, MigrationProgressEvent,
};
use super::startup_failure::ensure_database_ready_fail;

/// Result-slot helper so the migration runner can send either an Ok or
/// a textual error across the thread boundary without dragging
/// `AppError`'s non-`Send`-able parts along.
enum MigrationOutcome {
    Ok,
    Err(String),
}

pub(crate) fn ensure_database_ready() {
    // run the pool init (which drives SQL migrations) on a
    // background thread so the main thread can surface a native
    // progress dialog after `MIGRATION_DIALOG_THRESHOLD`. `db::get_db()`
    // is idempotent — both threads call through `OnceLock::get_or_init`,
    // so only one actually runs the migration; the other blocks on the
    // cell and returns the cached result.
    let mut migration_progress_events: Vec<MigrationProgressEvent> = Vec::new();
    record_migration_progress_event(
        &mut migration_progress_events,
        "app.startup.migration.init",
        "opening database pool",
        None,
    );
    let start = std::time::Instant::now();

    let migration_result: std::sync::Arc<std::sync::Mutex<Option<MigrationOutcome>>> =
        std::sync::Arc::new(std::sync::Mutex::new(None));
    let (done_tx, done_rx) = std::sync::mpsc::channel::<()>();
    {
        let migration_result = migration_result.clone();
        let _ = std::thread::Builder::new()
            .name("lorvex-migration-runner".into())
            .spawn(move || {
                let outcome = match db::get_db() {
                    Ok(_) => MigrationOutcome::Ok,
                    Err(e) => MigrationOutcome::Err(format!("{e}")),
                };
                // Recover from poisoning rather than panicking — if
                // an earlier holder panicked, the migration result
                // mutex's inner state (Option<MigrationOutcome>) has
                // no invariants that a panic could have violated.
                // Panicking again here would mask the original error.
                *migration_result
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(outcome);
                let _ = done_tx.send(());
            });
    }

    let threshold = MIGRATION_DIALOG_THRESHOLD;
    let gate = wait_for_migration_with_progress(&done_rx, threshold, || {
        record_migration_progress_event(
            &mut migration_progress_events,
            "app.startup.migration.threshold_crossed",
            "database migration still running after threshold; raising progress dialog",
            Some(format!("threshold={threshold:?}")),
        );
        spawn_migration_progress_dialog();
    });

    let elapsed = start.elapsed();

    // symmetric poison
    // recovery with the writer site above. The
    // `done_rx`/`wait_for_migration_with_progress` join already
    // observed that the runner thread completed (or aborted), so
    // any poison flag here is collateral damage from a panic that
    // surfaced before the slot was populated. `take()` returns
    // `None` in that case and the match below maps it to a
    // graceful `MigrationOutcome::Err`-equivalent path.
    let outcome = migration_result
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take();
    match outcome {
        Some(MigrationOutcome::Ok) => {
            if should_persist_migration_progress_events(&gate) {
                record_migration_progress_event(
                    &mut migration_progress_events,
                    "app.startup.migration.complete",
                    "database migration completed after progress dialog was raised",
                    Some(format!("finished in {elapsed:?}")),
                );
                persist_migration_progress_events_best_effort(&migration_progress_events);
            }
        }
        // Migration finished with a typed error — fall through to the
        // existing fatal-dialog path. The `Err` string was captured
        // from `AppError::Display`, so `error_str.contains(...)` below
        // still matches the `[FATAL_MIGRATION_*]` prefixes injected by
        // `init_pool`.
        Some(MigrationOutcome::Err(error_str)) => {
            record_migration_progress_event(
                &mut migration_progress_events,
                "app.startup.migration.error",
                "database migration failed",
                Some(format!("failed after {elapsed:?}")),
            );
            ensure_database_ready_fail(error_str, &migration_progress_events)
        }
        None => {
            // Disconnect before send — migration thread panicked. Treat
            // the same as a hard error; the panic hook has already
            // persisted the backtrace to `error_logs`.
            record_migration_progress_event(
                &mut migration_progress_events,
                "app.startup.migration.error",
                "database migration runner terminated without a result",
                Some(format!("failed after {elapsed:?}")),
            );
            ensure_database_ready_fail(
                "migration thread terminated without producing a result (see panic log)"
                    .to_string(),
                &migration_progress_events,
            );
        }
    }
}
