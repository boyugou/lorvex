use super::super::apply_calendar_event_upsert;
use super::support::*;
use serde_json::json;

fn event_payload(attendees: serde_json::Value) -> String {
    json!({
        "title": "Standup",
        "start_date": "2026-04-20",
        "all_day": false,
        "event_type": "event",
        "created_at": "2026-04-20T09:00:00.000Z",
        "updated_at": "2026-04-20T09:00:00.000Z",
        "attendees": attendees,
    })
    .to_string()
}

#[test]
fn unknown_attendee_field_round_trips_through_shadow() {
    // Simulate the v3 → v2 → v3 hop: a newer peer sends an
    // attendee with a surplus `role` field. The local apply
    // captures `role` in the attendee shadow, and the next
    // outbound enqueue (modeled here by
    // `load_attendees_with_extras`) re-emits it unchanged.
    let conn = test_db();
    let event_id = "evt-2317-roundtrip";
    let payload = event_payload(json!([
        {
            "email": "alice@example.com",
            "name": "Alice",
            "status": "accepted",
            "role": "chair",
            "rsvp_deadline": "2026-04-19T17:00:00Z",
        }
    ]));
    apply_calendar_event_upsert(&conn, event_id, &payload, &next_version(), false.into(), "")
        .unwrap();

    // Known fields landed in the primary table.
    let primary: (String, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT email, name, status FROM calendar_event_attendees WHERE event_id = ?1",
            [event_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(primary.0, "alice@example.com");
    assert_eq!(primary.1.as_deref(), Some("Alice"));
    assert_eq!(primary.2.as_deref(), Some("accepted"));

    // Surplus keys landed in the shadow, keyed by the synthesized
    // `attendee_id` (`email:<email>` for an email attendee).
    let shadow_json: String = conn
        .query_row(
            "SELECT extra_fields_json FROM calendar_event_attendee_shadow
                 WHERE event_id = ?1 AND attendee_id = ?2",
            [event_id, "email:alice@example.com"],
            |row| row.get(0),
        )
        .unwrap();
    let shadow: serde_json::Value = serde_json::from_str(&shadow_json).unwrap();
    assert_eq!(shadow.get("role").and_then(|v| v.as_str()), Some("chair"));
    assert_eq!(
        shadow.get("rsvp_deadline").and_then(|v| v.as_str()),
        Some("2026-04-19T17:00:00Z")
    );

    // Re-echo: the merged view used by both the MCP enrich path
    // and the app seed path reassembles the surplus keys into
    // each attendee object.
    let typed_event_id = lorvex_domain::EventId::from_trusted(event_id.to_string());
    let merged =
        lorvex_sync_payload::attendee_shadow::load_attendees_with_extras(&conn, &typed_event_id)
            .unwrap();
    assert_eq!(merged.len(), 1);
    let att = &merged[0];
    assert_eq!(
        att.get("email").and_then(|v| v.as_str()),
        Some("alice@example.com")
    );
    assert_eq!(att.get("role").and_then(|v| v.as_str()), Some("chair"));
    assert_eq!(
        att.get("rsvp_deadline").and_then(|v| v.as_str()),
        Some("2026-04-19T17:00:00Z")
    );
}

#[test]
fn removing_attendee_purges_shadow_row() {
    // A later envelope that drops the attendee entirely (or
    // replaces them with a different email) must purge the
    // shadow row — otherwise a future attendee with the same
    // email would inherit stale extras.
    let conn = test_db();
    let event_id = "evt-2317-removal";

    // Seed with two attendees, both carrying extras.
    let payload_v1 = event_payload(json!([
        { "email": "alice@example.com", "role": "chair" },
        { "email": "bob@example.com", "role": "note-taker" }
    ]));
    apply_calendar_event_upsert(
        &conn,
        event_id,
        &payload_v1,
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();
    let shadow_count_v1: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendee_shadow WHERE event_id = ?1",
            [event_id],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(shadow_count_v1, 2, "both extras must land in shadow");

    // Second envelope drops Bob entirely.
    let payload_v2 = event_payload(json!([
        { "email": "alice@example.com", "role": "observer" }
    ]));
    apply_calendar_event_upsert(
        &conn,
        event_id,
        &payload_v2,
        &next_version(),
        false.into(),
        "",
    )
    .unwrap();

    // Only Alice's shadow row remains; her role was overwritten,
    // Bob's row is gone.
    let rows: Vec<(String, String)> = conn
        .prepare(
            "SELECT attendee_id, extra_fields_json FROM calendar_event_attendee_shadow
                 WHERE event_id = ?1 ORDER BY attendee_id",
        )
        .unwrap()
        .query_map([event_id], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(rows.len(), 1, "bob's shadow row must be purged");
    assert_eq!(rows[0].0, "email:alice@example.com");
    let shadow: serde_json::Value = serde_json::from_str(&rows[0].1).unwrap();
    assert_eq!(
        shadow.get("role").and_then(|v| v.as_str()),
        Some("observer")
    );
}

#[test]
fn underscore_partstat_is_rejected_as_invalid_payload() {
    // Closing #3946: legacy `needs_action` is no longer repaired on
    // sync apply. The schema and write surfaces accept only the RFC
    // 5545 hyphen spelling, and inbound sync uses the same strict
    // contract so old wire payloads fail closed instead of being
    // normalized.
    let conn = test_db();
    let event_id = "evt-2953-needs-action-underscore";
    let payload = event_payload(json!([
        { "email": "alice@example.com", "status": "needs_action" }
    ]));
    let err =
        apply_calendar_event_upsert(&conn, event_id, &payload, &next_version(), false.into(), "")
            .expect_err("legacy underscore PARTSTAT must be rejected");
    let msg = err.to_string();
    assert!(
        msg.contains("needs_action") && msg.contains("not a recognized RFC 5545 PARTSTAT"),
        "diagnostic should name the legacy value and the contract, got: {msg}"
    );

    let stored: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendees WHERE event_id = ?1",
            [event_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored, 0,
        "rejected legacy PARTSTAT must not materialize an attendee row"
    );
}

#[test]
fn unrecognized_partstat_value_is_rejected_as_invalid_payload() {
    // Closing #3946: only the canonical RFC 5545 PARTSTAT subset is
    // accepted. A truly unknown value must surface as
    // `InvalidPayload` so the apply orchestrator can defer / log
    // the bad envelope rather than letting it ride to a row where
    // the schema CHECK would reject it with a less-actionable
    // SQLite error.
    let conn = test_db();
    let event_id = "evt-2953-unknown-partstat";
    let payload = event_payload(json!([
        { "email": "alice@example.com", "status": "delegated" }
    ]));
    let err =
        apply_calendar_event_upsert(&conn, event_id, &payload, &next_version(), false.into(), "")
            .expect_err("unknown PARTSTAT value must be rejected");
    let msg = err.to_string();
    assert!(
        msg.contains("delegated") && msg.contains("not a recognized RFC 5545 PARTSTAT"),
        "diagnostic should name the bad value and the contract, got: {msg}"
    );
}

// -----------------------------------------------------------------
// deterministic email-collision resolution.
//
// Two attendee entries that collapse to the same normalized email
// (`trim().to_lowercase()`) cannot share a primary `calendar_event_attendees`
// row. Pre-fix, `INSERT OR IGNORE` silently dropped the second
// entry at SQL level, but the second entry's surplus extras still
// reached `attendee_shadow_rows`; the LEFT JOIN in
// `replace_attendee_shadows` then paired the LATER extras with the
// EARLIER attendee, fusing two peers' metadata under one row with
// no diagnostic trail. The apply pipeline now picks a single
// deterministic winner per normalized email
// (lexicographically-smallest canonical-JSON of the entry) and
// emits one `attendee_email_collision` row per dropped entry so
// the audit surface names exactly what was lost.
// -----------------------------------------------------------------

fn count_collision_log_rows(conn: &rusqlite::Connection, event_id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_conflict_log
             WHERE entity_type = ?1
               AND entity_id = ?2
               AND resolution_type = ?3",
        rusqlite::params![
            lorvex_domain::naming::ENTITY_CALENDAR_EVENT,
            event_id,
            lorvex_domain::naming::RESOLUTION_ATTENDEE_EMAIL_COLLISION,
        ],
        |row| row.get(0),
    )
    .unwrap()
}

fn loaded_attendee_extras(
    conn: &rusqlite::Connection,
    event_id: &str,
    attendee_id: &str,
) -> Option<serde_json::Value> {
    conn.query_row(
        "SELECT extra_fields_json FROM calendar_event_attendee_shadow
             WHERE event_id = ?1 AND attendee_id = ?2",
        [event_id, attendee_id],
        |row| row.get::<_, String>(0),
    )
    .ok()
    .map(|raw| serde_json::from_str(&raw).unwrap())
}

#[test]
fn single_attendee_no_collision_baseline_logs_no_conflict() {
    // Baseline: a single, unambiguous attendee must land cleanly,
    // populate the primary table, round-trip its surplus through
    // the shadow, and emit zero conflict-log rows. Pins that the
    // resolution pass is a no-op when there is nothing to resolve.
    let conn = test_db();
    let event_id = "evt-2878-baseline-single";
    let payload = event_payload(json!([
        { "email": "Alice@Example.com", "name": "Alice", "status": "accepted",
          "role": "chair" }
    ]));
    apply_calendar_event_upsert(&conn, event_id, &payload, &next_version(), false.into(), "")
        .expect("single-attendee payload must apply cleanly");

    let primary_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendees WHERE event_id = ?1",
            [event_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(primary_count, 1, "exactly one primary row must land");

    let stored_email: String = conn
        .query_row(
            "SELECT email FROM calendar_event_attendees WHERE event_id = ?1",
            [event_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored_email, "alice@example.com",
        "email must be stored in the canonical lowercased form"
    );

    let shadow = loaded_attendee_extras(&conn, event_id, "email:alice@example.com")
        .expect("surplus `role` must round-trip via the shadow");
    assert_eq!(
        shadow.get("role").and_then(|v| v.as_str()),
        Some("chair"),
        "shadow must carry the attendee's surplus role unchanged"
    );

    assert_eq!(
        count_collision_log_rows(&conn, event_id),
        0,
        "no collision means no conflict-log row"
    );
}

#[test]
fn email_collision_with_different_status_resolves_deterministically() {
    // Two entries collide on email after `trim().to_lowercase()`
    // but disagree on `status` (a delegate accepted, a delegator
    // declined). The apply pipeline must:
    //   1. Insert exactly one primary row.
    //   2. Pick the winner deterministically — the entry whose
    //      canonical-JSON sorts lexicographically smallest. Because
    //      JSON object keys are sorted in canonical form,
    //      `{"email":...,"status":"accepted"}` < `{"email":...,"status":"declined"}`
    //      ('a' < 'd' at the first differing character). The
    //      "accepted" entry wins; the "declined" entry is logged.
    //   3. Emit ONE `attendee_email_collision` row carrying the
    //      dropped entry as `loser_payload` (post-PII-scrub).
    let conn = test_db();
    let event_id = "evt-2878-status-collision";
    let payload = event_payload(json!([
        { "email": "Alice@Example.com", "status": "declined" },
        { "email": "alice@example.com", "status": "accepted" }
    ]));
    apply_calendar_event_upsert(&conn, event_id, &payload, &next_version(), false.into(), "")
        .expect("collision must resolve, not reject");

    let primary: (String, Option<String>) = conn
        .query_row(
            "SELECT email, status FROM calendar_event_attendees WHERE event_id = ?1",
            [event_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(primary.0, "alice@example.com");
    assert_eq!(
        primary.1.as_deref(),
        Some("accepted"),
        "deterministic tiebreaker keeps the lex-smallest canonical-JSON \
             entry; 'accepted' < 'declined' at the canonical-JSON byte level"
    );

    assert_eq!(
        count_collision_log_rows(&conn, event_id),
        1,
        "exactly one loser must be audited"
    );

    let logged_payload: String = conn
        .query_row(
            "SELECT loser_payload FROM sync_conflict_log
                 WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3",
            rusqlite::params![
                lorvex_domain::naming::ENTITY_CALENDAR_EVENT,
                event_id,
                lorvex_domain::naming::RESOLUTION_ATTENDEE_EMAIL_COLLISION,
            ],
            |row| row.get(0),
        )
        .unwrap();
    // `log_conflict` runs the payload through the PII scrubber
    // (`attendees` is a PII-bearing key, so the email-bearing
    // entry will be redacted at the array-of-attendees level —
    // but the `status` key is structural and survives so the
    // diagnostics surface can still tell the user which entry
    // status was on the dropped peer).
    assert!(
        logged_payload.contains("declined"),
        "loser_payload must preserve the dropped status so the \
             user can audit what was lost, got: {logged_payload}"
    );
}

#[test]
fn email_collision_with_attendee_extras_does_not_fuse_metadata() {
    // The pre-fix bug: extras from the LATER colliding entry
    // would silently overwrite the EARLIER entry's extras under
    // one row. Pin that the deterministic winner's extras stand
    // alone — the loser's extras are NOT folded into the surviving
    // shadow row, but ARE recoverable from the conflict-log
    // `loser_payload`.
    //
    // Expected winner: the entry whose canonical-JSON (sorted
    // keys, compact, with email normalized) sorts lexicographically
    // smallest. Here entry B's key set is
    // {`delegated_to`, `email`, `role`} and entry A's is
    // {`email`, `role`, `rsvp_deadline`}. Sorted-keys canonical
    // form for B begins `{"delegated_to":...` while A begins
    // `{"email":...`; 'd' < 'e' at the first differing byte, so
    // B (the `secretary` / delegate entry) wins. Entry A becomes
    // the loser. This is fully content-determined: any peer
    // observing the same set of colliding entries picks the same
    // winner.
    let conn = test_db();
    let event_id = "evt-2878-extras-collision";
    let payload = event_payload(json!([
        // Loser: keys begin with `email` ('e' beats 'd' below).
        { "email": "Bob@Example.com", "role": "note-taker",
          "rsvp_deadline": "2026-04-19T17:00:00Z" },
        // Winner: leading `delegated_to` key sorts the canonical
        // form to the smallest byte sequence.
        { "email": "bob@example.com", "role": "secretary",
          "delegated_to": "carol@example.com" }
    ]));
    apply_calendar_event_upsert(&conn, event_id, &payload, &next_version(), false.into(), "")
        .expect("collision must resolve, not reject");

    let primary_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendees WHERE event_id = ?1",
            [event_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        primary_count, 1,
        "only one row may carry email='bob@example.com'"
    );

    // Winner's shadow extras stand alone. CRITICALLY: the
    // loser's `rsvp_deadline` MUST NOT appear here — that was the
    // exact silent fusion the pre-fix LEFT JOIN produced.
    let shadow = loaded_attendee_extras(&conn, event_id, "email:bob@example.com")
        .expect("winner's extras must round-trip via the shadow");
    assert_eq!(
        shadow.get("role").and_then(|v| v.as_str()),
        Some("secretary"),
        "winner's role must dominate"
    );
    assert_eq!(
        shadow.get("delegated_to").and_then(|v| v.as_str()),
        Some("carol@example.com"),
        "winner's delegated_to must round-trip via the shadow"
    );
    assert!(
        shadow.get("rsvp_deadline").is_none(),
        "loser's `rsvp_deadline` must NOT bleed into the winner's \
             shadow — that fusion was the silent-corruption pre-fix bug"
    );

    // The dropped peer's metadata is auditable via conflict_log.
    let logged_payload: String = conn
        .query_row(
            "SELECT loser_payload FROM sync_conflict_log
                 WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3",
            rusqlite::params![
                lorvex_domain::naming::ENTITY_CALENDAR_EVENT,
                event_id,
                lorvex_domain::naming::RESOLUTION_ATTENDEE_EMAIL_COLLISION,
            ],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        logged_payload.contains("rsvp_deadline") && logged_payload.contains("note-taker"),
        "loser_payload must carry the dropped attendee's surplus \
             keys so the user can recover them, got: {logged_payload}"
    );
}

#[test]
fn three_way_email_collision_emits_two_loser_log_rows() {
    // A pathological envelope with THREE entries colliding on the
    // same normalized email. Exactly one must survive to the
    // primary table; the other TWO must each produce their own
    // conflict-log row (the audit surface needs one row per
    // dropped peer, not one row per collision-event).
    let conn = test_db();
    let event_id = "evt-2878-three-way";
    let payload = event_payload(json!([
        // Three entries differing only on `role`. Canonical-JSON
        // byte order: `chair` < `note-taker` < `secretary`, so
        // the `chair` entry wins.
        { "email": "carol@example.com", "role": "secretary" },
        { "email": "Carol@Example.com", "role": "chair" },
        { "email": "  carol@EXAMPLE.com  ", "role": "note-taker" }
    ]));
    apply_calendar_event_upsert(&conn, event_id, &payload, &next_version(), false.into(), "")
        .expect("three-way collision must resolve, not reject");

    let primary_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendees WHERE event_id = ?1",
            [event_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        primary_count, 1,
        "three colliding entries collapse to exactly one row"
    );

    let shadow = loaded_attendee_extras(&conn, event_id, "email:carol@example.com")
        .expect("winner's shadow must exist");
    assert_eq!(
        shadow.get("role").and_then(|v| v.as_str()),
        Some("chair"),
        "lex-smallest canonical-JSON wins; 'chair' < 'note-taker' < 'secretary'"
    );

    assert_eq!(
        count_collision_log_rows(&conn, event_id),
        2,
        "two losers must produce two conflict-log rows — one per dropped peer"
    );

    // Verify each loser's surplus role is auditable (one row per
    // dropped peer carries that peer's payload). Collect the
    // logged role values and check both losers are present.
    let mut stmt = conn
        .prepare(
            "SELECT loser_payload FROM sync_conflict_log
                 WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3
                 ORDER BY id",
        )
        .unwrap();
    let payloads: Vec<String> = stmt
        .query_map(
            rusqlite::params![
                lorvex_domain::naming::ENTITY_CALENDAR_EVENT,
                event_id,
                lorvex_domain::naming::RESOLUTION_ATTENDEE_EMAIL_COLLISION,
            ],
            |row| row.get::<_, Option<String>>(0),
        )
        .unwrap()
        .map(|r| r.unwrap().unwrap_or_default())
        .collect();
    assert_eq!(payloads.len(), 2);
    let combined = payloads.join("\n");
    assert!(
        combined.contains("note-taker") && combined.contains("secretary"),
        "both losers' surplus roles must be preserved across the \
             two conflict-log rows, got: {combined}"
    );
}
