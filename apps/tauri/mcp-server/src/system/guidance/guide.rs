use crate::contract::GetGuideArgs;
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::system::guidance_support::{
    auto_detect_guide_topic, build_guide, guide_topic_to_str, GuideState,
};
use lorvex_store::load_setup_status;
use lorvex_workflow::timezone::today_ymd_for_conn;
use rusqlite::Connection;
use serde_json::{json, Value};

fn map_setup_status_error(error: lorvex_store::StoreError) -> McpError {
    match error {
        lorvex_store::StoreError::Validation(message) => McpError::Validation(message),
        other => McpError::Store(Box::new(other)),
    }
}

pub(crate) fn get_guide(conn: &Connection, args: &GetGuideArgs) -> Result<String, McpError> {
    let &GetGuideArgs { topic } = args;
    let today = today_ymd_for_conn(conn)?;
    let task_count: i64 = conn.query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))?;
    let list_count: i64 = conn.query_row("SELECT COUNT(*) FROM lists", [], |row| row.get(0))?;
    let setup_status = load_setup_status(conn).map_err(map_setup_status_error)?;
    let has_current_focus = conn.query_row(
        "SELECT COUNT(*) FROM current_focus WHERE date = ?",
        [today],
        |row| row.get::<_, i64>(0),
    )? > 0;
    let memory_count: i64 =
        conn.query_row("SELECT COUNT(*) FROM memories", [], |row| row.get(0))?;

    let configured_preferences =
        query_all_as_json(conn, "SELECT key FROM preferences ORDER BY key", [])?
            .into_iter()
            .filter_map(|row| row.get("key").and_then(Value::as_str).map(str::to_string))
            .collect::<Vec<_>>();

    let state = GuideState {
        setup_completed: setup_status.setup_completed,
        task_count,
        list_count,
        has_current_focus,
        memory_count,
        configured_preferences,
    };
    let effective_topic = topic.unwrap_or_else(|| auto_detect_guide_topic(&state));
    let guide = build_guide(effective_topic, &state);

    Ok(serde_json::to_string(&json!({
        "topic": guide_topic_to_str(effective_topic),
        "state": state.to_value(),
        "guide": guide,
    }))?)
}
