//! `batch_complete_habit`: canonical `{count, results}` response shape
//! (#3033-M10) and the all-or-nothing atomicity guarantee — any
//! per-id failure must roll back the entire batch.

use super::support::*;

/// #3033-M10 — `completed_count` was dead weight under the
/// atomic-batch contract (`count == completed_count` always),
/// so the field is dropped. The response is `{results, count}`
/// with no separate success counter; legacy `total` / `completed`
/// must not resurface either.
#[test]
#[serial_test::serial(hlc)]
fn batch_complete_habit_response_uses_canonical_count_fields() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000202", "Meditate");
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000203", "Exercise");

    let payload = batch_complete_habit(
        &conn,
        &[
            "01966a3f-7c8b-7d4e-8f3a-000000000202".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-000000000203".to_string(),
        ],
        Some("2026-03-29"),
    )
    .expect("batch_complete_habit should succeed");

    let value: serde_json::Value = serde_json::from_str(&payload).expect("valid json payload");

    assert_eq!(
        value["count"], 2,
        "`count` should equal length of returned results array"
    );
    assert_eq!(value["results"].as_array().expect("results array").len(), 2);
    // #3033-M10: `completed_count` was dead weight under atomic-batch
    // semantics and is gone. Pinning its absence keeps a future
    // re-introduction from sneaking back in.
    assert!(
        value.get("completed_count").is_none(),
        "#3033-M10: `completed_count` must not resurface — \
         atomic semantics make it duplicate of `count`"
    );
    // Legacy names must be gone.
    assert!(
        value.get("total").is_none(),
        "legacy `total` must not resurface"
    );
    assert!(
        value.get("completed").is_none(),
        "legacy `completed` must not resurface"
    );
}

/// any per-id failure rolls back the whole batch.
/// Pre-fix the loop swallowed the failure and reported a partial
/// success; the tool must now propagate the error so the outer
/// `with_conn` savepoint discards every preceding completion.
#[test]
#[serial_test::serial(hlc)]
fn batch_complete_habit_rejects_whole_batch_when_any_id_fails() {
    let conn = open_temp_db();
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000202", "Meditate");
    seed_habit(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000203", "Exercise");

    let err = batch_complete_habit(
        &conn,
        &[
            "01966a3f-7c8b-7d4e-8f3a-000000000202".to_string(),
            "habit-missing".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-000000000203".to_string(),
        ],
        Some("2026-03-29"),
    )
    .expect_err("missing habit id should propagate as a single error");

    let msg = err.to_string();
    assert!(
        msg.contains("habit-missing") || msg.contains("not found"),
        "error should describe the failing id, got: {msg}"
    );
}
