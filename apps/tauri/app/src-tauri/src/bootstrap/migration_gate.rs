//! Migration-progress threshold gate (#2493) and the native
//! "Migrating…" dialog spawned when the gate fires.
//!
//! The wait helper is extracted from [`super::ensure_database_ready`]
//! so the unit tests can drive the threshold with a mock channel
//! instead of running a real SQL migration. The dialog raise lives
//! here too because it's the production callback the gate invokes
//! when the threshold elapses.

/// Threshold above which a long-running migration (or any pool init)
/// will raise a native "Migrating…" info dialog. Short migrations stay
/// silent so ordinary launches don't flash a dialog. The unit tests
/// exercise [`wait_for_migration_with_progress`] directly with a
/// shorter threshold so the production value can stay at the
/// user-facing 3 seconds without slowing CI.
pub(super) const MIGRATION_DIALOG_THRESHOLD: std::time::Duration =
    std::time::Duration::from_secs(3);

/// Outcome returned by [`wait_for_migration_with_progress`]. Exists so
/// the unit tests can assert whether the threshold gate actually fired,
/// without needing to observe the native dialog itself (which is
/// impossible on a headless test runner).
#[derive(Debug, PartialEq, Eq)]
pub(super) enum MigrationGate {
    /// The migration finished before the threshold elapsed — no dialog
    /// was raised.
    FinishedQuickly,
    /// The threshold elapsed while the migration was still running; the
    /// caller raised (or would raise) the native progress dialog and
    /// then blocked for the migration to complete.
    ThresholdCrossed,
}

/// Block the current thread until the migration-runner sends `()` on
/// `done`. If the threshold elapses first, invoke `on_threshold` (which
/// is where production callers raise the native dialog) and keep
/// waiting for the runner to finish.
///
/// Extracted from [`super::ensure_database_ready`] so the unit tests
/// can drive the threshold gate with a mock channel instead of running
/// a real migration. The return value reports whether the gate fired,
/// so the tests can assert the 3-second boundary is honoured.
pub(super) fn wait_for_migration_with_progress<F>(
    done: &std::sync::mpsc::Receiver<()>,
    threshold: std::time::Duration,
    mut on_threshold: F,
) -> MigrationGate
where
    F: FnMut(),
{
    match done.recv_timeout(threshold) {
        Ok(()) => MigrationGate::FinishedQuickly,
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
            on_threshold();
            // After the gate fires, keep blocking until the migration
            // thread finishes. We intentionally ignore `Disconnected`
            // here — the sender side always sends `()` before dropping,
            // so a bare disconnect only happens if the runner thread
            // panicked, and the caller surfaces that via the shared
            // `Arc<Mutex<...>>` result slot.
            let _ = done.recv();
            MigrationGate::ThresholdCrossed
        }
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => MigrationGate::FinishedQuickly,
    }
}

/// Raise a non-blocking native "Migrating…" info dialog on a dedicated
/// thread. The dialog uses `rfd` (already a transitive dep via
/// `tauri-plugin-dialog`) so we don't need an AppHandle — `rfd` talks to
/// the native OS dialog APIs directly (NSAlert / MessageBox / GTK).
///
/// The dialog thread is NOT joined: once the migration finishes the
/// main thread proceeds with `tauri::Builder::default()` regardless of
/// whether the user has clicked OK. This is the closest we can get to
/// "auto-dismiss" with `rfd` — the library has no public close API —
/// but it does not matter in practice: the dialog is informational, it
/// does NOT block the main thread, and if the user leaves it up they
/// simply see the app window mount behind it.
pub(super) fn spawn_migration_progress_dialog() {
    let _ = std::thread::Builder::new()
        .name("lorvex-migration-dialog".into())
        .spawn(|| {
            let _ = rfd::MessageDialog::new()
                .set_level(rfd::MessageLevel::Info)
                .set_title("Lorvex")
                .set_description("Migrating database (this may take a few minutes — do not quit).")
                .set_buttons(rfd::MessageButtons::Ok)
                .show();
        });
}
