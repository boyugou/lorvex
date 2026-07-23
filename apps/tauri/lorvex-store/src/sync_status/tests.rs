//! Tests for `sync_status`. Extracted from the parent file
//! to keep the production module focused.

use rusqlite::Connection;

use super::*;

const V1: &str = "0001743573600000_0001_6465766963656131";
const V2: &str = "0001743573601000_0001_6465766963656131";

fn conn() -> Connection {
    crate::open_db_in_memory().expect("open migrated in-memory db")
}

#[test]
fn load_sync_status_snapshot_returns_empty_defaults() {
    let conn = conn();

    let snapshot = load_sync_status_snapshot(&conn).expect("load empty status");

    assert_eq!(snapshot.pending_count, 0);
    assert_eq!(snapshot.retrying_count, 0);
    assert_eq!(snapshot.failed_count, 0);
    assert_eq!(snapshot.pending_inbox_count, 0);
    assert_eq!(snapshot.tombstone_count, 0);
    assert_eq!(snapshot.conflict_log_count, 0);
    assert_eq!(snapshot.sync_backend_kind, None);
    assert!(!snapshot.sync_backend_kind_malformed);
    assert_eq!(
        snapshot.sync_backend_kind_effective,
        lorvex_domain::parsing::SyncBackendKind::platform_default().to_string()
    );
}

#[test]
fn load_sync_status_snapshot_projects_shared_diagnostics() {
    let conn = conn();
    conn.execute(
        "INSERT INTO sync_outbox
         (entity_type, entity_id, operation, version, payload_schema_version, payload,
          device_id, created_at, retry_count)
         VALUES
         ('task', 'task-a', 'upsert', ?1, 1, '{}', 'device-a', '2026-04-01T00:00:00.000Z', 0),
         ('task', 'task-b', 'upsert', ?2, 1, '{}', 'device-a', '2026-04-02T00:00:00.000Z', 10)",
        [V1, V2],
    )
    .expect("insert outbox");
    conn.execute(
        "INSERT INTO sync_outbox
         (entity_type, entity_id, operation, version, payload_schema_version, payload,
          device_id, created_at, synced_at)
         VALUES ('task', 'task-c', 'upsert', ?1, 1, '{}', 'device-a',
                 '2026-04-03T00:00:00.000Z', '2026-04-04T00:00:00.000Z')",
        [V1],
    )
    .expect("insert synced outbox");
    conn.execute(
        "INSERT INTO sync_pending_inbox
         (envelope, reason, envelope_entity_type, envelope_entity_id, envelope_version,
          first_attempted_at, last_attempted_at)
         VALUES ('{}', 'missing_fk', 'task', 'task-z', ?1,
                 '2026-03-31T00:00:00.000Z', '2026-03-31T00:00:00.000Z')",
        [V1],
    )
    .expect("insert pending inbox");
    conn.execute(
        "INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
         VALUES ('task', 'task-deleted', ?1, '2026-04-05T00:00:00.000Z')",
        [V1],
    )
    .expect("insert tombstone");
    conn.execute(
        "INSERT INTO sync_conflict_log
         (entity_type, entity_id, winner_version, loser_version, loser_device_id,
          resolved_at, resolution_type)
         VALUES ('task', 'task-conflict', ?2, ?1, 'device-b',
                 '2026-04-06T00:00:00.000Z', 'lww')",
        [V1, V2],
    )
    .expect("insert conflict");
    conn.execute(
        "INSERT INTO calendar_subscriptions
         (id, name, url, enabled, version, created_at, updated_at)
         VALUES
         ('sub-a', 'A', 'https://example.test/a.ics', 1, ?1,
          '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z'),
         ('sub-b', 'B', 'https://example.test/b.ics', 1, ?2,
          '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        [V1, V2],
    )
    .expect("insert subscriptions");
    conn.execute(
        "INSERT INTO provider_scope_runtime_state
         (provider_kind, provider_scope, availability_state, last_refresh_result)
         VALUES ('ical_subscription', 'sub-a', 'permission_denied', 'permission_denied')",
        [],
    )
    .expect("insert provider runtime state");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES
         ('device_id', 'device-a'),
         ('reseed_required', 'true'),
         ('last_error', 'boom'),
         ('last_success_at', '2026-04-08T00:00:00.000Z'),
         ('last_pull_at', 'not-a-date'),
         ('filesystem_bridge_last_pull_cursor', ?1),
         ('filesystem_bridge_lookback_known_id_skipped_last_run', '7'),
         ('filesystem_bridge_lookback_known_id_skipped_last_run_at', '2026-04-09T00:00:00.000Z')",
        [format!(
            r#"{{"updated_at":"{V2}","device_id":"device-a","event_id":"event-a"}}"#
        )],
    )
    .expect("insert checkpoints");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES (?1, ?2, ?3, '2026-04-01T00:00:00.000Z')",
        [
            lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND,
            r#""filesystem_bridge""#,
            V1,
        ],
    )
    .expect("insert sync backend preference");

    let snapshot = load_sync_status_snapshot(&conn).expect("load seeded status");

    assert_eq!(snapshot.pending_count, 2);
    assert_eq!(snapshot.retrying_count, 1);
    assert_eq!(snapshot.failed_count, 1);
    assert_eq!(
        snapshot.last_synced_at,
        Some("2026-04-04T00:00:00.000Z".to_string())
    );
    assert_eq!(snapshot.pending_inbox_count, 1);
    assert_eq!(
        snapshot.pending_inbox_oldest_at,
        Some("2026-03-31T00:00:00.000Z".to_string())
    );
    assert_eq!(snapshot.tombstone_count, 1);
    assert_eq!(snapshot.conflict_log_count, 1);
    assert_eq!(snapshot.apply_cycle_count, 0);
    assert_eq!(snapshot.apply_cycle_last_applied, 0);
    assert_eq!(snapshot.ical_subscription_total_count, 2);
    assert_eq!(snapshot.ical_subscription_failing_count, 1);
    assert_eq!(snapshot.ical_subscription_never_refreshed_count, 1);
    assert!(snapshot.reseed_required);
    assert_eq!(snapshot.device_id, Some("device-a".to_string()));
    assert_eq!(snapshot.last_error, Some("boom".to_string()));
    assert_eq!(snapshot.last_pull_at, None);
    assert!(snapshot.last_pull_at_malformed);
    assert_eq!(
        snapshot.last_pull_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
    assert_eq!(
        snapshot.filesystem_bridge_last_pull_event_id,
        Some("event-a".to_string())
    );
    assert_eq!(
        snapshot.filesystem_bridge_lookback_known_id_skipped_last_run,
        7
    );
    assert_eq!(
        snapshot.sync_backend_kind,
        Some("filesystem_bridge".to_string())
    );
    assert_eq!(snapshot.sync_backend_kind_effective, "filesystem_bridge");
    assert!(!snapshot.sync_backend_kind_malformed);
}

