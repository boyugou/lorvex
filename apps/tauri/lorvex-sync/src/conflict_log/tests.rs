//! Tests for `conflict_log`. Extracted from the parent file
//! to keep the production module focused.

use super::*;
use crate::test_db;
use lorvex_domain::naming;

fn make_lww_conflict(entity_id: &str, resolved_at: &str) -> ConflictLogEntry {
    ConflictLogEntry {
        id: 0, // assigned by DB
        entity_type: Cow::Borrowed(lorvex_domain::naming::EntityKind::Task.as_str()),
        entity_id: entity_id.to_string(),
        winner_version: "1711234567891_0000_a1b2c3d4a1b2c3d4".to_string(),
        loser_version: "1711234567890_0000_bbbbbbbbbbbbbbbb".to_string(),
        loser_device_id: "device-002".to_string(),
        loser_payload: Some(r#"{"title":"old version"}"#.to_string()),
        resolved_at: resolved_at.to_string(),
        resolution_type: Cow::Borrowed(naming::RESOLUTION_LWW),
    }
}

#[test]
fn log_conflict_is_idempotent_on_replay() {
    // A peer that re-sends the same stale envelope (e.g. via
    // outbox retry) must not duplicate the conflict-log row.
    // Dedup is by (entity, loser_version, loser_device_id,
    // resolution_type) — the same conflict surfaced twice should
    // result in one row, but a *different* loser_version from the
    // same peer (or the same loser_version from a different peer)
    // logs separately so the diagnostic surface stays accurate.
    let conn = test_db();
    let entry = make_lww_conflict("task-001", "2026-03-23T12:00:00.000Z");

    log_conflict(&conn, &entry).unwrap();
    log_conflict(&conn, &entry).unwrap();
    log_conflict(&conn, &entry).unwrap();

    let results = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    assert_eq!(results.len(), 1, "replay should not duplicate the row");

    // A different loser_version from the same peer is a distinct
    // conflict — log it.
    let mut newer_loser = entry.clone();
    newer_loser.loser_version = "1711234567892_0000_bbbbbbbbbbbbbbbb".to_string();
    log_conflict(&conn, &newer_loser).unwrap();

    let results = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    assert_eq!(results.len(), 2, "distinct loser_version logs separately");

    // Same conflict from a different peer also logs separately.
    let mut other_peer = entry;
    other_peer.loser_device_id = "device-003".to_string();
    log_conflict(&conn, &other_peer).unwrap();

    let results = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    assert_eq!(results.len(), 3, "distinct loser_device_id logs separately");
}

#[test]
fn log_and_get_conflict() {
    let conn = test_db();
    let entry = make_lww_conflict("task-001", "2026-03-23T12:00:00.000Z");

    log_conflict(&conn, &entry).unwrap();

    let results = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].entity_type, naming::ENTITY_TASK);
    assert_eq!(results[0].entity_id, "task-001");
    assert_eq!(
        results[0].winner_version,
        "1711234567891_0000_a1b2c3d4a1b2c3d4"
    );
    assert_eq!(
        results[0].loser_version,
        "1711234567890_0000_bbbbbbbbbbbbbbbb"
    );
    assert_eq!(results[0].loser_device_id, "device-002");
    assert_eq!(results[0].resolution_type, naming::RESOLUTION_LWW);
    assert!(results[0].id > 0, "DB should assign a non-zero id");
}

#[test]
fn log_conflict_without_payload() {
    let conn = test_db();
    let entry = ConflictLogEntry {
        id: 0,
        entity_type: Cow::Borrowed(lorvex_domain::naming::EntityKind::Tag.as_str()),
        entity_id: "tag-001".to_string(),
        winner_version: "1711234567891_0000_a1b2c3d4a1b2c3d4".to_string(),
        loser_version: "1711234567890_0000_bbbbbbbbbbbbbbbb".to_string(),
        loser_device_id: "device-002".to_string(),
        loser_payload: None,
        resolved_at: "2026-03-23T12:00:00.000Z".to_string(),
        resolution_type: Cow::Borrowed(naming::RESOLUTION_TAG_MERGE),
    };

    log_conflict(&conn, &entry).unwrap();

    let results = get_conflicts_by_type(&conn, naming::RESOLUTION_TAG_MERGE, 10).unwrap();
    assert_eq!(results.len(), 1);
    assert!(results[0].loser_payload.is_none());
    assert_eq!(results[0].resolution_type, naming::RESOLUTION_TAG_MERGE);
}

#[test]
fn gc_conflicts_deletes_old() {
    let conn = test_db();

    let old_entry = make_lww_conflict("task-old", "2020-01-01T00:00:00.000Z");
    let recent_entry = make_lww_conflict("task-recent", "2099-01-01T00:00:00.000Z");

    log_conflict(&conn, &old_entry).unwrap();
    log_conflict(&conn, &recent_entry).unwrap();

    let deleted = gc_conflicts(&conn, 30).unwrap();
    assert_eq!(deleted, 1);

    let remaining = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    assert_eq!(remaining.len(), 1);
    assert_eq!(remaining[0].entity_id, "task-recent");
}

