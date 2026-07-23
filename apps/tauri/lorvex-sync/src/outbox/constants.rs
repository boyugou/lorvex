/// Maximum number of retries before an outbox entry is considered permanently
/// failed and excluded from `get_pending`. Failed entries are cleaned up by
/// `gc_synced` after a retention period.
pub const MAX_RETRIES: i64 = 10;

/// (#3054 H3) cap on the number of outbox rows materialized by a single
/// `get_pending` call. The push pipeline fetch the entire
/// pending set in one shot, so a 10k-row backlog allocated 10k owned
/// `OutboxEntry` values (each carrying a payload up to
/// `MAX_ENVELOPE_PAYLOAD_BYTES = 1 MiB`) inside a single transaction
/// before any of them got pushed. Capping at 1000 lets the next push
/// cycle drain the next slice — the same chunk-then-loop pattern
/// `record_many_retries` already uses (see `CHUNK = 500` further down
/// this file). Production push paths re-trigger naturally on the next
/// sync tick.
pub const MAX_PENDING_FETCH: i64 = 1000;

/// cap on `sync_outbox.last_error`. Provider / network /
/// SQLite error chains can balloon to tens of kilobytes when a peer
/// attaches an envelope dump or a chained cause. The same-error
/// escalation only needs a stable byte-equality key, so trim every
/// stored error string at this byte budget. 4 KiB is generous enough
/// to capture the error kind + first cause line for every realistic
/// backend, tight enough that a single pathological row cannot bloat
/// the outbox.
pub const OUTBOX_LAST_ERROR_MAX_BYTES: usize = 4096;

/// Truncate an error string to [`OUTBOX_LAST_ERROR_MAX_BYTES`] without
/// splitting a UTF-8 code point. Public so the bulk-retry path
/// (`record_many_retries`) and any future writer can apply the same
/// cap as the per-row `record_retry` helper.
pub fn truncate_outbox_last_error(error: &str) -> String {
    if error.len() <= OUTBOX_LAST_ERROR_MAX_BYTES {
        return error.to_string();
    }
    // Walk back to the nearest char boundary at or below the cap so
    // the truncated string is still valid UTF-8 (UTF-8 code points
    // are 1-4 bytes). `floor_char_boundary` is unstable; do this
    // manually to keep the helper on stable Rust.
    let mut end = OUTBOX_LAST_ERROR_MAX_BYTES;
    while end > 0 && !error.is_char_boundary(end) {
        end -= 1;
    }
    error[..end].to_string()
}
/// Minimum retry count before the "same error repeated" heuristic
/// escalates a row to `MAX_RETRIES`. Three identical
/// failures in a row is strong evidence the failure is permanent
/// (malformed payload, schema mismatch, oversized record, etc.); at
/// that point we jump straight to the exhausted state instead of
/// burning the remaining retry budget on the same futile error.
pub const SAME_ERROR_ESCALATION_THRESHOLD: i64 = 3;
pub(super) const RECORD_MANY_RETRIES_SENTINEL_ID: i64 = -1;
