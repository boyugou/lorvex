//! Unit tests for the #2493 migration-progress threshold gate. These
//! tests exercise [`wait_for_migration_with_progress`] directly so we
//! don't have to drive a real SQL migration — the gate's only job
//! is to raise a callback after N milliseconds of silence on the
//! completion channel.
use super::migration_gate::{wait_for_migration_with_progress, MigrationGate};
use super::migration_progress::{
    persist_migration_progress_events, should_persist_migration_progress_events,
    MigrationProgressEvent,
};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

/// verify the threshold callback fires after the
/// configured wait when the migration runs past the gate. We drive
/// the gate with a 100 ms threshold and a 400 ms simulated
/// migration so the test stays fast on CI but still observably
/// crosses the boundary.
#[test]
fn threshold_gate_fires_after_configured_duration() {
    let (tx, rx) = mpsc::channel::<()>();
    let threshold = Duration::from_millis(100);
    let migration_duration = Duration::from_millis(400);

    // Spawn the "migration" — just sleep then send. This is the
    // exact control-flow pattern of the production code path: the
    // runner thread sends `()` on the channel once `init_pool`
    // returns.
    thread::spawn(move || {
        thread::sleep(migration_duration);
        let _ = tx.send(());
    });

    let fired = Arc::new(AtomicBool::new(false));
    let fired_for_cb = fired.clone();
    let start = Instant::now();
    let gate = wait_for_migration_with_progress(&rx, threshold, move || {
        fired_for_cb.store(true, Ordering::SeqCst);
    });
    let elapsed = start.elapsed();

    assert_eq!(
        gate,
        MigrationGate::ThresholdCrossed,
        "gate must report ThresholdCrossed when migration runs past the threshold"
    );
    assert!(
        fired.load(Ordering::SeqCst),
        "on_threshold callback must fire exactly when the threshold elapses"
    );
    assert!(
        elapsed >= threshold,
        "the gate must wait at least the configured threshold before firing \
         (elapsed={elapsed:?}, threshold={threshold:?})"
    );
    // And it must keep waiting for the full migration duration.
    assert!(
        elapsed >= migration_duration,
        "the gate must block until the migration completes after the dialog is raised \
         (elapsed={elapsed:?}, migration_duration={migration_duration:?})"
    );
}

/// the startup-failure marker must be written
/// owner-only on Unix so a co-tenant on a shared host cannot
/// tail the (already redacted) error body. Verify the mode bits
/// land at exactly 0o600.
#[test]
#[cfg(unix)]
fn write_owner_only_marker_uses_0o600_permissions() {
    use std::os::unix::fs::PermissionsExt;

    let dir = tempfile::tempdir().expect("tempdir");
    let marker = dir.path().join("db.startup-failure.txt");
    super::startup_failure::write_owner_only_marker(&marker, "test body");

    let meta = std::fs::metadata(&marker).expect("marker file must exist");
    let mode = meta.permissions().mode() & 0o777;
    assert_eq!(
        mode, 0o600,
        "startup-failure marker must be owner-only (got {mode:o})"
    );
    assert_eq!(
        std::fs::read_to_string(&marker).expect("read marker"),
        "test body"
    );
}

#[test]
fn migration_progress_events_persist_to_error_logs() {
    let conn = crate::test_support::test_conn();
    let events = vec![
        MigrationProgressEvent::new("app.startup.migration.init", "opening database pool", None),
        MigrationProgressEvent::new(
            "app.startup.migration.complete",
            "database migration completed",
            Some("finished in 42ms".to_string()),
        ),
    ];

    persist_migration_progress_events(&conn, &events);

    let rows = conn
        .prepare(
            "SELECT source, level, message, details
             FROM error_logs
             WHERE source LIKE 'app.startup.migration.%'
             ORDER BY source",
        )
        .expect("prepare migration progress diagnostics read")
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<String>>(3)?,
            ))
        })
        .expect("query migration progress diagnostics")
        .collect::<rusqlite::Result<Vec<_>>>()
        .expect("collect migration progress diagnostics");

    assert_eq!(
        rows,
        vec![
            (
                "app.startup.migration.complete".to_string(),
                "info".to_string(),
                "database migration completed".to_string(),
                Some("finished in 42ms".to_string()),
            ),
            (
                "app.startup.migration.init".to_string(),
                "info".to_string(),
                "opening database pool".to_string(),
                None,
            ),
        ]
    );
}

#[test]
fn migration_progress_events_only_persist_for_slow_startup_gate() {
    assert!(
        !should_persist_migration_progress_events(&MigrationGate::FinishedQuickly),
        "ordinary quick launches must not add routine info rows to error_logs"
    );
    assert!(
        should_persist_migration_progress_events(&MigrationGate::ThresholdCrossed),
        "slow launches that showed the progress dialog should keep a durable timeline"
    );
}

#[test]
fn migration_progress_timeline_formats_marker_section() {
    let events = vec![
        MigrationProgressEvent::new("app.startup.migration.init", "opening database pool", None),
        MigrationProgressEvent::new(
            "app.startup.migration.threshold_crossed",
            "database migration still running after threshold; raising progress dialog",
            Some("threshold=3s".to_string()),
        ),
    ];

    let expected = [
        "  - app.startup.migration.init: opening database pool\n",
        "  - app.startup.migration.threshold_crossed: database migration still running after threshold; raising progress dialog (threshold=3s)\n",
    ]
    .concat();

    assert_eq!(
        super::migration_progress::format_migration_progress_timeline(&events),
        expected
    );
}

/// Counterpart: a migration that finishes well before the threshold
/// must NEVER raise the dialog. This protects ordinary short
/// launches from flashing a spurious dialog on screen.
#[test]
fn threshold_gate_stays_silent_when_migration_is_fast() {
    let (tx, rx) = mpsc::channel::<()>();
    let threshold = Duration::from_millis(500);

    thread::spawn(move || {
        // Finish essentially instantly.
        let _ = tx.send(());
    });

    let fired = Arc::new(AtomicBool::new(false));
    let fired_for_cb = fired.clone();
    let gate = wait_for_migration_with_progress(&rx, threshold, move || {
        fired_for_cb.store(true, Ordering::SeqCst);
    });

    assert_eq!(gate, MigrationGate::FinishedQuickly);
    assert!(
        !fired.load(Ordering::SeqCst),
        "short migrations must stay silent — no dialog callback"
    );
}
