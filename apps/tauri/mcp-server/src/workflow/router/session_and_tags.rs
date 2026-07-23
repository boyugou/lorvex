//! Cross-cutting workflow tools: session bootstrap snapshot and bulk tag rename.
//!
//! - `rename_tag` — bulk rename a tag across every task that uses it.
//! - `get_session_context` — bounded all-in-one snapshot for assistant
//!   session bootstrap (overview, focus, today's calendar, recent
//!   changelog, contextual guide, habits summary, memory).

use crate::contract::RenameTagArgs;
use crate::system::session_context;
use crate::system::tags;

crate::server::tool_macros::mcp_tools! {
    router = workflow_session_and_tags_tool_router;

    write rename_tag(RenameTagArgs) -> tags::rename_tag;
        "Rename a tag across all tasks that use it. Case-insensitive match on old_name, replaces with new_name. Use when the user wants to consolidate tags, fix typos, or standardize tag naming. Logs to ai_changelog and enqueues sync for all affected tasks. Returns {old_name, new_name, tasks_updated, task_ids}.";

    read_noargs get_session_context -> session_context::get_session_context;
        "Read the bounded all-in-one session context snapshot for startup and wide situational context. It includes overview, current focus, today's calendar events, recent AI changelog, contextual guide, and habits summary. The memory section contains notes_for_ai (nested under memory) plus a compact memory summary.";
}
