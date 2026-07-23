use super::*;
use lorvex_store::test_support::fixtures::TaskBuilder;

const EDGE_TASK_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000000301";
const EDGE_TAG_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000000302";
const EDGE_OTHER_TAG_ID: &str = "01966a3f-7c8b-7d4e-8f3a-000000000303";

/// Seed minimal `tags` / `calendar_events` / `habits` rows so FK
/// constraints on edge envelopes are satisfied. The task seed lifts
/// out to [`TaskBuilder`] (canonical-shape fixture) — these helpers
/// stay inline because they're 1-2 sites each and have no analogous
/// `*Builder` yet.
fn seed_tag(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES (?1, 'test', 'test', '0000000000000_0000_0000000000000000', '', '')",
        [id],
    )
    .unwrap();
}

#[test]
fn apply_edge_succeeds() {
    let conn = test_db();
    // Pre-create the task and tag so FK constraints are satisfied.
    TaskBuilder::new(EDGE_TASK_ID).title("T").insert(&conn);
    seed_tag(&conn, EDGE_TAG_ID);

    let mut env = make_envelope(
        naming::EDGE_TASK_TAG,
        &format!("{EDGE_TASK_ID}:{EDGE_TAG_ID}"),
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    env.payload =
        format!(r#"{{"task_id":"{EDGE_TASK_ID}","tag_id":"{EDGE_TAG_ID}","created_at":""}}"#);
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);
}

/// edge envelopes whose payload disagrees with
/// `entity_id` (e.g. payload's `task_id` does not match the first
/// half of the composite id) MUST be rejected as InvalidPayload at
/// the FK preflight boundary. Pre-fix, the EDGE_TASK_TAG branch
/// parsed payload while EDGE_TASK_DEPENDENCY parsed entity_id —
/// inconsistent. Post-fix, every edge cross-checks payload-vs-
/// entity_id before accepting the envelope.
#[test]
fn apply_edge_rejects_payload_vs_entity_id_mismatch() {
    let conn = test_db();
    TaskBuilder::new(EDGE_TASK_ID).title("T").insert(&conn);
    seed_tag(&conn, EDGE_TAG_ID);

    let mut env = make_envelope(
        naming::EDGE_TASK_TAG,
        &format!("{EDGE_TASK_ID}:{EDGE_TAG_ID}"),
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    // Payload's tag_id disagrees with entity_id half — the preflight
    // must reject as InvalidPayload before any SQL fires.
    env.payload =
        format!(r#"{{"task_id":"{EDGE_TASK_ID}","tag_id":"{EDGE_OTHER_TAG_ID}","created_at":""}}"#);

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(result, Err(ApplyError::InvalidPayload(_))),
        "expected InvalidPayload, got {result:?}"
    );
}

#[test]
fn apply_edge_rejects_malformed_composite_entity_id() {
    let conn = test_db();
    TaskBuilder::new(EDGE_TASK_ID).title("T").insert(&conn);
    seed_tag(&conn, EDGE_TAG_ID);

    let mut env = make_envelope(
        naming::EDGE_TASK_TAG,
        &format!("{EDGE_TASK_ID}:{EDGE_TAG_ID}:extra"),
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    env.payload =
        format!(r#"{{"task_id":"{EDGE_TASK_ID}","tag_id":"{EDGE_TAG_ID}","created_at":""}}"#);

    let result = apply_envelope(&conn, &env);
    assert!(
        matches!(result, Err(ApplyError::InvalidPayload(_))),
        "malformed composite edge ids must be rejected consistently, got {result:?}"
    );
}

#[test]
fn apply_all_known_edge_types() {
    let conn = test_db();
    // Pre-create entities that edges reference.
    TaskBuilder::new(DUMMY_UUID_A).title("T").insert(&conn);
    TaskBuilder::new(DUMMY_UUID_B).title("T2").insert(&conn);
    seed_tag(&conn, DUMMY_UUID_B);
    conn.execute(
        "INSERT INTO calendar_events (id, title, start_date, version, created_at, updated_at) \
         VALUES (?1, 'E', '2026-01-01', '0000000000000_0000_0000000000000000', '', '')",
        [DUMMY_UUID_B],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO habits (id, name, version, created_at, updated_at) \
         VALUES (?1, 'H', '0000000000000_0000_0000000000000000', '', '')",
        [DUMMY_UUID_A],
    )
    .unwrap();

    for edge_type in naming::ALL_EDGE_TYPES {
        let payload = make_payload_for_edge_type(edge_type);
        let entity_id = if *edge_type == naming::EDGE_HABIT_COMPLETION {
            format!("{DUMMY_UUID_A}:2026-01-01")
        } else {
            format!("{DUMMY_UUID_A}:{DUMMY_UUID_B}")
        };
        let env = SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::parse(edge_type)
                .expect("test edge_type must be a known EntityKind"),
            entity_id,
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
                .expect("test fixture version must be a canonical HLC"),
            payload_schema_version: PAYLOAD_SCHEMA_VERSION,
            payload,
            device_id: "remote-device".to_string(),
        };
        let result = apply_envelope(&conn, &env).unwrap();
        assert_eq!(
            result,
            ApplyResult::Applied,
            "should apply for edge type {edge_type}"
        );
    }
}
