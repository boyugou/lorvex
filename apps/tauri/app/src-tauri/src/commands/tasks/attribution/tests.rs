use super::*;

use crate::test_support::test_conn;

/// a peer-supplied `initiated_by` must
/// not flow through to the attribution panel verbatim. Bidi marks
/// (`U+202E`), zero-width characters (`U+200B` / `U+FEFF`),
/// and other control codepoints are scrubbed by
/// `lorvex_domain::sanitize_user_text` so a synced changelog row
/// cannot forge a visually-impersonating actor name.
#[test]
fn actor_from_initiated_by_strips_bidi_and_zero_width_injections() {
    // Right-to-left override + zero-width space + BOM tucked
    // inside an otherwise-plausible AI label.
    let raw = "plan\u{202E}ner\u{200B}_ai\u{FEFF}";
    let actor = actor_from_initiated_by(raw);
    assert_eq!(actor.kind, "ai");
    assert_eq!(
        actor.name, "planner_ai",
        "scrubbed name must drop bidi / zero-width / BOM bytes"
    );

    // The "human" sentinel is recognized even when wrapped in
    // injection bytes — sanitization runs before the case-folded
    // lookup, so the row still classifies as a human actor.
    let raw_human = "\u{200B}HUMAN\u{202E}";
    let human = actor_from_initiated_by(raw_human);
    assert_eq!(human.kind, "human");
    assert_eq!(human.name, "human");
}

#[test]
fn actor_from_initiated_by_treats_every_non_assistant_actor_as_human() {
    // The non-assistant actor set must match the changelog initiated_by filter
    // used by retention/export/query/import: {human, system, user, manual}.
    // "system" in particular must not render as an AI actor named "system".
    for raw in ["human", "system", "user", "manual", "SYSTEM", " System "] {
        let actor = actor_from_initiated_by(raw);
        assert_eq!(
            actor.kind, "human",
            "non-assistant actor {raw:?} must classify as human, not AI"
        );
    }
    // A genuine assistant label still renders as a named AI actor.
    assert_eq!(actor_from_initiated_by("claude").kind, "ai");
}

#[test]
fn get_task_attribution_matches_valid_batch_entity_ids_json() {
    let conn = test_conn();
    // lift to canonical TaskBuilder. The legacy raw INSERT used
    // distinct created_at / updated_at; preserve the gap.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000001")
        .title("Task 1")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T09:00:00Z")
        .updated_at("2026-03-29T09:00:02Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO ai_changelog (
            id, timestamp, operation, entity_type, entity_id, summary, initiated_by, mcp_tool
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        (
            "log-batch",
            "2026-03-29T09:00:00Z",
            "batch_create",
            "task",
            Option::<String>::None,
            "batched create",
            "planner_ai",
            "test",
        ),
    )
    .expect("insert changelog row");
    // Populate the `ai_changelog_entities` registry so the
    // attribution path's join branch surfaces this batch row for
    // task-1's lookup.
    lorvex_store::changelog::replace_changelog_entities(
        &conn,
        "log-batch",
        &[
            "01966a3f-7c8b-7d4e-8f3a-000000000001".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-000000000002".to_string(),
        ],
    )
    .expect("populate entity registry");

    let attribution = get_task_attribution_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001")
        .expect("batch entity_ids registry should resolve attribution")
        .expect("task attribution");

    assert_eq!(attribution.created_by.kind, "ai");
    assert_eq!(attribution.created_by.name, "planner_ai");
}
