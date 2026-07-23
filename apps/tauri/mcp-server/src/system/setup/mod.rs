use crate::contract::CompleteSetupArgs;
use crate::error::McpError;
use crate::json_row::query_one_as_json;
use crate::preferences::parse_preference_row_value;
use crate::runtime::change_tracking::execute_mcp_batch_mutation_with_audit_finalizer;
use crate::system::handler_support::utc_now_iso;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_PREFERENCE;
use lorvex_store::load_setup_status;
use lorvex_store::repositories::preference_repo;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::{json, Map, Value};

struct CompleteSetupMutation<'a> {
    summary: &'a str,
    now: &'a str,
    operation: &'static str,
    before: Option<&'a Value>,
}

impl<'a> Mutation for CompleteSetupMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_PREFERENCE
    }

    fn operation(&self) -> &'static str {
        self.operation
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.cloned())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let setup_completed_key = lorvex_domain::preference_keys::PREF_SETUP_COMPLETED;
        let setup_summary_key = lorvex_domain::preference_keys::PREF_SETUP_SUMMARY;
        let setup_state_key = lorvex_domain::preference_keys::PREF_SETUP_STATE;

        let version = hlc.next_version_string();
        preference_repo::set_preference(conn, setup_completed_key, "true", &version, self.now)?;

        let version = hlc.next_version_string();
        let summary_json = serde_json::to_string(self.summary)
            .map_err(|error| StoreError::Serialization(error.to_string()))?;
        preference_repo::set_preference(
            conn,
            setup_summary_key,
            &summary_json,
            &version,
            self.now,
        )?;

        let version = hlc.next_version_string();
        let setup_state_json = json!({
            "completed_at": self.now,
            "completed_summary": self.summary,
            "completed_via": "complete_setup",
        });
        let setup_state_json = serde_json::to_string(&setup_state_json)
            .map_err(|error| StoreError::Serialization(error.to_string()))?;
        preference_repo::set_preference(
            conn,
            setup_state_key,
            &setup_state_json,
            &version,
            self.now,
        )?;

        Ok(MutationOutput::new(
            load_setup_preferences_after_for_store(conn)?,
            format!("Completed initial setup: {}", self.summary),
        ))
    }
}

fn load_typed_preference_row_for_store(conn: &Connection, key: &str) -> Result<Value, StoreError> {
    let row = query_one_as_json(
        conn,
        "SELECT key, value, updated_at FROM preferences WHERE key = ?",
        [key.to_string()],
    )
    .map_err(|error| StoreError::Invariant(format!("query_one_as_json: {error}")))?
    .ok_or_else(|| StoreError::NotFound {
        entity: ENTITY_PREFERENCE,
        id: key.to_string(),
    })?;
    parse_preference_row_value(row).map_err(|error| StoreError::Serialization(error.to_string()))
}

fn load_setup_preferences_after_for_store(conn: &Connection) -> Result<Value, StoreError> {
    let setup_completed_key = lorvex_domain::preference_keys::PREF_SETUP_COMPLETED;
    let setup_summary_key = lorvex_domain::preference_keys::PREF_SETUP_SUMMARY;
    let setup_state_key = lorvex_domain::preference_keys::PREF_SETUP_STATE;

    Ok(json!({
        "setup_completed": load_typed_preference_row_for_store(conn, setup_completed_key)?,
        "setup_summary": load_typed_preference_row_for_store(conn, setup_summary_key)?,
        "setup_state": load_typed_preference_row_for_store(conn, setup_state_key)?,
    }))
}

fn map_setup_status_error(error: lorvex_store::StoreError) -> McpError {
    match error {
        lorvex_store::StoreError::Validation(message) => McpError::Validation(message),
        other => McpError::Store(Box::new(other)),
    }
}

fn compute_setup_state(conn: &Connection) -> Result<Value, McpError> {
    let status = load_setup_status(conn).map_err(map_setup_status_error)?;

    Ok(json!({
        "lists_ready": status.lists_ready,
        "default_list_id": status.default_list_id,
        "default_list_ready": status.default_list_ready,
        "working_hours_ready": status.working_hours_ready,
        "normal_task_creation_ready": status.normal_task_creation_ready,
        "prerequisites_ready": status.prerequisites_ready,
        "explicit_setup_completed": status.explicit_setup_completed,
        "setup_completed": status.setup_completed,
    }))
}

