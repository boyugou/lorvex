use crate::contract::GetTaskArgs;
use crate::error::McpError;
use crate::system::handler_support::fetch_task_json;
use crate::system::text_hygiene::fence_task_user_fields;
use crate::tasks::validation::validate_uuid_arg;
use rusqlite::Connection;

pub(crate) fn get_task(conn: &Connection, args: GetTaskArgs) -> Result<String, McpError> {
    let GetTaskArgs { id } = args;
    let id = validate_uuid_arg(&id, "id")?;
    let mut task = fetch_task_json(conn, &id)?;
    // #2422: fence user-origin strings on the read-path only.
    // `fetch_task_json` is shared with write-path return values that
    // need raw strings for post-processing (duplicate-title advice,
    // etc.), so the fence is applied here at the read-tool entry.
    fence_task_user_fields(&mut task);
    Ok(serde_json::to_string(&task)?)
}
