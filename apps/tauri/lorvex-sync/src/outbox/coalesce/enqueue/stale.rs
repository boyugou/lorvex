//! Stale-incoming detection for the coalesce decision.
//!
//! Compares the incoming envelope's HLC against the queued row's
//! HLC; when the incoming side loses, the coalesce site preserves
//! the queued row untouched. The replacement branch lives in
//! [`super::body::enqueue_coalesced_body`].

use rusqlite::Connection;

use crate::envelope::SyncEnvelope;
use crate::outbox::coalesce::warn_dedup::is_recent_unparseable_warn_duplicate;

/// Compare the incoming envelope against the existing queued row's HLC.
/// Returns `true` when the incoming version is older than (or equal
/// to) the queued one, so the coalesce site preserves the existing
/// row. Tolerates a corrupted (legacy / hand-edited) existing version
/// by treating the canonical incoming HLC as the unambiguous winner —
/// and best-effort logs the corruption so it stays visible in the
/// diagnostics surface.
pub(super) fn incoming_is_stale(
    conn: &Connection,
    envelope: &SyncEnvelope,
    existing_version: &str,
) -> bool {
    let envelope_version_string = envelope.version.to_string();
    let envelope_lex = envelope_version_string.as_str();
    let existing_lex = existing_version;
    let existing_parse = lorvex_domain::hlc::Hlc::parse(existing_lex);
    existing_parse.as_ref().map_or_else(
        |_| {
            // Canonical incoming vs tainted existing — never-stale;
            // replace the predecessor. Letters (`'v1'`, `'seed'`)
            // sort ABOVE digits, so the historical lex-compare
            // fallback flipped here. The outbox row's `version`
            // column is rewritten in the same transaction so the
            // taint clears on the next coalesce. Best-effort
            // diagnostic so the corruption stays visible.
            let dedup_signature = format!(
                "{}|{}|incoming_ok=true|existing_ok=false",
                envelope.entity_type, envelope.entity_id,
            );
            if !is_recent_unparseable_warn_duplicate(conn, &dedup_signature) {
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "sync.outbox.coalesce_unparseable_version",
                    &format!(
                        "outbox coalesce LWW fallback for entity_type={}, entity_id={}, \
                         incoming={envelope_lex:?} (parsed=true), \
                         existing={existing_lex:?} (parsed=false)",
                        envelope.entity_type, envelope.entity_id,
                    ),
                    Some(&dedup_signature),
                    Some("warn"),
                );
            }
            false
        },
        |existing_hlc| &envelope.version <= existing_hlc,
    )
}
