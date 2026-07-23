//! Coalesced enqueue path for `sync_outbox`.
//!
//! Splits the production entry point + LWW body from the warn-once
//! dedup memo so each concern is reviewed independently. Callers go
//! through [`enqueue_coalesced`].

mod enqueue;
mod warn_dedup;

pub use enqueue::enqueue_coalesced;