pub(crate) fn get_setup_status(conn: &Connection) -> Result<String, McpError> {
    let setup_state = compute_setup_state(conn)?;
    let setup_completed = setup_state
        .get("setup_completed")
        .cloned()
        .unwrap_or(Value::Bool(false));

    let mut prefs_stmt = conn.prepare_cached("SELECT key, value FROM preferences ORDER BY key")?;

    let prefs_rows = prefs_stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;

    let mut prefs_map = Map::new();
    for row in prefs_rows {
        let (key, raw_value) = row?;
        let parsed = serde_json::from_str::<Value>(&raw_value).map_err(|error| {
            McpError::Validation(format!(
                "preference '{key}' contains malformed JSON: {error}"
            ))
        })?;
        prefs_map.insert(key, parsed);
    }

    let list_count: i64 = conn.query_row("SELECT COUNT(*) FROM lists", [], |row| row.get(0))?;
    let task_count: i64 = conn.query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))?;

    let payload = json!({
        "setup_completed": setup_completed,
        "setup_state": setup_state,
        "existing_preferences": Value::Object(prefs_map),
        "list_count": list_count,
        "task_count": task_count,
    });

    Ok(serde_json::to_string(&payload)?)
}

pub(crate) fn complete_setup(
    conn: &Connection,
    args: CompleteSetupArgs,
) -> Result<String, McpError> {
    // idempotency cache. Capture canonical
    // fingerprint before destructure so a retried complete_setup
    // (which writes 3 preferences + 1 audit row + sync envelopes)
    // short-circuits.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // #3607 — derive-driven shape validation replaces the hand-rolled
    // `validate_string_length(&summary, MAX_LONG_TEXT_LENGTH)` call
    // below.
    use crate::contract_validate::ContractValidate;
    args.validate_shape()?;
    let CompleteSetupArgs {
        summary,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "complete_setup",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let now = utc_now_iso();

    // capture the pre-write row for each of the three
    // setup preferences BEFORE we mutate them.
    // hardcoded `operation: "create"` and dropped `before_json`, so
    // re-completing setup (which is a legitimate path: the
    // assistant-driven onboarding can be re-run) emitted a misleading
    // "create" audit row that erased the prior values it actually
    // overwrote. Decide operation per row, then aggregate into a
    // single audit-row decision: if any of the three prefs already
    // existed, the changelog row is an `update`.
    let setup_completed_key = lorvex_domain::preference_keys::PREF_SETUP_COMPLETED;
    let setup_summary_key = lorvex_domain::preference_keys::PREF_SETUP_SUMMARY;
    let setup_state_key = lorvex_domain::preference_keys::PREF_SETUP_STATE;

    let before_setup_completed = query_one_as_json(
        conn,
        "SELECT key, value, updated_at FROM preferences WHERE key = ?",
        [setup_completed_key],
    )?;
    let before_setup_summary = query_one_as_json(
        conn,
        "SELECT key, value, updated_at FROM preferences WHERE key = ?",
        [setup_summary_key],
    )?;
    let before_setup_state = query_one_as_json(
        conn,
        "SELECT key, value, updated_at FROM preferences WHERE key = ?",
        [setup_state_key],
    )?;

    // parse each captured pre-row into the same shape
    // the after_json emits (key/value/updated_at, with `value` as
    // typed JSON rather than the raw stored string) so the diff
    // renderer can compare apples-to-apples. Missing-row stays
    // `Value::Null` so re-completing surfaces the prior state for
    // exactly the keys that had one, while a true first-run leaves
    // every leaf null.
    let before_setup_completed_value = match before_setup_completed {
        Some(row) => parse_preference_row_value(row)?,
        None => Value::Null,
    };
    let before_setup_summary_value = match before_setup_summary {
        Some(row) => parse_preference_row_value(row)?,
        None => Value::Null,
    };
    let before_setup_state_value = match before_setup_state {
        Some(row) => parse_preference_row_value(row)?,
        None => Value::Null,
    };

    let any_existed = !before_setup_completed_value.is_null()
        || !before_setup_summary_value.is_null()
        || !before_setup_state_value.is_null();
    let operation = if any_existed { "update" } else { "create" };

    let before_aggregate = any_existed.then(|| {
        json!({
            "setup_completed": before_setup_completed_value,
            "setup_summary": before_setup_summary_value,
            "setup_state": before_setup_state_value,
        })
    });

    let mutation = CompleteSetupMutation {
        summary: summary.as_str(),
        now: now.as_str(),
        operation,
        before: before_aggregate.as_ref(),
    };
    let after = execute_mcp_batch_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "complete_setup",
        vec![
            setup_completed_key.to_string(),
            setup_summary_key.to_string(),
            setup_state_key.to_string(),
        ],
        McpError::from,
        |_, _| Ok(()),
    )?
    .after;
    let setup_completed_preference = after
        .get("setup_completed")
        .cloned()
        .expect("Mutation contract: complete_setup stamps setup_completed");
    let setup_summary_preference = after
        .get("setup_summary")
        .cloned()
        .expect("Mutation contract: complete_setup stamps setup_summary");
    let setup_state_preference = after
        .get("setup_state")
        .cloned()
        .expect("Mutation contract: complete_setup stamps setup_state");

    let response = serde_json::to_string(&json!({
        "setup_completed": true,
        "summary": summary,
        "setup_completed_preference": setup_completed_preference,
        "setup_summary_preference": setup_summary_preference,
        "setup_state_preference": setup_state_preference,
    }))?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "complete_setup",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

#[cfg(test)]
mod tests;
