use super::*;
use lorvex_domain::EventId;
use lorvex_store::open_db_in_memory;
use serde_json::json;

fn evt(id: &str) -> EventId {
    EventId::from_trusted(id.to_string())
}

fn seed_event(conn: &Connection, event_id: &str) {
    conn.execute(
        "INSERT INTO calendar_events
            (id, title, start_date, all_day, event_type, created_at, updated_at, version)
         VALUES (?1, 'T', '2026-01-01', 0, 'event', '', '', '1000000000000_0000_abcdef01abcdef01')",
        params![event_id],
    )
    .unwrap();
}

/// Seed a `calendar_event_attendees` row keyed by the synthesized
/// `attendee_id` for a plain email attendee (`email:<email>`).
fn seed_attendee(
    conn: &Connection,
    event_id: &str,
    email: &str,
    name: Option<&str>,
    status: Option<&str>,
) {
    conn.execute(
        "INSERT INTO calendar_event_attendees (event_id, attendee_id, email, name, status)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![event_id, format!("email:{email}"), email, name, status],
    )
    .unwrap();
}

#[test]
fn load_attendees_merges_extras() {
    let conn = open_db_in_memory().unwrap();
    seed_event(&conn, "evt-1");
    seed_attendee(&conn, "evt-1", "a@x", Some("Alice"), Some("accepted"));
    let mut extras = Map::new();
    extras.insert("role".to_string(), json!("chair"));
    replace_attendee_shadows(&conn, &evt("evt-1"), &[("email:a@x".to_string(), extras)]).unwrap();

    let loaded = load_attendees_with_extras(&conn, &evt("evt-1")).unwrap();
    assert_eq!(loaded.len(), 1);
    let obj = loaded[0].as_object().unwrap();
    assert_eq!(obj.get("email").unwrap(), "a@x");
    assert_eq!(obj.get("name").unwrap(), "Alice");
    assert_eq!(obj.get("role").unwrap(), "chair");
    // `attendee_id` is device-local and must never leak onto the wire object.
    assert!(obj.get("attendee_id").is_none());
}

#[test]
fn replace_deletes_all_then_reinserts() {
    let conn = open_db_in_memory().unwrap();
    seed_event(&conn, "evt-2");
    seed_attendee(&conn, "evt-2", "a@x", None, None);
    seed_attendee(&conn, "evt-2", "b@x", None, None);
    let mut extras_a = Map::new();
    extras_a.insert("role".to_string(), json!("chair"));
    let mut extras_b = Map::new();
    extras_b.insert("role".to_string(), json!("note-taker"));
    replace_attendee_shadows(
        &conn,
        &evt("evt-2"),
        &[
            ("email:a@x".to_string(), extras_a),
            ("email:b@x".to_string(), extras_b),
        ],
    )
    .unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendee_shadow WHERE event_id = 'evt-2'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 2);

    // Replace with only one attendee — the other's shadow row must go.
    let mut extras_a2 = Map::new();
    extras_a2.insert("role".to_string(), json!("observer"));
    replace_attendee_shadows(
        &conn,
        &evt("evt-2"),
        &[("email:a@x".to_string(), extras_a2)],
    )
    .unwrap();
    let remaining: Vec<String> = conn
        .prepare("SELECT attendee_id FROM calendar_event_attendee_shadow WHERE event_id = 'evt-2' ORDER BY attendee_id")
        .unwrap()
        .query_map([], |r| r.get::<_, String>(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(remaining, vec!["email:a@x".to_string()]);
}

#[test]
fn batch_loader_returns_empty_vec_for_event_without_attendees() {
    let conn = open_db_in_memory().unwrap();
    seed_event(&conn, "evt-empty");
    let by_event = load_attendees_with_extras_for_events(&conn, &["evt-empty"]).unwrap();
    assert_eq!(by_event.len(), 1);
    assert!(by_event.get("evt-empty").unwrap().is_empty());
}

#[test]
fn batch_loader_groups_attendees_by_event() {
    let conn = open_db_in_memory().unwrap();
    seed_event(&conn, "evt-a");
    seed_event(&conn, "evt-b");
    seed_event(&conn, "evt-c");
    seed_attendee(&conn, "evt-a", "a1@x", Some("A1"), Some("accepted"));
    seed_attendee(&conn, "evt-a", "a2@x", Some("A2"), None);
    seed_attendee(&conn, "evt-b", "b1@x", None, Some("declined"));
    let mut extras_a1 = Map::new();
    extras_a1.insert("role".to_string(), json!("chair"));
    replace_attendee_shadows(
        &conn,
        &evt("evt-a"),
        &[("email:a1@x".to_string(), extras_a1)],
    )
    .unwrap();

    let by_event =
        load_attendees_with_extras_for_events(&conn, &["evt-a", "evt-b", "evt-c"]).unwrap();
    assert_eq!(by_event.len(), 3);

    let a = by_event.get("evt-a").unwrap();
    assert_eq!(a.len(), 2);
    // ORDER BY a.attendee_id — email:a1@x before email:a2@x.
    assert_eq!(a[0].as_object().unwrap().get("email").unwrap(), "a1@x");
    assert_eq!(a[0].as_object().unwrap().get("role").unwrap(), "chair");
    assert_eq!(a[1].as_object().unwrap().get("email").unwrap(), "a2@x");

    let b = by_event.get("evt-b").unwrap();
    assert_eq!(b.len(), 1);
    assert_eq!(b[0].as_object().unwrap().get("email").unwrap(), "b1@x");

    // evt-c has no attendees but the map must still carry an empty
    // vector so callers can distinguish "no attendees" from
    // "unknown event id".
    assert!(by_event.get("evt-c").unwrap().is_empty());
}

#[test]
fn batch_loader_dedupes_repeated_input_ids() {
    let conn = open_db_in_memory().unwrap();
    seed_event(&conn, "evt-dup");
    seed_attendee(&conn, "evt-dup", "d@x", None, None);
    let by_event = load_attendees_with_extras_for_events(&conn, &["evt-dup", "evt-dup"]).unwrap();
    assert_eq!(by_event.len(), 1);
    assert_eq!(by_event.get("evt-dup").unwrap().len(), 1);
}

#[test]
fn batch_loader_handles_empty_input() {
    let conn = open_db_in_memory().unwrap();
    let by_event = load_attendees_with_extras_for_events(&conn, &[]).unwrap();
    assert!(by_event.is_empty());
}

#[test]
fn empty_extras_removes_row() {
    let conn = open_db_in_memory().unwrap();
    seed_event(&conn, "evt-3");
    seed_attendee(&conn, "evt-3", "a@x", None, None);
    let mut extras = Map::new();
    extras.insert("role".to_string(), json!("chair"));
    replace_attendee_shadows(&conn, &evt("evt-3"), &[("email:a@x".to_string(), extras)]).unwrap();
    // Re-replace with an empty rowset — the shadow row for the
    // single attendee must be deleted (purge-on-absence).
    replace_attendee_shadows(&conn, &evt("evt-3"), &[]).unwrap();
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendee_shadow WHERE event_id = 'evt-3'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 0);
}
