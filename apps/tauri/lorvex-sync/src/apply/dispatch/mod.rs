//! typed entity-handler dispatch table.
//!
//! Replaces the previous ~340-line megamatch in `apply_entity_with_version_mode`
//! with a small registration table. Each entity type names a handler kind
//! (`StandardAggregate`, `ChildOrEdge`, plus the three special cases that
//! need device-id threading or append-only semantics) and the dispatcher
//! does a single lookup.
//!
//! Adding a new entity type now requires:
//!   1. Implement the `*_upsert` / `*_delete` pair in the appropriate
//!      submodule (`aggregate::`, `child::`, `edge::`, `tag::`, `blob::`,
//!      `day_scoped::`, etc.).
//!   2. Register the pair in `ENTITY_HANDLERS` in `handler.rs` with the
//!      correct `EntityHandler` variant.
//!
//! Every aggregate-style handler in the workspace returns
//! `Result<(), ApplyError>` *or* the list-only `Result<bool, ApplyError>`
//! variant (which signals "DELETE skipped by an aggregate-level guard").
//! The list bool is preserved through the dispatcher into a typed
//! `EntityApplyOutcome::DeleteSkippedByInvariant` so the caller in
//! `apply_envelope` can defer the envelope to `sync_pending_inbox`
//! instead of writing a tombstone at the envelope's HLC over a
//! still-live row. Discarding the bool would let a stale tombstone
//! permanently block any future re-upsert of the same id from any
//! peer.
//!
//! Per-concern siblings:
//!
//! * `outcome.rs` — the typed [`EntityApplyOutcome`] enum consumed by
//!   `apply::envelope::delete_flow` for the tombstone-vs-defer decision.
//! * `handler.rs` — the `EntityHandler` enum + fn-pointer signatures +
//!   the `ENTITY_HANDLERS` registration table + the `lookup` helper.
//! * `dispatch_impl.rs` — the `dispatch` entry point + its
//!   `post_handler_lww_outcome` translator.

mod dispatch_impl;
mod handler;
mod outcome;

pub(in crate::apply) use dispatch_impl::dispatch;
pub(crate) use outcome::EntityApplyOutcome;

#[cfg(test)]
mod tests;
