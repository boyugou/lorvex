#[allow(unused_imports)]
use super::super::*;
use super::support::*;

#[test]
fn pending_entry_ids_for_drain_uses_last_attempted_ordering_index() {
    let conn = test_db();
    let plan = explain_query_plan_details(
        &conn,
        "SELECT id
         FROM sync_pending_inbox
         ORDER BY last_attempted_at ASC, id ASC
         LIMIT ?1",
        params![50_i64],
    );

    assert!(
        plan.iter()
            .any(|detail| detail.contains("idx_sync_pending_inbox_drain")),
        "pending inbox drain must use idx_sync_pending_inbox_drain, got plan: {plan:#?}"
    );
}

#[test]
fn pending_expiry_queries_use_first_attempted_index() {
    let conn = test_db();
    let horizon = "-90 days";
    let has_expired_plan = explain_query_plan_details(
        &conn,
        "SELECT COUNT(*) FROM sync_pending_inbox
         WHERE first_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        params![horizon],
    );
    assert!(
        has_expired_plan
            .iter()
            .any(|detail| detail.contains("idx_sync_pending_inbox_first_attempted")),
        "pending inbox expiry probe must use idx_sync_pending_inbox_first_attempted, got plan: {has_expired_plan:#?}"
    );

    let gc_plan = explain_query_plan_details(
        &conn,
        "DELETE FROM sync_pending_inbox
         WHERE first_attempted_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        params![horizon],
    );
    assert!(
        gc_plan
            .iter()
            .any(|detail| detail.contains("idx_sync_pending_inbox_first_attempted")),
        "pending inbox expiry GC must use idx_sync_pending_inbox_first_attempted, got plan: {gc_plan:#?}"
    );
}
