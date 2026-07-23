//! Calendar event CRUD plus task↔event linking surfaces (canonical
//! `task_calendar_event_links` and provider-only
//! `task_provider_event_links`).
//!
//! ## Module layout
//!
//! - [`types`] — `CalendarEventCreateFields` / `CalendarEventCreateInput`
//!   inputs, the `*Result` payloads, and the `CalendarEventUpdateFields`
//!   patch shape.
//! - [`validation`] — pure validation, sanitization, normalization, and
//!   recurrence-rule helpers (no DB IO).
//! - [`load`] — read-only DB helpers: row loaders, link existence
//!   probes, and the public read entry points (link lookups, provider
//!   resolution, search, ICS export).
//! - [`mutations`] — every write path: create/update/delete,
//!   canonical and provider link/unlink, and recurrence-exception
//!   mutations. Each helper owns its own transaction, mints HLC
//!   versions through `crate::hlc_guard`, logs to `ai_changelog`, and
//!   (for syncable edges) drives the sync outbox.
//! - [`tests`] — integration tests covering both the read and write
//!   surfaces.
//!
//! ## Provider event links: local-only by design
//!
//! `EDGE_TASK_PROVIDER_EVENT_LINK` is intentionally NOT in
//! `lorvex_domain::naming::ALL_SYNCABLE_TYPES` — it represents a
//! pointer from a Lorvex task to an external calendar provider's
//! event id (EventKit / Google / etc.) and that pointer is meaningful
//! only on the device that holds the corresponding provider auth
//! session. Replicating it across peers would surface broken or
//! ambiguous links on devices that never resolved the provider.
//!
//! Both `link_task_to_provider_event_with_conn` and
//! `unlink_task_from_provider_event_with_conn` therefore:
//!   - write a row to `task_provider_event_links` (local table only),
//!   - log an `ai_changelog` row (which IS synced — peers see that
//!     SOMETHING happened, but cannot reconstruct or undo the link),
//!   - skip the sync outbox entirely (no `enqueue_payload_*`),
//!   - skip the parent-task `(version, updated_at)` bump and the
//!     `enqueue_entity_upsert(ENTITY_TASK, ...)` envelope (`task`
//!     aggregate payload does not embed provider links, so a bump
//!     would broadcast a "task updated" envelope with no observable
//!     field change — noise without signal).
//!
//! This matches the MCP server's `link_task_to_provider_event` /
//! `unlink_task_from_provider_event`
//! (`mcp-server/src/calendar/provider_event_links/`), so both CLI and MCP
//! surfaces converge on the same local-only contract. Issue #2979 M20 flagged the
//! changelog-syncs-but-link-doesn't divergence as a known and
//! documented quirk; closing CL-H6 commits to that contract here so
//! future audits don't reopen the question.
//!
//! If the project ever decides to make these links syncable, the
//! change must:
//!   1. Add `EDGE_TASK_PROVIDER_EVENT_LINK` to `ALL_SYNCABLE_TYPES`
//!      (`lorvex-domain/src/naming/`) and the apply pipeline
//!      (`lorvex-sync/src/apply/edge/`),
//!   2. Wire outbox enqueue calls here AND in the MCP server in
//!      lockstep,
//!   3. Bump parent-task version on link/unlink (CL-H7) so peers see
//!      the task aggregate changed,
//!   4. Define what happens on the receiving side when the provider
//!      auth context is missing (best path: the apply queues the
//!      link as "unresolved" until a local provider sync fills it in).
//!
//! Until all four ship together, keep the local-only contract.

mod load;
mod mutations;
mod types;
mod validation;

#[cfg(test)]
mod tests;

// Re-export the public-to-crate write entry points. Read entry points
// live in `load`; types live in `types`. Both are flattened here so
// `super::calendar::foo` callers (the surrounding mutate surface and
// the calendar dispatch entry points) keep working unchanged.
pub(crate) use load::{
    export_calendar_ics_with_conn, get_calendar_links_for_event_with_conn,
    get_calendar_links_for_task_with_conn, get_provider_event_links_for_task_with_conn,
    search_calendar_events_with_conn,
};
pub(crate) use mutations::{
    add_calendar_event_exception_with_conn, create_calendar_event_with_conn,
    create_calendar_events_with_conn, delete_calendar_event_with_conn,
    link_task_to_provider_event_with_conn, link_tasks_to_calendar_event_with_conn,
    remove_calendar_event_exception_with_conn, unlink_task_from_calendar_event_with_conn,
    unlink_task_from_provider_event_with_conn, update_calendar_event_with_conn,
};
pub(crate) use types::{
    CalendarEventCreateFields, CalendarEventCreateInput, CalendarEventUpdateFields,
    CliAttendeeInput,
};

// Test-only re-exports. Tests use `super::*` to pull in the entire
// public surface; surfacing `Cow` here lets the test fixtures stay
// readable (`Cow::Borrowed(...)`) without each test importing it.
#[cfg(test)]
pub(crate) use std::borrow::Cow;
