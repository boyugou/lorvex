//! Tests for the periodic retention sweep — focused on the watermark
//! gate and the public preference reader. The full sweep behavior is
//! covered end-to-end by the Tauri-side `retention_cleanup` integration
//! tests; here we exercise the new cross-process wiring.

use super::{
    read_retention_days, record_retention_sweep_completed, resolve_retention_days,
    run_periodic_retention_sweep, should_run_retention_sweep, DEFAULT_AI_CHANGELOG_RETENTION_DAYS,
    HARD_CAP_RETENTION_DAYS, KEY_LAST_RETENTION_SWEEP_AT,
};

/// Pin the default-policy invariant: `DEFAULT_AI_CHANGELOG_RETENTION_DAYS`
/// must be a positive non-zero value (a zero would purge everything on
/// the next sweep tick), and must clamp to under the hard cap. The
/// previous `let _ = DEFAULT_AI_CHANGELOG_RETENTION_DAYS;` line was
/// fake coverage — swapped for compile-time const-block assertions
/// so a future tweak that violates the invariant fails to build
///.
#[test]
fn default_changelog_retention_days_is_within_hard_cap() {
    const _: () = assert!(
        DEFAULT_AI_CHANGELOG_RETENTION_DAYS > 0,
        "default policy must keep at least one day of history",
    );
    const _: () = assert!(
        DEFAULT_AI_CHANGELOG_RETENTION_DAYS <= HARD_CAP_RETENTION_DAYS,
        "default policy must not exceed the documented hard cap",
    );
}

fn fresh_conn() -> rusqlite::Connection {
    lorvex_store::test_support::test_conn()
}

#[test]
fn should_run_returns_true_when_watermark_absent() {
    let conn = fresh_conn();
    assert!(
        should_run_retention_sweep(&conn).expect("watermark check"),
        "no checkpoint row → first run should be due"
    );
}

#[test]
fn should_run_returns_false_immediately_after_record() {
    let conn = fresh_conn();
    record_retention_sweep_completed(&conn).expect("record sweep");
    assert!(
        !should_run_retention_sweep(&conn).expect("watermark check"),
        "just-recorded sweep should not be immediately due again"
    );
}

#[test]
fn should_run_returns_true_when_watermark_is_old() {
    let conn = fresh_conn();
    // Stamp a watermark from 24 hours ago (well past the 6-hour interval).
    let old_ts: String = conn
        .query_row(
            "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours')",
            [],
            |r| r.get(0),
        )
        .expect("compute old timestamp");
    lorvex_runtime::sync_checkpoint_set(&conn, KEY_LAST_RETENTION_SWEEP_AT, &old_ts)
        .expect("seed old watermark");
    assert!(
        should_run_retention_sweep(&conn).expect("watermark check"),
        "watermark older than interval should re-arm sweep"
    );
}

#[test]
fn resolve_retention_days_uses_default_when_explicit_is_zero_or_negative() {
    assert_eq!(resolve_retention_days(Some(0), 30), 30);
    assert_eq!(resolve_retention_days(Some(-5), 30), 30);
    assert_eq!(resolve_retention_days(None, 90), 90);
}

#[test]
fn resolve_retention_days_clamps_to_hard_cap() {
    assert_eq!(
        resolve_retention_days(Some(HARD_CAP_RETENTION_DAYS + 100), 30),
        HARD_CAP_RETENTION_DAYS
    );
}

#[test]
fn read_retention_days_returns_none_when_unset() {
    let conn = fresh_conn();
    let parsed = read_retention_days(
        &conn,
        lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY,
    )
    .expect("missing preference should be Ok(None)");
    assert_eq!(parsed, None);
}

#[test]
fn run_periodic_retention_sweep_succeeds_on_empty_db() {
    let conn = fresh_conn();
    let outcome = run_periodic_retention_sweep(&conn).expect("sweep on empty DB");
    assert_eq!(outcome.changelog_deleted, 0);
    assert_eq!(outcome.error_logs_deleted, 0);
    assert_eq!(outcome.memory_revisions_deleted, 0);
}
