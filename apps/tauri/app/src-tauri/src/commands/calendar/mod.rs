//! Calendar-domain Tauri commands: VEVENT CRUD, recurrence exceptions,
//! ICS export, and the unified per-date-range read surface used by
//! the timeline and Today view.
//!
//! Source: refactor for #3277 — `calendar_events.rs` and its companion
//! directory at the `commands/` root were folded under this single
//! `calendar/` namespace.

pub(crate) mod events;
