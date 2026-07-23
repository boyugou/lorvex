//! Shared forward-compat sync payload types for Lorvex.
//!
//! This crate hosts the payload shadow + attendee shadow subsystems
//! that both [`lorvex_store`] and [`lorvex_sync`] need. It sits
//! between `lorvex-domain` and those two crates so the sync wire
//! layer can stay layered above the storage layer without dragging
//! storage into a cycle with sync.
//!
//! Scope:
//!
//! * [`payload_shadow`] — `sync_payload_shadow` table CRUD and the
//!   merge/redirect helpers that preserve unknown JSON keys across
//!   LWW conflict resolution and re-emit. Both the inbound apply
//!   path (sync) and the export/import path (store) read and write
//!   this table.
//! * [`attendee_shadow`] — `calendar_event_attendee_shadow` CRUD
//!   for per-attendee forward-compat extras. Both calendar apply
//!   (sync) and calendar export/MCP enrichment (store) read this
//!   table when assembling the canonical `attendees` array.
//!
//! The crate is intentionally thin — only the row types, size
//! caps, and SQL primitives. Envelope assembly, aggregate-payload
//! builders, and per-entity SELECT mappers live one layer up in
//! `lorvex_sync::payload_build`.

// Tests legitimately `unwrap()` on known-good fixtures; exempt them from the
// workspace `unwrap_used` lint so its signal stays meaningful for production
// code, matching every other crate in the workspace.
#![cfg_attr(test, allow(clippy::unwrap_used))]

pub mod attendee_shadow;
pub mod calendar_event_wire;
mod error;
pub mod payload_shadow;
mod support;

pub use calendar_event_wire::{AttendeeWire, CalendarEventUpdateWire};
pub use error::PayloadError;
