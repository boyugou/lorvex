use crate::contract::{AddEventExceptionArgs, RemoveEventExceptionArgs};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::utc_now_iso;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;
use lorvex_domain::EventId;
use lorvex_store::repositories::calendar_event_exceptions;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;

use super::mutations::load_calendar_event_json;

fn load_calendar_event_json_for_mutation(
    conn: &Connection,
    event_id: &str,
) -> Result<Option<Value>, StoreError> {
    load_calendar_event_json(conn, event_id).map_err(|error| match error {
        McpError::Store(store_error) => *store_error,
        McpError::Sql(sql_error) => StoreError::from(*sql_error),
        McpError::Validation(message) => StoreError::Validation(message),
        McpError::NotFound(_) => StoreError::NotFound {
            entity: ENTITY_CALENDAR_EVENT,
            id: event_id.to_string(),
        },
        McpError::Serialization(message) => StoreError::Serialization(message),
        other => StoreError::Invariant(other.to_string()),
    })
}

struct AddEventExceptionMutation {
    event_id: String,
    date: String,
    now: String,
    before: Option<Value>,
}

impl Mutation for AddEventExceptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let typed_event_id = EventId::from_trusted(self.event_id.clone());
        calendar_event_exceptions::add_recurrence_exception(
            conn,
            &typed_event_id,
            &self.date,
            &version,
            &self.now,
        )?;
        let after =
            load_calendar_event_json_for_mutation(conn, &self.event_id)?.ok_or_else(|| {
                StoreError::NotFound {
                    entity: ENTITY_CALENDAR_EVENT,
                    id: self.event_id.clone(),
                }
            })?;
        Ok(MutationOutput::new(
            after,
            format!("Added recurrence exception for {}", self.date),
        ))
    }
}

struct RemoveEventExceptionMutation {
    event_id: String,
    date: String,
    now: String,
    before: Option<Value>,
}

impl Mutation for RemoveEventExceptionMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CALENDAR_EVENT
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let typed_event_id = EventId::from_trusted(self.event_id.clone());
        calendar_event_exceptions::remove_recurrence_exception(
            conn,
            &typed_event_id,
            &self.date,
            &version,
            &self.now,
        )?;
        let after =
            load_calendar_event_json_for_mutation(conn, &self.event_id)?.ok_or_else(|| {
                StoreError::NotFound {
                    entity: ENTITY_CALENDAR_EVENT,
                    id: self.event_id.clone(),
                }
            })?;
        Ok(MutationOutput::new(
            after,
            format!("Removed recurrence exception for {}", self.date),
        ))
    }
}

pub(crate) fn add_event_exception(
    conn: &Connection,
    args: AddEventExceptionArgs,
) -> Result<String, McpError> {
    // #3029-M4: idempotency cache. dry_run is consumed at the
    // router layer via `dispatch_dry_run`; the body sees a normal
    // call and `dispatch_dry_run` rolls the savepoint back if the
    // flag was true.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let AddEventExceptionArgs {
        event_id,
        date,
        idempotency_key,
        dry_run: _,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "add_event_exception",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    // validate the date shape at the trust boundary
    // before any DB work.
    // the store helper which surfaced any parse error as a generic
    // validation message far from the trust boundary.
    lorvex_domain::validation::validate_date_format(&date)?;

    // route both before/after through
    // `load_calendar_event_json` so the diagnostics renderer sees the
    // same enriched (attendees + canonical event_type) shape it gets
    // from `update_calendar_event`.
    // row reads omitted attendees and
    // returned the raw event_type discriminant — the diff renderer
    // had to special-case the exception path. Now exceptions match
    // the canonical shape end-to-end.
    let before = load_calendar_event_json(conn, &event_id)?;

    let mutation = AddEventExceptionMutation {
        event_id: event_id.clone(),
        date,
        now: utc_now_iso(),
        before,
    };
    let output = execute_mcp_mutation(conn, &mutation, "add_event_exception", event_id)?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "add_event_exception",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

pub(crate) fn remove_event_exception(
    conn: &Connection,
    args: RemoveEventExceptionArgs,
) -> Result<String, McpError> {
    // #3029-M4: idempotency cache.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let RemoveEventExceptionArgs {
        event_id,
        date,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "remove_event_exception",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    // same trust-boundary date validation as
    // add_event_exception.
    lorvex_domain::validation::validate_date_format(&date)?;

    // enriched read (attendees + canonical
    // event_type) for both before and after, parity with
    // `update_calendar_event`.
    let before = load_calendar_event_json(conn, &event_id)?;

    let mutation = RemoveEventExceptionMutation {
        event_id: event_id.clone(),
        date,
        now: utc_now_iso(),
        before,
    };
    let output = execute_mcp_mutation(conn, &mutation, "remove_event_exception", event_id)?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "remove_event_exception",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
