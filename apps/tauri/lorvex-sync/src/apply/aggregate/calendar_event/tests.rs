use rusqlite::params;

use crate::test_db;

/// same shape as the task / habit
/// cascade-before-LWW tests — a calendar_event row whose
/// `version` column is a legacy `'v1'` literal must have its
/// delete refused, AND the cascade pass over
/// `task_calendar_event_links` must NOT run. Pre-#3002 the
/// cascade fired before the byte-compare fallback rejected the
/// parent delete, leaving orphan link tombstones.
#[test]
fn cascade_does_not_run_when_byte_compare_fallback_rejects_legacy_local_version() {
    let conn = test_db();
    let event_id = "00000000-0000-7000-8000-000000004001";
    let task_id = "00000000-0000-7000-8000-000000004002";
    let canonical_envelope_version = "1711234599000_0000_dec0000200000002";
    let legacy_local_version = "v1";

    conn.execute(
        "INSERT INTO calendar_events (
            id, title, start_date, all_day, version,
            created_at, updated_at
         ) VALUES (?1, 'meeting', '2026-04-01', 0, ?2,
                   '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![event_id, legacy_local_version],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, version,
                            created_at, updated_at, defer_count)
         VALUES (?1, 'T', 'open', ?2,
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)",
        params![task_id, canonical_envelope_version],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_calendar_event_links (
            task_id, calendar_event_id, version, created_at, updated_at
         ) VALUES (?1, ?2, ?3,
                   '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![task_id, event_id, canonical_envelope_version],
    )
    .unwrap();

    let outcome = super::apply_calendar_event_delete(
        &conn,
        event_id,
        canonical_envelope_version,
        "2026-04-01T00:00:00.000Z",
    )
    .unwrap();
    assert!(
        matches!(outcome, super::super::LwwGatedDeleteOutcome::LwwRejected(_)),
        "byte-compare fallback must surface as LwwRejected, got {outcome:?}"
    );

    let parent_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_events WHERE id = ?1",
            params![event_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        parent_count, 1,
        "parent calendar_event must survive the rejected delete"
    );

    let link_edge_id = format!("{task_id}:{event_id}");
    let link_ts_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones \
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![
                lorvex_domain::naming::EDGE_TASK_CALENDAR_EVENT_LINK,
                &link_edge_id
            ],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        link_ts_count, 0,
        "task_calendar_event_link cascade tombstone must NOT be written on rejected parent delete"
    );
}
