use super::load_setup_status;
use crate::test_support::test_conn;

#[test]
fn load_setup_status_uses_required_prerequisites() {
    let conn = test_conn();
    // Schema already seeds 'inbox' list + default_list_id preference,
    // so normal_task_creation_ready should be true from the start.

    let incomplete = load_setup_status(&conn).expect("load incomplete status");
    assert!(incomplete.normal_task_creation_ready);
    assert!(!incomplete.setup_completed);

    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-03T00:00:00Z')",
        rusqlite::params![
            lorvex_domain::preference_keys::PREF_WORKING_HOURS,
            "{\"start\":\"09:00\",\"end\":\"17:00\"}"
        ],
    )
    .expect("seed working hours");

    let complete = load_setup_status(&conn).expect("load complete status");
    assert!(complete.setup_completed);
    assert!(complete.prerequisites_ready);
}
