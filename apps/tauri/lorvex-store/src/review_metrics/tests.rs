use super::load_task_estimate_summary;
use crate::{migration::apply_migrations, open_db_in_memory, schema::all_migrations};

#[test]
fn load_task_estimate_summary_computes_coverage() {
    let conn = open_db_in_memory().expect("open in-memory db");
    apply_migrations(&conn, &all_migrations()).expect("apply migrations");
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES ('l1', 'Default', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
        [],
    )
    .expect("seed list");
    conn.execute(
        "INSERT INTO tasks (
            id, title, status, list_id, estimated_minutes,
            completed_at, version, created_at, updated_at
         ) VALUES
            ('t1', 'Covered', 'completed', 'l1', 30, '2026-04-02T12:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-02T00:00:00Z', '2026-04-02T12:00:00Z'),
            ('t2', 'Covered only', 'completed', 'l1', 20, '2026-04-02T13:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-02T00:00:00Z', '2026-04-02T13:00:00Z'),
            ('t3', 'Unestimated', 'completed', 'l1', NULL, '2026-04-02T14:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-02T00:00:00Z', '2026-04-02T14:00:00Z')
        ",
        [],
    )
    .expect("seed tasks");

    let summary = load_task_estimate_summary(&conn, "2026-04-01T00:00:00Z", "2026-04-03T00:00:00Z")
        .expect("load task estimate summary");

    assert_eq!(summary.completed_total, 3);
    assert_eq!(summary.completed_with_estimate_count, 2);
    assert_eq!(summary.estimate_coverage_ratio, Some(2.0 / 3.0));
}