#[test]
fn load_sync_status_snapshot_preserves_malformed_diagnostics() {
    let conn = conn();
    conn.execute(
        "INSERT INTO sync_outbox
         (entity_type, entity_id, operation, version, payload_schema_version, payload,
          device_id, created_at, synced_at)
         VALUES ('task', 'task-synced', 'upsert', ?1, 1, '{}', 'device-a',
                 '2026-04-01T00:00:00.000Z', 'not-a-date')",
        [V1],
    )
    .expect("insert malformed synced_at");
    conn.execute(
        "INSERT INTO sync_pending_inbox
         (envelope, reason, envelope_entity_type, envelope_entity_id, envelope_version,
          first_attempted_at, last_attempted_at)
         VALUES ('{}', 'missing_fk', 'task', 'task-z', ?1,
                 'bad-pending-date', 'bad-pending-date')",
        [V1],
    )
    .expect("insert malformed pending inbox timestamp");
    conn.execute(
        "INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
         VALUES ('task', 'task-deleted', ?1, 'bad-tombstone-date')",
        [V1],
    )
    .expect("insert malformed tombstone timestamp");
    conn.execute(
        "INSERT INTO sync_conflict_log
         (entity_type, entity_id, winner_version, loser_version, loser_device_id,
          resolved_at, resolution_type)
         VALUES ('task', 'task-conflict', ?1, ?1, 'device-b',
                 'bad-conflict-date', 'lww')",
        [V1],
    )
    .expect("insert malformed conflict timestamp");
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES
         ('reseed_required', 'maybe'),
         ('last_success_at', 'bad-success-date'),
         ('last_pull_at', 'bad-pull-date'),
         ('filesystem_bridge_last_pull_cursor', '{'),
         ('filesystem_bridge_lookback_known_id_skipped_last_run', 'NaN'),
         ('filesystem_bridge_lookback_known_id_skipped_last_run_at', 'bad-lookback-date')",
        [],
    )
    .expect("insert malformed checkpoints");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES (?1, 'not-json', ?2, '2026-04-01T00:00:00.000Z')",
        [lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND, V1],
    )
    .expect("insert malformed sync backend preference");

    let snapshot = load_sync_status_snapshot(&conn).expect("load malformed status");

    assert!(snapshot.last_synced_at_malformed);
    assert_eq!(
        snapshot.last_synced_at_malformed_reason,
        Some("invalid_rfc3339".to_string())
    );
    assert!(snapshot.pending_inbox_oldest_at_malformed);
    assert!(snapshot.tombstone_oldest_deleted_at_malformed);
    assert!(snapshot.tombstone_newest_deleted_at_malformed);
    assert!(snapshot.conflict_log_last_resolved_at_malformed);
    assert!(snapshot.reseed_required_malformed);
    assert_eq!(
        snapshot.reseed_required_malformed_reason,
        Some("invalid_bool".to_string())
    );
    assert!(snapshot.last_success_at_malformed);
    assert!(snapshot.last_pull_at_malformed);
    assert!(snapshot.filesystem_bridge_last_pull_cursor_malformed);
    assert!(snapshot.filesystem_bridge_lookback_known_id_skipped_last_run_malformed);
    assert!(snapshot.filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed);
    assert!(snapshot.sync_backend_kind_malformed);
    assert_eq!(
        snapshot.sync_backend_kind_malformed_reason,
        Some("invalid_json".to_string())
    );
}

