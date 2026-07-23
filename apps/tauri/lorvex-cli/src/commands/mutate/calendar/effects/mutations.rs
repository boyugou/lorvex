//! Calendar event write paths: create, batch-create, update, delete,
//! task↔event link/unlink (canonical and provider-only), and
//! recurrence-exception mutations. Every helper here owns its own
//! transaction, mints HLC versions through `crate::hlc_guard`, logs to
//! `ai_changelog`, and (for the canonical edges) drives the sync
//! outbox.
//!
//! Read-only queries — including the `get_*_with_conn` lookups and ICS
//! export — live in `super::load`. Validation, sanitization, and
//! recurrence normalization live in `super::validation`.
//!
//! Implementation is split by write-path family under the sibling
//! `mutations/` module directory; this file is intentionally only the
//! composition boundary used by `calendar/mod.rs`.

use std::borrow::Cow;

use lorvex_domain::naming::{
    EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_PROVIDER_EVENT_LINK, ENTITY_CALENDAR_EVENT,
    ENTITY_TASK, OP_DELETE,
};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::calendar_event_exceptions;
use lorvex_store::repositories::calendar_event_write;
use lorvex_store::repositories::provider_repo::{self, TaskProviderEventLink};
use lorvex_store::repositories::task::calendar_links;
use lorvex_sync::outbox_enqueue::{
    enqueue_entity_upsert, enqueue_payload_delete, enqueue_payload_upsert,
};
use rusqlite::Connection;

use super::load::{ensure_calendar_event_exists, load_calendar_event_row};
use super::types::{
    CalendarEventCreateFields, CalendarEventCreateInput, CalendarEventUpdateFields,
    CalendarEventsCreateResult, CalendarLinkTasksResult, CalendarProviderUnlinkResult,
    CalendarUnlinkTaskResult, DeletedCalendarEventResult,
};
use super::validation::{
    normalize_calendar_event_type, normalize_calendar_link_task_ids, normalize_calendar_title,
    normalize_nonempty_cli_id,
};
use crate::commands::shared::{ensure_task_exists, validate_calendar_date};

mod create;
mod delete;
mod exceptions;
mod links;
mod provider_links;
mod support;
mod update;

pub(crate) use create::{create_calendar_event_with_conn, create_calendar_events_with_conn};
pub(crate) use delete::delete_calendar_event_with_conn;
pub(crate) use exceptions::{
    add_calendar_event_exception_with_conn, remove_calendar_event_exception_with_conn,
};
pub(crate) use links::{
    link_tasks_to_calendar_event_with_conn, unlink_task_from_calendar_event_with_conn,
};
pub(crate) use provider_links::{
    link_task_to_provider_event_with_conn, unlink_task_from_provider_event_with_conn,
};
use support::calendar_write_tx;
pub(crate) use update::update_calendar_event_with_conn;
