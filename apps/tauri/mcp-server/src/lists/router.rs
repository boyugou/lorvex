use crate::contract::{
    CreateListArgs, DeleteListArgs, ListListsArgs, ReorganizeListArgs, UpdateListArgs,
};
use crate::lists;

crate::server::tool_macros::mcp_tools! {
    router = list_tool_router;

    read_ref list_lists(ListListsArgs) -> lists::list_lists;
        "Returns user-created lists with their task counts (open_count, total_count per list). Paginated: pass `limit` (default 100, cap 1000) and `offset`; the response carries `next_offset` for the next page. `open_count` only counts open tasks; `total_count` counts every task row still assigned to the list regardless of status, including completed, cancelled, and someday tasks. Use to see all lists, look up list IDs before moving tasks, during weekly review to identify stalled lists, or when the user asks about their list organization.";

    write create_list(CreateListArgs) -> lists::create_list;
        "Create a new task list. Optional ai_notes can store AI-only list scope/profile metadata. Use when the user describes a new area to organize tasks into. Set icon and color for visual identity in the sidebar. Returns the full created list object.";

    write update_list(UpdateListArgs) -> lists::update_list;
        "Update a list's name, color, icon, description, or ai_notes. Use when renaming a list, changing visual identity, or updating AI-facing scope notes. Returns the full updated list object.";

    raw {
        #[::rmcp::tool(
            name = "reorganize_list",
            description = "Reorder open tasks in a list by a strategy (priority, deadline, manual). Use when a list's task order feels wrong, after bulk task changes, or when the user asks to sort/prioritize within a list. 'manual' requires a full ordered permutation of every open task ID currently in the list; use [] only when the list has no open tasks. Pass dry_run=true to preview the reorder without logging a normal changelog. Returns the list object with an embedded tasks array in the computed order, `dry_run?`."
        )]
        pub(crate) fn reorganize_list(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<ReorganizeListArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            let list_id = args.id.clone();
            self.dispatch_dry_run(
                dry_run,
                "reorganize_list",
                lorvex_domain::naming::ENTITY_LIST,
                move |_| format!("reorganize list {list_id}"),
                |value| crate::system::handler_support::collect_id_strings(value.get("tasks")),
                move |conn| lists::reorganize_list(conn, args),
            )
        }

        #[::rmcp::tool(
            name = "delete_list",
            description = "Delete a user list only after every remaining assigned task has been moved to another list or permanently deleted. Use when a list is finished, merged into another, or no longer relevant and no remaining assigned work still points at it. Pass dry_run=true to preview the delete (runs the validation gates + returns the snapshot) without persisting. Returns {deleted_list_id, deleted, undo_token, dry_run?}."
        )]
        pub(crate) fn delete_list(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<DeleteListArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            let list_id = args.id.clone();
            self.dispatch_dry_run(
                dry_run,
                "delete_list",
                lorvex_domain::naming::ENTITY_LIST,
                move |_| format!("delete list {list_id}"),
                |value| {
                    value
                        .get("deleted_list_id")
                        .and_then(serde_json::Value::as_str)
                        .map(|s| vec![s.to_string()])
                        .unwrap_or_default()
                },
                move |conn| lists::delete_list(conn, args),
            )
        }
    }
}