#[test]
fn gc_conflicts_preserves_all_when_none_expired() {
    let conn = test_db();

    let entry = make_lww_conflict("task-001", "2099-01-01T00:00:00.000Z");
    log_conflict(&conn, &entry).unwrap();

    let deleted = gc_conflicts(&conn, 30).unwrap();
    assert_eq!(deleted, 0);
}

#[test]
fn count_conflicts_empty() {
    let conn = test_db();
    assert_eq!(count_conflicts(&conn).unwrap(), 0);
}

#[test]
fn count_conflicts_after_inserts() {
    let conn = test_db();

    for i in 0..5 {
        let entry = make_lww_conflict(&format!("task-{i:03}"), "2026-03-23T12:00:00.000Z");
        log_conflict(&conn, &entry).unwrap();
    }

    assert_eq!(count_conflicts(&conn).unwrap(), 5);
}

#[test]
fn get_conflicts_by_type_filters_correctly() {
    let conn = test_db();

    let lww_entry = make_lww_conflict("task-001", "2026-03-23T12:00:00.000Z");
    log_conflict(&conn, &lww_entry).unwrap();

    let tag_merge_entry = ConflictLogEntry {
        id: 0,
        entity_type: Cow::Borrowed(lorvex_domain::naming::EntityKind::Tag.as_str()),
        entity_id: "tag-001".to_string(),
        winner_version: "1711234567891_0000_a1b2c3d4a1b2c3d4".to_string(),
        loser_version: "1711234567890_0000_bbbbbbbbbbbbbbbb".to_string(),
        loser_device_id: "device-002".to_string(),
        loser_payload: None,
        resolved_at: "2026-03-23T12:00:00.000Z".to_string(),
        resolution_type: Cow::Borrowed(naming::RESOLUTION_TAG_MERGE),
    };
    log_conflict(&conn, &tag_merge_entry).unwrap();

    let lww_only = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    assert_eq!(lww_only.len(), 1);
    assert_eq!(lww_only[0].entity_id, "task-001");

    let tag_merge_only = get_conflicts_by_type(&conn, naming::RESOLUTION_TAG_MERGE, 10).unwrap();
    assert_eq!(tag_merge_only.len(), 1);
    assert_eq!(tag_merge_only[0].entity_id, "tag-001");

    let fk_stalled = get_conflicts_by_type(&conn, naming::RESOLUTION_FK_STALLED, 10).unwrap();
    assert!(fk_stalled.is_empty());
}

#[test]
fn scrub_loser_payload_redacts_pii_keys() {
    let raw = r#"{"title":"Pregnancy test","notes":"follow up","tags":["health"],"priority":1}"#;
    let out = scrub_loser_payload(raw);
    assert!(!out.contains("Pregnancy test"));
    assert!(!out.contains("follow up"));
    assert!(out.contains("[REDACTED_PII]"));
    assert!(out.contains("\"tags\":[\"health\"]") || out.contains("\"tags\": [\"health\"]"));
    assert!(out.contains("\"priority\":1"));
}

#[test]
fn scrub_loser_payload_recurses_into_nested_objects() {
    let raw = r#"{"outer":{"notes":"secret","id":"abc"},"keep":true}"#;
    let out = scrub_loser_payload(raw);
    assert!(!out.contains("secret"));
    assert!(out.contains("[REDACTED_PII]"));
    assert!(out.contains("\"id\":\"abc\""));
    assert!(out.contains("\"keep\":true"));
}

#[test]
fn scrub_loser_payload_rejects_non_json() {
    let out = scrub_loser_payload("this is not json");
    assert_eq!(out, "<non-json payload suppressed>");
}

