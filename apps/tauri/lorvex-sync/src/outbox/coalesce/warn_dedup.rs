//! Warn-once dedup memo for `sync.outbox.coalesce_unparseable_version`.
//!
//! When the LWW fallback fires (incoming canonical vs tainted existing,
//! or vice versa), we want exactly one diagnostic per
//! `(entity_type, entity_id)` signature — both within a process and
//! across the cluster. A bounded FIFO short-circuits the in-process
//! repeats; the slow path consults `error_logs` so a fresh process
//! still defers to a peer that already wrote the warn.

use rusqlite::{Connection, OptionalExtension};

/// Probe `error_logs` (with a process-local FIFO short-circuit) to
/// decide whether a fresh `sync.outbox.coalesce_unparseable_version`
/// warn would duplicate an already-recorded one. Any DB error is
/// swallowed and treated as "not a duplicate" so a transient
/// diagnostic-table read failure never silences a fresh warn.
///
/// The memo's miss path still consults the DB so a fresh-process /
/// cross-process signature still triggers exactly one warn.
pub(in crate::outbox::coalesce) fn is_recent_unparseable_warn_duplicate(
    conn: &Connection,
    signature: &str,
) -> bool {
    // Fast path: this process already saw the same signature.
    if recently_warned_signatures()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .contains_signature(signature)
    {
        return true;
    }
    // Slow path: consult the DB. Either the signature is fresh (write
    // a warn + remember it) or another process already logged the
    // same signature (treat as duplicate and remember).
    let recent: Result<Option<Option<String>>, rusqlite::Error> = conn
        .query_row(
            "SELECT details FROM error_logs \
             WHERE source = 'sync.outbox.coalesce_unparseable_version' \
             ORDER BY created_at DESC LIMIT 1",
            [],
            |row| row.get::<_, Option<String>>(0),
        )
        .optional();
    let was_duplicate = matches!(&recent, Ok(Some(Some(prior))) if prior == signature);
    // Remember the signature regardless of the DB outcome: a fresh
    // signature now becomes the most-recent log row (so subsequent
    // envelopes within the process can short-circuit), and a
    // duplicate confirmed against the DB already had its row written
    // by some prior caller. The set is bounded — see
    // `RECENTLY_WARNED_SIGNATURES_CAP`.
    let mut guard = recently_warned_signatures()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    guard.insert_with_fifo_eviction(signature);
    drop(guard);
    was_duplicate
}

/// Hard cap on the number of distinct
/// `(entity_type, entity_id)` poison signatures the process retains
/// at any one time. A long-lived MCP session that touches many
/// retain every signature for the lifetime of the process; a heavy-
/// mutation peer could grow the set into the millions. 4096 is
/// large enough that a healthy workload never hits the cap (the set
/// only grows when the LWW fallback fires, i.e. only on tainted-
/// version rows). When the cap IS hit, [`SignatureFifo`] evicts the
/// oldest single entry instead of clearing the whole set — bounding
/// the worst-case "extra DB read" cost to one per evicted signature.
const RECENTLY_WARNED_SIGNATURES_CAP: usize = 4096;

/// Bounded FIFO with O(1) membership test for the warn-once memo.
/// Pairs a `HashSet` (for `contains` short-circuit) with a `VecDeque`
/// (for insertion order) so eviction at cap is `O(1)` and only drops
/// the single oldest entry rather than clearing every memo at once.
#[derive(Default)]
struct SignatureFifo {
    set: std::collections::HashSet<String>,
    order: std::collections::VecDeque<String>,
}

impl SignatureFifo {
    fn contains_signature(&self, signature: &str) -> bool {
        self.set.contains(signature)
    }

    fn insert_with_fifo_eviction(&mut self, signature: &str) {
        if self.set.contains(signature) {
            return;
        }
        if self.set.len() >= RECENTLY_WARNED_SIGNATURES_CAP {
            if let Some(oldest) = self.order.pop_front() {
                self.set.remove(&oldest);
            }
        }
        self.set.insert(signature.to_string());
        self.order.push_back(signature.to_string());
    }
}

fn recently_warned_signatures() -> &'static std::sync::Mutex<SignatureFifo> {
    static MEMO: std::sync::OnceLock<std::sync::Mutex<SignatureFifo>> = std::sync::OnceLock::new();
    MEMO.get_or_init(|| std::sync::Mutex::new(SignatureFifo::default()))
}
