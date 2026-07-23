use crate::commands::with_immediate_transaction;
use crate::db::{get_conn, get_read_conn};
use crate::error::{AppError, AppResult};
use crate::event_bus;
use lorvex_domain::TaskId;
use lorvex_store::repositories::provider_repo;

// Re-export shared types for Tauri command return values
pub use lorvex_store::repositories::provider_repo::{
    ProviderEventLinkWithResolution, TaskProviderEventLink,
};

/// `task_id` is a UUID, so it must match the canonical
/// 36-char hex-with-hyphens shape exactly — running it through the
/// free-text sanitizer is conceptually wrong (UUIDs have no bidi /
/// zero-width risk) and would silently accept values like
/// `"  01966a3f-7c8b-7d4e-8f3a-000000000001  "` after trim. Extracted into the
/// shared `commands::shared::validate_uuid_id` so the calendar-link
/// surface (`task_calendar_event_links`) walks the same contract.
fn validate_task_id(value: &str) -> Result<String, String> {
    crate::commands::shared::validate_uuid_id(value, "task_id")
}

fn validate_provider_link_fields(
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> Result<lorvex_domain::provider_link::ProviderLinkFields, String> {
    lorvex_domain::provider_link::normalize_provider_link_fields(
        provider_kind,
        provider_scope,
        provider_event_key,
    )
    .map_err(|err| err.to_string())
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn link_task_to_provider_event(
    task_id: String,
    provider_kind: String,
    provider_scope: String,
    provider_event_key: String,
) -> Result<TaskProviderEventLink, String> {
    // validate every field at the IPC boundary —
    // unconstrained writes here propagated unchecked into the outbox
    // payload of every linked task and could carry multi-megabyte
    // values, bidi-override garbage, or unknown provider kinds that
    // resolution paths assume are in a small enum. Upstream of
    // \`get_conn\` so a malformed request never even enters the
    // writer transaction.
    // task_id is a UUID; shape-check rather than scrub.
    let task_id_str = validate_task_id(&task_id)?;
    let task_id = TaskId::from_trusted(task_id_str);
    let fields =
        validate_provider_link_fields(&provider_kind, &provider_scope, &provider_event_key)?;

    let conn = get_conn()?;

    let result = with_immediate_transaction(&conn, |conn| {
        link_task_to_provider_event_inner(
            conn,
            &task_id,
            &fields.provider_kind,
            &fields.provider_scope,
            &fields.provider_event_key,
        )
    })
    .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::Task);
    Ok(result)
}

fn link_task_to_provider_event_inner(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> AppResult<TaskProviderEventLink> {
    // Verify task exists (nicer error than FK violation)
    if !lorvex_store::task_exists_active(conn, task_id).map_err(AppError::from)? {
        return Err(AppError::NotFound(format!("Task not found: {task_id}")));
    }

    let link = provider_repo::upsert_provider_event_link(
        conn,
        task_id,
        provider_kind,
        provider_scope,
        provider_event_key,
    )
    .map_err(AppError::from)?;

    Ok(link)
}

fn unlink_task_from_provider_event_inner(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    provider_kind: &str,
    provider_scope: &str,
    provider_event_key: &str,
) -> AppResult<Vec<TaskProviderEventLink>> {
    if !lorvex_store::task_exists_active(conn, task_id).map_err(AppError::from)? {
        return Err(AppError::NotFound(format!("Task not found: {task_id}")));
    }

    let delete = provider_repo::delete_provider_event_link(
        conn,
        task_id,
        provider_kind,
        provider_scope,
        provider_event_key,
    )
    .map_err(AppError::from)?;
    if !delete.deleted {
        return Err(AppError::NotFound(format!(
            "Task-provider event link not found: {task_id}:{provider_kind}:{provider_scope}:{provider_event_key}"
        )));
    }

    Ok(delete.remaining_links)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn unlink_task_from_provider_event(
    task_id: String,
    provider_kind: String,
    provider_scope: String,
    provider_event_key: String,
) -> Result<Vec<TaskProviderEventLink>, String> {
    // Mirror the link-side validation: shape-check `task_id`, clamp
    // length, and allowlist `provider_kind` before any raw string
    // reaches the writer transaction. Parameterized SQL alone closes
    // injection but leaves an unbounded `provider_event_key` (from a
    // renderer bug or compromised webview) free to reach the writer,
    // and an unknown `provider_kind` would silently no-op as
    // NotFound.
    // task_id is a UUID; shape-check rather than scrub.
    let task_id_str = validate_task_id(&task_id)?;
    let task_id = TaskId::from_trusted(task_id_str);
    let fields =
        validate_provider_link_fields(&provider_kind, &provider_scope, &provider_event_key)?;

    let conn = get_conn()?;

    let result = with_immediate_transaction(&conn, |conn| {
        unlink_task_from_provider_event_inner(
            conn,
            &task_id,
            &fields.provider_kind,
            &fields.provider_scope,
            &fields.provider_event_key,
        )
    })
    .map_err(String::from)?;
    event_bus::emit_data_changed(event_bus::Entity::Task);
    Ok(result)
}

fn get_provider_event_links_for_task_inner(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
) -> AppResult<Vec<ProviderEventLinkWithResolution>> {
    if !lorvex_store::task_exists_active(conn, task_id).map_err(AppError::from)? {
        return Err(AppError::NotFound(format!("Task not found: {task_id}")));
    }

    provider_repo::get_resolved_provider_links_for_task(conn, task_id).map_err(AppError::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_provider_event_links_for_task(
    task_id: String,
) -> Result<Vec<ProviderEventLinkWithResolution>, String> {
    // scrub + length-cap the task_id at the IPC
    // boundary so a malformed renderer state cannot ship a megabyte
    // of "task_id" into the read path. Validation is identical in
    // shape to link / unlink so a future helper can subsume all
    // three call sites if desired.
    // task_id is a UUID; shape-check rather than scrub.
    let task_id_str = validate_task_id(&task_id)?;
    let task_id = TaskId::from_trusted(task_id_str);

    let conn = get_read_conn()?;

    get_provider_event_links_for_task_inner(&conn, &task_id).map_err(String::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::test_support::test_conn;

    fn setup() -> rusqlite::Connection {
        test_conn()
    }

    fn seed_task(conn: &rusqlite::Connection, id: &str) {
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new(id)
            .title("Task")
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-03-29T08:00:00Z")
            .insert(conn);
    }

    #[test]
    fn validate_provider_link_fields_accepts_empty_scope() {
        let fields =
            validate_provider_link_fields("eventkit", "", "ek-123").expect("empty scope valid");

        assert_eq!(fields.provider_kind, "eventkit");
        assert_eq!(fields.provider_scope, "");
        assert_eq!(fields.provider_event_key, "ek-123");
    }

    #[test]
    fn validate_provider_link_fields_rejects_overlong_scope() {
        let too_long = "a".repeat(lorvex_domain::provider_link::MAX_PROVIDER_LINK_FIELD_LEN + 1);

        let err = validate_provider_link_fields("eventkit", &too_long, "ek-123")
            .expect_err("overlong scope should reject");

        assert!(err.contains("provider_scope"), "unexpected error: {err}");
    }

    #[test]
    fn link_task_to_provider_event_inner_rejects_missing_task() {
        let conn = setup();

        let error = link_task_to_provider_event_inner(
            &conn,
            &TaskId::from_trusted("missing-task".to_string()),
            "eventkit",
            "",
            "ek-123",
        )
        .expect_err("missing task should be rejected");

        let message = error.to_string();
        assert!(
            message.contains("Task not found: missing-task"),
            "unexpected error: {message}"
        );
    }

    #[test]
    fn unlink_task_from_provider_event_inner_rejects_missing_link() {
        let conn = setup();
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new(
            "01966a3f-7c8b-7d4e-8f3a-000000000001",
        )
        .title("Task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-29T08:00:00Z")
        .insert(&conn);

        let error = unlink_task_from_provider_event_inner(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
            "eventkit",
            "",
            "missing-link",
        )
        .expect_err("missing provider link should be rejected");

        match error {
            AppError::NotFound(message) => assert!(message.contains("missing-link")),
            other => panic!("expected not found error, got {other:?}"),
        }
    }

    #[test]
    fn get_provider_event_links_for_task_inner_rejects_missing_task() {
        let conn = setup();

        let error = get_provider_event_links_for_task_inner(
            &conn,
            &TaskId::from_trusted("missing-task".to_string()),
        )
        .expect_err("missing task should be rejected");

        match error {
            AppError::NotFound(message) => assert!(message.contains("missing-task")),
            other => panic!("expected not found error, got {other:?}"),
        }
    }

    #[test]
    fn get_provider_event_links_for_task_inner_surfaces_provider_health_states() {
        let conn = setup();
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000001c");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000001d");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000001e");
        seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000001f");

        let fresh_success = lorvex_domain::sync_timestamp_now();
        conn.execute(
            "INSERT INTO provider_scope_runtime_state
                (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at)
             VALUES ('eventkit', 'default', 1, 'enabled', ?1)",
            [&fresh_success],
        )
        .expect("seed fresh provider state");
        conn.execute(
            "INSERT INTO calendar_subscriptions
                (id, name, url, enabled, version, created_at, updated_at)
             VALUES ('sub-pending', 'Pending', 'https://example.com/pending.ics', 1,
                     '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
            [],
        )
        .expect("seed pending subscription");
        conn.execute(
            "INSERT INTO provider_scope_runtime_state
                (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at)
             VALUES ('eventkit', 'stale', 1, 'enabled', '2000-01-01T00:00:00.000Z')",
            [],
        )
        .expect("seed stale provider state");
        conn.execute(
            "INSERT INTO provider_scope_runtime_state
                (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at, last_refresh_result)
             VALUES ('eventkit', 'failing', 1, 'enabled', ?1, 'fetch_error')",
            [&fresh_success],
        )
        .expect("seed failing provider state");

        provider_repo::upsert_provider_event_link(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000001c".to_string()),
            "eventkit",
            "default",
            "missing-event",
        )
        .expect("link missing event");
        provider_repo::upsert_provider_event_link(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000001d".to_string()),
            "ical_subscription",
            "sub-pending",
            "pending-event",
        )
        .expect("link pending event");
        provider_repo::upsert_provider_event_link(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000001e".to_string()),
            "eventkit",
            "stale",
            "stale-event",
        )
        .expect("link stale event");
        provider_repo::upsert_provider_event_link(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000001f".to_string()),
            "eventkit",
            "failing",
            "failing-event",
        )
        .expect("link failing event");

        let missing = get_provider_event_links_for_task_inner(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000001c".to_string()),
        )
        .expect("read missing link");
        assert_eq!(missing[0].resolution_state, "missing");

        let pending = get_provider_event_links_for_task_inner(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000001d".to_string()),
        )
        .expect("read pending link");
        assert_eq!(pending[0].resolution_state, "pending");

        let stale = get_provider_event_links_for_task_inner(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000001e".to_string()),
        )
        .expect("read stale link");
        assert_eq!(stale[0].resolution_state, "stale");

        let failing = get_provider_event_links_for_task_inner(
            &conn,
            &TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000001f".to_string()),
        )
        .expect("read failing link");
        assert_eq!(failing[0].resolution_state, "unavailable");
    }
}
