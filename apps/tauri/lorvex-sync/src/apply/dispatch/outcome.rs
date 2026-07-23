//! Outcome of dispatching a single envelope to its registered handler.
//!
//! Extracted from `dispatch/mod.rs` so the typed outcome enum lives
//! beside its sole consumer in `apply::envelope::delete_flow` without
//! bringing the rest of the dispatcher's fn-pointer table along for
//! the ride. The variants are load-bearing across the whole apply
//! pipeline — see `dispatch_impl::dispatch` and
//! `dispatch_impl::post_handler_lww_outcome` for the producers, and
//! `apply::envelope::delete_flow` for the tombstone-vs-defer decision
//! that consumes them.

/// Outcome of dispatching a single envelope to its handler.
///
/// distinguish "delete fully applied / intentionally
/// skipped" from "delete refused by the handler's in-handler LWW
/// gate". The caller in `apply_envelope` uses the variant to decide
/// whether to create the tombstone row downstream.
///
/// - `Applied` covers four cases that all need the tombstone written:
///   * upsert applied
///   * delete that actually removed the row
///   * delete that found no row (idempotent late-replay — tombstone
///     still required so a future stale upsert is correctly
///     rejected)
///   * intentional in-handler skip (list "at-least-one" invariant,
///     blob-asset / list FK-stalled child references — tombstone
///     still required so a future cleanup pass can finish the delete
///     once the dependent rows resolve)
/// - `LwwRejected` is the strict in-handler LWW refusal: a delete
///   envelope reached the handler but the local row's version is
///   strictly greater than the envelope's. The caller in
///   `apply_envelope` does NOT mint a tombstone for this outcome —
///   doing so would record the envelope's older HLC as the
///   canonical death of an entity the cluster decided is still
///   alive, durably overriding the winning local state on
///   subsequent re-syncs.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum EntityApplyOutcome {
    Applied,
    /// The in-handler LWW gate refused the SQL DELETE because the
    /// surviving local row's HLC dominates the envelope's. The
    /// `local_version` carries the row's pre-handler version so the
    /// envelope-level caller can render the conflict-log row without
    /// re-issuing a `SELECT version FROM <table> WHERE id = ?1` —
    /// the per-handler outcome already paid that read inside its
    /// LWW gate.
    LwwRejected {
        local_version: String,
    },
    /// an aggregate-level invariant guard refused the
    /// in-handler DELETE while leaving the row alive. Currently only
    /// `apply_list_delete` produces this outcome — both the
    /// at-least-one-list invariant (`total_lists <= 1`) and the
    /// FK-restrict invariant (`tasks.list_id` rows still reference
    /// the list locally) flow through this variant. The caller in
    /// `apply_envelope` defers the envelope to `sync_pending_inbox`
    /// instead of writing a tombstone over the still-live row.
    /// Discarding this signal would let `apply_envelope` always
    /// write a tombstone, which would permanently block any future
    /// re-upsert of the same id — the tombstone-vs-upsert gate uses
    /// `tombstone.version >= envelope.version`, so a peer concurrent
    /// edit at a lower HLC would silently lose.
    /// `invariant` is a `'static` identifier for the guard that
    /// fired — recorded in the `sync_pending_inbox.reason` column so
    /// diagnostics can distinguish "still 1 list" from "tasks still
    /// reference this list" without re-deriving the condition.
    DeleteSkippedByInvariant {
        invariant: &'static str,
    },
}
