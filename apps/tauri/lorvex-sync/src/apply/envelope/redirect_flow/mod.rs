//! Redirected-tombstone apply path for inbound envelopes.
//!
//! The orchestrator owns the per-stage ordering (build remap, drop
//! redirected delete, rewrite payload identity fields, gate the upsert)
//! while focused siblings own each stage so the redirect boundary stays
//! readable.

mod delete_drop;
mod orchestrator;
mod remap_envelope;
mod rewrite_payload;
mod upsert_gate;

pub(super) use self::orchestrator::apply_redirected_tombstone;
