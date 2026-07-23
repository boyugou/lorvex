use crate::error::{AppError, AppResult};
use lorvex_sync::outbox;

pub(super) fn outbox_backoff_seconds(retry_count: i64) -> i64 {
    let base: i64 = 30;
    let max: i64 = 3600;
    let exponent = (retry_count - 1).clamp(0, 10) as u32;
    let deterministic = std::cmp::min(base.saturating_mul(2_i64.saturating_pow(exponent)), max);
    let jitter_range = (deterministic / 10).max(1);
    // Audit (post-#2457): the previous expression
    //   `(rng_next() as i64) % (jitter_range * 2 + 1) - jitter_range`
    // bit-flipped the high RNG bit on `u64 → i64` cast, and Rust's `%`
    // follows the dividend's sign — so half of all draws were already
    // negative before subtracting `jitter_range`, falling outside the
    // intended ±range and clamped to the 1-second floor by the
    // trailing `.max(1)`. That defeated the very thundering-herd
    // jitter the comment above promises (N devices fight for the lock
    // at the same 1-second mark — worse correlation than no jitter).
    // Keep the overflow fix: take `%` on the unsigned modulus
    // first, THEN cast to i64 and shift into the symmetric range.
    let divisor = (jitter_range * 2 + 1) as u64;
    let jitter = (fs_bridge_jitter_rng_next() % divisor) as i64 - jitter_range;
    (deterministic + jitter).max(1)
}

/// Process-local xorshift64* jitter stream for filesystem-bridge
/// backoff. Seeded once from SystemTime + process id (same approach as
/// the shared jitter helper, #2466) so devices that share wall-clock
/// state via NTP still diverge via process identity. The implementation
/// uses `lorvex_runtime::JitterRng` — see #2749
/// for the consolidation that removed the duplicate of this helper.
fn fs_bridge_jitter_rng_next() -> u64 {
    use std::sync::{Mutex, OnceLock};
    static RNG: OnceLock<Mutex<lorvex_runtime::JitterRng>> = OnceLock::new();
    let rng = RNG.get_or_init(|| Mutex::new(lorvex_runtime::JitterRng::from_entropy()));
    match rng.lock() {
        Ok(mut guard) => guard.next_u64(),
        // See the shared sync-support poison handling rationale — poisoning
        // just means zero jitter this tick.
        Err(poisoned) => poisoned.into_inner().next_u64(),
    }
}

pub(super) fn record_outbox_retry(
    conn: &rusqlite::Connection,
    outbox_id: i64,
    now: &str,
) -> AppResult<()> {
    // Surface permanent exhaustion to diagnostics. The filesystem-bridge
    // path calls record_retry from multiple sites (missing blob, bad
    // envelope, remote-dir unreachable, etc.), so this records the first
    // transition into MAX_RETRIES for each row.
    // filesystem-bridge callers don't currently thread a
    // structured error message into this helper (the string is logged
    // separately via structured diagnostics). Pass None so the outbox
    // row's `last_error` column is untouched; same-error escalation
    // remains available once a caller supplies the error inline.
    let outcome = outbox::record_retry(conn, outbox_id, now, None).map_err(AppError::from)?;
    if outcome.exhausted_now {
        crate::commands::diagnostics::append_error_log_best_effort(
            "sync.filesystem_bridge.outbox_exhausted",
            &format!(
                "Filesystem-bridge outbox entry {outbox_id} permanently failed after {} attempts — this write never reached the sync folder.",
                lorvex_sync::outbox::MAX_RETRIES,
            ),
            None,
            Some("error".to_string()),
        );
    }
    Ok(())
}

pub(super) fn should_skip_outbox_for_backoff(
    entry: &outbox::OutboxEntry,
    now: &chrono::DateTime<chrono::Utc>,
) -> bool {
    /// Maximum interval beyond which a `last_retry_at` is treated as
    /// stale and ignored. 7× the cap of `outbox_backoff_seconds`
    /// (3600 s) gives a generous tolerance for legitimately-slow
    /// retry queues without indefinitely pinning rows after a
    /// pathological clock jump.
    const MAX_BACKOFF_FLOOR_SECS: i64 = 7 * 3600;

    if entry.retry_count >= outbox::MAX_RETRIES {
        return true;
    }
    if entry.retry_count == 0 {
        return false;
    }
    if let Some(ref last_retry) = entry.last_retry_at {
        if let Ok(last) = chrono::DateTime::parse_from_rfc3339(last_retry) {
            let last_utc = last.with_timezone(&chrono::Utc);
            // Clock went backward: persisted timestamp is in the
            // future. Ignore the stale wait and let the row retry.
            if last_utc > *now {
                return false;
            }
            // Clock went forward (or persisted row is genuinely
            // ancient): treat as fresh.
            let elapsed = now.signed_duration_since(last_utc);
            if elapsed.num_seconds() > MAX_BACKOFF_FLOOR_SECS {
                return false;
            }
            let wait = chrono::Duration::seconds(outbox_backoff_seconds(entry.retry_count));
            return *now < last_utc + wait;
        }
    }
    false
}
