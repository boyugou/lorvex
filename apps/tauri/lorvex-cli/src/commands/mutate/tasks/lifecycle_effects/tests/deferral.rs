use super::super::*;
use super::support::*;

#[test]
fn defer_task_with_conn_rejects_invalid_structured_reason() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-defer-bad", "Bad defer", "open");

    let error = defer_task_with_conn(
        &conn,
        &tid("task-defer-bad"),
        Some(1),
        None,
        Some("not_a_real_reason"),
    )
    .expect_err("invalid structured defer reason should be rejected");
    assert!(error
        .to_string()
        .contains("invalid structured defer reason"));
}

/// the free-text `reason` argument flows into `ai_notes`
/// AND into the changelog summary, so it must pass through
/// `sanitize_user_text` BEFORE length validation and before either
/// downstream consumer sees it. Build a reason that contains the full
/// gauntlet of trust-boundary hazards (bidi override, ZWSP, ANSI
/// escape, NUL) and assert that none of them survive into either
/// surface.
#[test]
fn defer_task_with_conn_sanitizes_reason_for_ai_notes_and_changelog() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000057";
    seed_task(&conn, task_id, "Sanitize me", "open");

    // U+202E RIGHT-TO-LEFT OVERRIDE, U+200B ZERO WIDTH SPACE,
    // U+001B ANSI escape, U+0000 NUL, plus a benign payload.
    let dangerous_reason = "Waiting\u{202E}on \u{200B}reply\u{001B}[31mRED\u{0000}";

    defer_task_with_conn(&conn, &tid(task_id), Some(1), Some(dangerous_reason), None)
        .expect("defer with sanitized reason");

    let ai_notes: Option<String> = conn
        .query_row(
            "SELECT ai_notes FROM tasks WHERE id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("load ai_notes");
    let ai_notes = ai_notes.expect("ai_notes should be Some after defer with reason");
    assert!(
        !ai_notes.contains('\u{202E}'),
        "ai_notes must not contain U+202E (got {ai_notes:?})"
    );
    assert!(
        !ai_notes.contains('\u{200B}'),
        "ai_notes must not contain U+200B (got {ai_notes:?})"
    );
    assert!(
        !ai_notes.contains('\u{001B}'),
        "ai_notes must not contain U+001B (got {ai_notes:?})"
    );
    assert!(
        !ai_notes.contains('\u{0000}'),
        "ai_notes must not contain U+0000 (got {ai_notes:?})"
    );
    // The benign payload still reaches the row.
    assert!(ai_notes.contains("Waiting"));
    assert!(ai_notes.contains("reply"));

    // Same control-character invariant for the changelog summary.
    let summary: String = conn
        .query_row(
            "SELECT summary FROM ai_changelog WHERE entity_id = ?1 AND operation = 'defer'",
            [task_id],
            |row| row.get(0),
        )
        .expect("load defer changelog summary");
    assert!(!summary.contains('\u{202E}'));
    assert!(!summary.contains('\u{200B}'));
    assert!(!summary.contains('\u{001B}'));
    assert!(!summary.contains('\u{0000}'));
}

#[test]
fn defer_task_with_conn_rejects_non_positive_days() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-defer-zero", "Zero defer", "open");

    let error = defer_task_with_conn(&conn, &tid("task-defer-zero"), Some(0), None, None)
        .expect_err("zero days should be rejected");
    assert!(error.to_string().contains("defer days must be >= 1"));
}
