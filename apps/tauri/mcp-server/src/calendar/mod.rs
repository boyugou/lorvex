//! Calendar domain modules — split from the old `server_calendar*` tree.
//!
//! The cross-surface canonical create + update operations
//! (`CreateCalendarEventMutation`, `UpdateCalendarEventMutation`,
//! `normalize_calendar_create`, `normalize_calendar_update`,
//! attendee materialization, EXDATE skeleton-preserve policy) live
//! in `lorvex_workflow::calendar_event`. This module owns the
//! MCP-specific glue: tool routers, JSON wire shape, idempotency
//! cache, DST diagnostic plumbing, and the per-tool handler that
//! constructs the workflow mutation and runs it through
//! `execute_mcp_mutation`.

mod exceptions;
pub(crate) mod ics;
mod mutations;
mod provider_event_links;
mod queries;
pub(crate) mod router;
pub(crate) mod support;
mod task_calendar_event_links;

pub(crate) use exceptions::{add_event_exception, remove_event_exception};
pub(crate) use mutations::{
    batch_create_calendar_events, create_calendar_event, delete_calendar_event,
    delete_scoped_calendar_event, edit_scoped_calendar_event, update_calendar_event,
};
pub(crate) use provider_event_links::{
    get_provider_event_links_for_task, link_task_to_provider_event, unlink_task_from_provider_event,
};
pub(crate) use queries::{get_calendar_event, get_calendar_events, search_calendar_events};
pub(crate) use task_calendar_event_links::{
    batch_link_tasks_to_event, get_linked_events_for_task, get_linked_tasks_for_event,
    link_task_to_event, unlink_task_from_event,
};
