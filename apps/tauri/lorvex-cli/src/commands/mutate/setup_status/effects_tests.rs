use super::effects::*;
use crate::error::CliError;
use lorvex_domain::naming::ENTITY_PREFERENCE;
use lorvex_store::open_db_in_memory;

#[test]
fn get_setup_status_returns_baseline() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = open_db_in_memory().expect("open db");
    let snapshot = get_setup_status_with_conn(&conn).expect("status");
    // Schema seeds an inbox list + default_list_id preference.
    assert!(snapshot.status.normal_task_creation_ready);
    assert!(snapshot.list_count >= 1);
}

#[test]
fn complete_setup_marks_setup_completed_and_persists_prefs() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open db");
    let result = complete_setup_with_conn(&mut conn, "Onboarding done").expect("complete setup");
    assert!(result.setup_completed);
    assert_eq!(result.summary, "Onboarding done");

    // The three preference rows must be present.
    for key in [
        lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
        "setup_summary",
        lorvex_domain::preference_keys::PREF_SETUP_STATE,
    ] {
        let exists: bool = conn
            .query_row(
                "SELECT 1 FROM preferences WHERE key = ?1",
                rusqlite::params![key],
                |_r| Ok(true),
            )
            .unwrap_or(false);
        assert!(exists, "preference {key} not persisted");
    }
}

#[test]
fn complete_setup_rejects_empty_summary() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open db");
    let err = complete_setup_with_conn(&mut conn, "   ").expect_err("empty");
    assert!(matches!(err, CliError::Validation(_)));
}

/// each of the three preference rows
/// `complete_setup_with_conn` writes (`setup_completed`,
/// `setup_summary`, `setup_state`) must produce its own
/// `ai_changelog` row.
/// changelog row referencing `setup_completed`; the other two
/// preference writes were invisible to consumers that filter
/// the audit stream by `entity_id`.
#[test]
fn complete_setup_emits_one_changelog_row_per_preference_write() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = open_db_in_memory().expect("open db");
    complete_setup_with_conn(&mut conn, "Onboarding done").expect("complete setup");

    let entity_ids: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT entity_id FROM ai_changelog
                 WHERE entity_type = ?1 AND operation = 'update'
                   AND entity_id IN (?2, 'setup_summary', ?3)
                 ORDER BY entity_id ASC",
            )
            .expect("prepare");
        stmt.query_map(
            rusqlite::params![
                ENTITY_PREFERENCE,
                lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
                lorvex_domain::preference_keys::PREF_SETUP_STATE,
            ],
            |row| row.get::<_, String>(0),
        )
        .expect("query")
        .collect::<Result<_, _>>()
        .expect("collect")
    };

    let expected_ids: std::collections::HashSet<&str> = [
        lorvex_domain::preference_keys::PREF_SETUP_COMPLETED,
        "setup_summary",
        lorvex_domain::preference_keys::PREF_SETUP_STATE,
    ]
    .iter()
    .copied()
    .collect();
    let actual_ids: std::collections::HashSet<&str> =
        entity_ids.iter().map(std::string::String::as_str).collect();
    assert_eq!(
        actual_ids, expected_ids,
        "each setup preference write must have its own changelog row; got {entity_ids:?}"
    );
    assert_eq!(
        entity_ids.len(),
        3,
        "expected exactly three changelog rows, got {entity_ids:?}"
    );
}