#[test]
fn log_conflict_stores_scrubbed_payload() {
    let conn = test_db();
    let entry = ConflictLogEntry {
        id: 0,
        entity_type: Cow::Borrowed(lorvex_domain::naming::EntityKind::Task.as_str()),
        entity_id: "task-001".to_string(),
        winner_version: "1711234567891_0000_a1b2c3d4a1b2c3d4".to_string(),
        loser_version: "1711234567890_0000_bbbbbbbbbbbbbbbb".to_string(),
        loser_device_id: "device-002".to_string(),
        loser_payload: Some(r#"{"title":"Therapy with Dr. X","priority":1}"#.to_string()),
        resolved_at: "2026-03-23T12:00:00.000Z".to_string(),
        resolution_type: Cow::Borrowed(naming::RESOLUTION_LWW),
    };
    log_conflict(&conn, &entry).unwrap();
    let results = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    let payload = results[0].loser_payload.as_deref().unwrap_or("");
    assert!(!payload.contains("Therapy with Dr. X"));
    assert!(payload.contains("[REDACTED_PII]"));
    assert!(payload.contains("\"priority\":1"));
}

#[test]
fn all_resolution_types_can_be_stored() {
    let conn = test_db();

    let types = [
        naming::RESOLUTION_LWW,
        naming::RESOLUTION_TAG_MERGE,
        naming::RESOLUTION_RECURRENCE_DEDUP,
        naming::RESOLUTION_FK_STALLED,
        naming::RESOLUTION_FK_UNRESOLVED,
        naming::RESOLUTION_RESEED_REQUIRED,
    ];

    for (i, res_type) in types.iter().enumerate() {
        let entry = ConflictLogEntry {
            id: 0,
            entity_type: Cow::Borrowed(lorvex_domain::naming::EntityKind::Task.as_str()),
            entity_id: format!("task-{i:03}"),
            winner_version: "1711234567891_0000_a1b2c3d4a1b2c3d4".to_string(),
            loser_version: "1711234567890_0000_bbbbbbbbbbbbbbbb".to_string(),
            loser_device_id: "device-002".to_string(),
            loser_payload: None,
            resolved_at: "2026-03-23T12:00:00.000Z".to_string(),
            resolution_type: Cow::Borrowed(*res_type),
        };
        log_conflict(&conn, &entry).unwrap();
    }

    assert_eq!(count_conflicts(&conn).unwrap(), types.len() as u64);
}

#[test]
fn multi_loser_in_one_envelope_distinct_payloads_persist() {
    // when one envelope-apply tx
    // emits multiple `lww` rows that share
    // `(entity, loser_version, loser_device_id, resolution_type)`
    // — e.g. a calendar-event arriving with N attendees that all
    // collide on the same canonical email — each per-loser payload
    // MUST distinguish the row. With distinct payloads, every
    // dropped attendee surfaces in Settings → Sync → Conflicts
    // instead of collapsing into the first.
    let conn = test_db();
    let envelope_constants = (
        naming::ENTITY_CALENDAR_EVENT,
        "event-001".to_string(),
        "1711234567891_0000_aaaaaaaaaaaaaaaa".to_string(),
        "1711234567890_0000_bbbbbbbbbbbbbbbb".to_string(),
        "device-002".to_string(),
        naming::RESOLUTION_LWW,
    );
    let make_row = |attendee_id: &str, hlc: &str| ConflictLogEntry {
        id: 0,
        entity_type: Cow::Borrowed(envelope_constants.0),
        entity_id: envelope_constants.1.clone(),
        winner_version: envelope_constants.2.clone(),
        loser_version: envelope_constants.3.clone(),
        loser_device_id: envelope_constants.4.clone(),
        // The structure-preserving scrubber keeps the non-PII id +
        // hlc fields intact, so distinct attendee payloads remain
        // distinct after scrubbing.
        loser_payload: Some(format!(
            r#"{{"attendee_id":"{attendee_id}","hlc":"{hlc}","title":"redacted"}}"#
        )),
        resolved_at: "2026-03-23T12:00:00.000Z".to_string(),
        resolution_type: Cow::Borrowed(envelope_constants.5),
    };

    log_conflict(&conn, &make_row("attendee-aaa", "h-1")).unwrap();
    log_conflict(&conn, &make_row("attendee-bbb", "h-2")).unwrap();
    log_conflict(&conn, &make_row("attendee-ccc", "h-3")).unwrap();

    let rows = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    assert_eq!(
        rows.len(),
        3,
        "distinct loser_payloads under the same envelope-key tuple must each persist"
    );
    let mut payloads: Vec<String> = rows
        .into_iter()
        .map(|r| r.loser_payload.unwrap_or_default())
        .collect();
    payloads.sort();
    assert!(payloads[0].contains("attendee-aaa"));
    assert!(payloads[1].contains("attendee-bbb"));
    assert!(payloads[2].contains("attendee-ccc"));
}

#[test]
fn multi_loser_in_one_envelope_identical_payloads_dedupe() {
    // Replay path: re-applying the same envelope (outbox retry
    // semantics) must not duplicate rows even when the envelope
    // emits multiple per-loser rows. Two byte-identical
    // `loser_payload` values under the same other-key tuple collapse
    // to one row. This protects the diagnostic surface from being
    // flooded by retries while #2878's per-loser visibility is kept
    // intact for genuinely distinct rows (covered by the sibling
    // test above).
    let conn = test_db();
    let entry = ConflictLogEntry {
        id: 0,
        entity_type: Cow::Borrowed(lorvex_domain::naming::EntityKind::CalendarEvent.as_str()),
        entity_id: "event-001".to_string(),
        winner_version: "1711234567891_0000_aaaaaaaaaaaaaaaa".to_string(),
        loser_version: "1711234567890_0000_bbbbbbbbbbbbbbbb".to_string(),
        loser_device_id: "device-002".to_string(),
        loser_payload: Some(
            r#"{"attendee_id":"attendee-aaa","hlc":"h-1","title":"redacted"}"#.to_string(),
        ),
        resolved_at: "2026-03-23T12:00:00.000Z".to_string(),
        resolution_type: Cow::Borrowed(naming::RESOLUTION_LWW),
    };

    log_conflict(&conn, &entry).unwrap();
    log_conflict(&conn, &entry).unwrap();
    log_conflict(&conn, &entry).unwrap();

    let rows = get_conflicts_by_type(&conn, naming::RESOLUTION_LWW, 10).unwrap();
    assert_eq!(
        rows.len(),
        1,
        "identical loser_payload replays must dedupe to a single row"
    );
}