#[test]
fn load_sync_status_snapshot_keeps_well_formed_boundary_when_only_some_rows_are_malformed() {
    // The GLOB shape gate filters malformed rows OUT of the lex
    // MIN/MAX so a hand-edited row carrying a non-canonical literal
    // does not shadow the well-formed values the diagnostic surface
    // needs to display. Two invariants must hold simultaneously:
    //
    //   1. The reported boundary value is the well-formed MIN/MAX
    //      (NOT the malformed string)
    //   2. The `_malformed` flag is `true` because at least one
    //      malformed row exists in the table
    //
    // The all-malformed test above (`*_preserves_malformed_diagnostics`)
    // pinned only invariant (1) for the all-bad case. This covers
    // the mixed case the GLOB gate actually exists to handle, plus
    // the secondary count-driven flag re-establishment for the
    // outbox aggregate (lines 188-201 in sync_status.rs).
    let conn = conn();

    // Tombstones: one well-formed earlier date, one malformed later
    // string. Lex-MAX over the raw column would be the malformed
    // string ('not-a-date' starts with 'n' which is > '2' in ASCII
    // so it sorts above '2026-...'). The GLOB gate filters it out.
    conn.execute(
        "INSERT INTO sync_tombstones (
            entity_type, entity_id, version, deleted_at,
            redirect_entity_id, redirect_entity_type
         ) VALUES
           ('task', 'task-good', '0000000000000_0000_aaaaaaaaaaaaaaaa',
            '2026-04-01T08:00:00.000Z', NULL, NULL),
           ('task', 'task-bad', '0000000000000_0000_bbbbbbbbbbbbbbbb',
            'not-a-date', NULL, NULL)",
        [],
    )
    .expect("insert mixed tombstones");

    // sync_pending_inbox: one valid, one malformed.
    conn.execute(
        "INSERT INTO sync_pending_inbox
         (envelope, reason, envelope_entity_type, envelope_entity_id, envelope_version,
          first_attempted_at, last_attempted_at)
         VALUES
           ('{}', 'missing_fk', 'task', 'task-good', ?1,
            '2026-04-01T09:00:00.000Z', '2026-04-01T09:00:00.000Z'),
           ('{}', 'missing_fk', 'task', 'task-bad', ?2,
            'bogus-time', 'bogus-time')",
        [V1, V2],
    )
    .expect("insert mixed pending_inbox");

    // sync_conflict_log: one valid, one malformed.
    conn.execute(
        "INSERT INTO sync_conflict_log (
            entity_type, entity_id, winner_version, loser_version,
            loser_device_id, loser_payload, resolved_at, resolution_type
         ) VALUES
           ('task', 'task-good', '0000000000000_0000_winner000000000',
            '0000000000000_0000_loser0000000000', 'device-a', NULL,
            '2026-04-01T10:00:00.000Z', 'lww'),
           ('task', 'task-bad', '0000000000000_0000_winner000000001',
            '0000000000000_0000_loser0000000001', 'device-b', NULL,
            'wat', 'lww')",
        [],
    )
    .expect("insert mixed conflict_log");

    // sync_outbox: one well-formed `synced_at` plus one malformed
    // `synced_at`. The outbox aggregate post-fix surfaces the
    // malformed flag via a separate count column even when the
    // boundary value (MAX) was well-formed.
    conn.execute(
        "INSERT INTO sync_outbox
         (entity_type, entity_id, operation, version, payload_schema_version, payload,
          device_id, created_at, retry_count, synced_at)
         VALUES
           ('task', 'good', 'upsert', ?1, 1, '{}', 'device-a',
            '2026-04-01T07:00:00.000Z', 0, '2026-04-01T07:30:00.000Z'),
           ('task', 'bad', 'upsert', ?2, 1, '{}', 'device-a',
            '2026-04-01T07:05:00.000Z', 0, 'sync-time-corrupt')",
        [V1, V2],
    )
    .expect("insert mixed outbox");

    let snapshot = load_sync_status_snapshot(&conn).expect("load mixed status");

    // Tombstone boundaries: well-formed value reported, flag still on.
    assert_eq!(
        snapshot.tombstone_oldest_deleted_at.as_deref(),
        Some("2026-04-01T08:00:00.000Z"),
        "tombstone_oldest_deleted_at must be the well-formed MIN, not the malformed lex-MIN",
    );
    assert_eq!(
        snapshot.tombstone_newest_deleted_at.as_deref(),
        Some("2026-04-01T08:00:00.000Z"),
        "tombstone_newest_deleted_at must be the well-formed MAX (the malformed string is lex > '2026...' but the GLOB gate filters it out)",
    );
    assert!(
        snapshot.tombstone_oldest_deleted_at_malformed,
        "tombstone_oldest_deleted_at_malformed must surface the malformed-row count > 0"
    );
    assert!(
        snapshot.tombstone_newest_deleted_at_malformed,
        "tombstone_newest_deleted_at_malformed must surface the malformed-row count > 0"
    );

    // Pending inbox.
    assert_eq!(
        snapshot.pending_inbox_oldest_at.as_deref(),
        Some("2026-04-01T09:00:00.000Z"),
        "pending_inbox_oldest_at must be the well-formed MIN",
    );
    assert!(
        snapshot.pending_inbox_oldest_at_malformed,
        "pending_inbox_oldest_at_malformed must surface count > 0"
    );

    // Conflict log.
    assert_eq!(
        snapshot.conflict_log_last_resolved_at.as_deref(),
        Some("2026-04-01T10:00:00.000Z"),
        "conflict_log_last_resolved_at must be the well-formed MAX",
    );
    assert!(
        snapshot.conflict_log_last_resolved_at_malformed,
        "conflict_log_last_resolved_at_malformed must surface count > 0"
    );

    // Outbox `last_synced_at` — the cross-cutting-finding-5 fix that
    // motivated this whole exercise.
    assert_eq!(
        snapshot.last_synced_at.as_deref(),
        Some("2026-04-01T07:30:00.000Z"),
        "last_synced_at must be the well-formed MAX after the GLOB gate",
    );
    assert!(
        snapshot.last_synced_at_malformed,
        "last_synced_at_malformed must surface via the separate malformed-row count",
    );
    assert_eq!(
        snapshot.last_synced_at_malformed_reason.as_deref(),
        Some("invalid_rfc3339"),
    );
}
