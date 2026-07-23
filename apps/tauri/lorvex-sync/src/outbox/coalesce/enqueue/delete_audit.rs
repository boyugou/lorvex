//! Audit trail for the `Upsert(T1) → Delete(T2) → Upsert(T3)` collapse.
//!
//! When an Upsert is about to coalesce over a queued Delete the
//! Delete row gets overwritten in `sync_outbox`. Without an extra
//! audit hop, peer audit consumers that reconstruct lifecycle from
//! `ai_changelog` would never see that the cluster authored a
//! Delete at T2: the trail reads as "row created, row re-edited" —
//! losing the user-meaningful intent that the row was gone at T2
//! even if it was resurrected at T3.

use rusqlite::Connection;

use super::types::ExistingOutboxRow;
use crate::envelope::{SyncEnvelope, SyncOperation};
use lorvex_domain::naming::OP_DELETE;

/// Audit-log the dropped Delete envelope when an Upsert is about to
/// coalesce over a queued Delete. The shape `Upsert(T1) → Delete(T2)
/// → Upsert(T3)` collapses to just `Upsert(T3)` in the outbox (the
/// Delete row gets overwritten by this coalesce branch), but a peer's
/// audit consumer that reconstructs lifecycle from `ai_changelog`
/// would otherwise never see that the cluster authored a Delete at T2.
/// Without the trail, the lifecycle reads as "row created, row
/// re-edited" — losing the user-meaningful intent that the row was
/// gone at T2 even if it was resurrected at T3.
///
/// We record the dropped Delete as an `ai_changelog` row with operation
/// `sync.outbox.coalesced_delete_dropped` so it ships to peers via the
/// changelog-replication path and reaches every audit consumer (not
/// just the local `error_logs` table, which is device-local). The
/// `summary` carries the dropped entity_type/entity_id/version metadata
/// so peers can reconstruct intent without parsing structured fields.
///
/// Best-effort: any failure assembling or inserting the changelog row
/// must not abort the outbox enqueue. The coalesce itself is the
/// authoritative state mutation; the audit row is a peer-visible
/// reconstruction hint. Only fires when the existing op is Delete AND
/// the incoming op is Upsert — every other transition either preserves
/// the Delete (Delete → Delete) or genuinely supersedes it without
/// cluster-meaningful data loss (Upsert → Upsert).
pub(super) fn record_coalesced_delete_dropped(
    conn: &Connection,
    envelope: &SyncEnvelope,
    existing: &ExistingOutboxRow,
) {
    let (existing_version, existing_op) = existing;
    if existing_op.as_str() != OP_DELETE || !matches!(envelope.operation, SyncOperation::Upsert) {
        return;
    }
    let summary = format!(
        "outbox coalesce dropped a queued Delete: \
         entity_type={}, entity_id={}, dropped_delete_version={existing_version:?}, \
         superseding_upsert_version={}; peer audit consumers should reconstruct \
         the Delete intent from this entry",
        envelope.entity_type.as_str(),
        envelope.entity_id,
        envelope.version,
    );
    let Ok(device_id) = lorvex_runtime::get_or_create_device_id(conn) else {
        return;
    };
    let id = lorvex_domain::new_entity_id_string();
    let timestamp = lorvex_domain::sync_timestamp_now();
    let sanitized_summary = lorvex_store::changelog::sanitize_changelog_summary(&summary);
    let write_result = lorvex_store::changelog::write_changelog_row(
        conn,
        &lorvex_store::changelog::ChangelogRow {
            id: &id,
            timestamp: &timestamp,
            operation: "sync.outbox.coalesced_delete_dropped",
            entity_type: envelope.entity_type.as_str(),
            entity_id: Some(&envelope.entity_id),
            entity_ids: &[],
            summary: &sanitized_summary,
            initiated_by: "sync",
            mcp_tool: None,
            source_device_id: &device_id,
            before_json: None,
            after_json: None,
            undo_token: None,
            is_preview: false,
        },
    );
    // The audit row is a peer-visible reconstruction hint; the
    // coalesce itself is the authoritative state mutation. A failure
    // to write the row (FK violation, disk quota) must not abort the
    // so audit consumers saw "row created, row re-edited" with no
    // Delete between, and lifecycle reconstruction broke without any
    // diagnostic trail. Surface the failure through
    // `append_error_log_best_effort` so it shows up in Settings →
    // Diagnostics instead (#4583 B11).
    if let Err(err) = write_result {
        lorvex_store::error_log::append_error_log_best_effort(
            conn,
            "sync.outbox.coalesced_delete_changelog_failed",
            &format!(
                "failed to write audit changelog for dropped coalesced Delete: \
                 entity_type={}, entity_id={}, dropped_delete_version={:?}, error={err}",
                envelope.entity_type.as_str(),
                envelope.entity_id,
                existing_version,
            ),
            Some(&summary),
            Some("error"),
        );
    }
}
