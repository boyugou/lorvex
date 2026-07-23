use crate::contract::{
    AddTaskChecklistItemArgs, AddTaskRecurrenceExceptionArgs, AddTaskReminderArgs,
    AppendToTaskBodyArgs, BatchCancelTasksArgs, BatchCancelTasksInListArgs, BatchCompleteTasksArgs,
    BatchCreateTasksArgs, BatchDeferTasksArgs, BatchMoveTasksArgs, BatchReopenTasksArgs,
    BatchUpdateTasksArgs, CancelTaskArgs, CompleteTaskArgs, CreateTaskArgs, DeferTaskArgs,
    PermanentDeleteTaskArgs, RemoveTaskChecklistItemArgs, RemoveTaskRecurrenceExceptionArgs,
    RemoveTaskReminderArgs, ReopenTaskArgs, ReorderTaskChecklistItemsArgs, SetRecurrenceArgs,
    SetTaskAiNotesArgs, SetTaskRemindersArgs, ToggleTaskChecklistItemArgs, UpdateTaskArgs,
    UpdateTaskChecklistItemArgs,
};
use crate::tasks::batch;
use crate::tasks::lifecycle;
use crate::tasks::mutations;

crate::server::tool_macros::mcp_tools! {
    router = task_tool_router;

    write create_task(CreateTaskArgs) -> mutations::create_task;
        "Create one task. Use this for normal task capture with optional structure such as list_id, due_date, planned_date, tags, dependencies, reminders, or recurrence. Set include_advice=true if you want bounded deterministic intake advisories such as missing estimates or likely duplicates. Returns {task, next_occurrence, newly_unblocked, advice}.";

    write update_task(UpdateTaskArgs) -> mutations::update_task;
        "Patch one task's editable fields, including explicit tag patch semantics and recurrence clearing via recurrence=null. Status-transition side effects remain owned by complete_task, cancel_task, and reopen_task rather than update_task. Note: for recurring tasks, setting status='cancelled' via update_task always skips this occurrence (spawns next). Use cancel_task with cancel_series=true to stop the entire series. Returns the full updated task object (bare, not wrapped in an envelope).";

    raw {
        #[::rmcp::tool(
            description = "Create multiple tasks in one call. Use this for imports, brain dumps, or related task batches. Set include_advice=true if you want bounded deterministic intake advisories per created task. Pass dry_run=true to preview the insert (full response with freshly-minted IDs, `dry_run: true`) without persisting rows. Returns {created_count, tasks, next_occurrences, advice, dry_run?}."
        )]
        pub(crate) fn batch_create_tasks(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<BatchCreateTasksArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            self.dispatch_dry_run(
                dry_run,
                "batch_create_tasks",
                lorvex_domain::naming::ENTITY_TASK,
                |value| {
                    let n = value
                        .get("created_count")
                        .and_then(serde_json::Value::as_u64)
                        .unwrap_or(0);
                    format!("create {n} task(s)")
                },
                |value| crate::system::handler_support::collect_id_strings(value.get("tasks")),
                move |conn| mutations::batch_create_tasks(conn, args),
            )
        }

        #[::rmcp::tool(
            description = "Patch multiple tasks in one call. Supports the same task field updates and explicit tag patch semantics as update_task, but applied as a bounded batch. Pass dry_run=true to preview the updated rows without persisting. Returns {updated_count, tasks, dry_run?}."
        )]
        pub(crate) fn batch_update_tasks(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<BatchUpdateTasksArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            self.dispatch_dry_run(
                dry_run,
                "batch_update_tasks",
                lorvex_domain::naming::ENTITY_TASK,
                |value| {
                    let n = value
                        .get("updated_count")
                        .and_then(serde_json::Value::as_u64)
                        .unwrap_or(0);
                    format!("update {n} task(s)")
                },
                |value| crate::system::handler_support::collect_id_strings(value.get("tasks")),
                move |conn| batch::batch_update_tasks(conn, args),
            )
        }
    }

    write batch_complete_tasks(BatchCompleteTasksArgs) -> batch::batch_complete_tasks;
        "Mark multiple tasks as completed. Returns {completed_count, tasks, next_occurrences} — includes full updated task objects and any spawned recurring instances.";

    raw {
        #[::rmcp::tool(
            description = "Cancel multiple open tasks by ID. Rejects partial application when any requested task is already completed or cancelled. For recurring tasks: by default, cancellation skips each occurrence and spawns the next (series continues). Pass cancel_series=true to stop entire series. Pass dry_run=true to preview without persisting. Returns {cancelled_count, cancelled, already_done, dependency_updates, next_occurrences, dry_run?}."
        )]
        pub(crate) fn batch_cancel_tasks(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<BatchCancelTasksArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            self.dispatch_dry_run(
                dry_run,
                "batch_cancel_tasks",
                lorvex_domain::naming::ENTITY_TASK,
                |value| {
                    let n = value
                        .get("cancelled_count")
                        .and_then(serde_json::Value::as_u64)
                        .unwrap_or(0);
                    format!("cancel {n} task(s)")
                },
                |value| crate::system::handler_support::collect_id_strings(value.get("cancelled")),
                move |conn| batch::batch_cancel_tasks(conn, args),
            )
        }
    }

    write batch_reopen_tasks(BatchReopenTasksArgs) -> batch::batch_reopen_tasks;
        "Reopen multiple completed or cancelled tasks at once. Clears completed_at, planned_date, last_deferred_at, defer_count. For completed recurring tasks, cancels auto-spawned successors. Returns {reopened_count, reopened, already_open}.";

    write batch_defer_tasks(BatchDeferTasksArgs) -> batch::batch_defer_tasks;
        "Set planned_date on multiple tasks to an absolute target day. Canonical deferral semantics are absolute, not relative. Increments each task's defer_count, records reason in ai_notes, and returns {deferred_count, deferred, skipped}.";

    write batch_move_tasks(BatchMoveTasksArgs) -> batch::batch_move_tasks;
        "Move multiple tasks to a target list. Use when reorganizing tasks between lists, during list restructuring, or when the user asks to group tasks to a different list. Returns {moved_count, list_id, tasks}.";

    raw {
        #[::rmcp::tool(
            description = "Cancel tasks in a list with optional status filter. Use when a list is cancelled and all its remaining tasks should be dropped, or when cleaning up obsolete tasks in bulk. Optional `statuses` array filters which tasks to cancel (valid values: open, completed, cancelled, someday; default: open only). Pass cancel_series=true to stop recurring series rather than skip-and-spawn. Pass dry_run=true to preview without persisting. Returns {cancelled_count, cancelled, list_id, statuses, dry_run?}."
        )]
        pub(crate) fn batch_cancel_tasks_in_list(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<BatchCancelTasksInListArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            self.dispatch_dry_run(
                dry_run,
                "batch_cancel_tasks_in_list",
                lorvex_domain::naming::ENTITY_TASK,
                |value| {
                    let n = value
                        .get("cancelled_count")
                        .and_then(serde_json::Value::as_u64)
                        .unwrap_or(0);
                    format!("cancel {n} task(s) in list")
                },
                |value| crate::system::handler_support::collect_id_strings(value.get("cancelled")),
                move |conn| batch::batch_cancel_tasks_in_list(conn, args),
            )
        }
    }

    write set_recurrence(SetRecurrenceArgs) -> lifecycle::set_recurrence;
        "Set or update the recurrence schedule on an existing task. Uses RRULE-aligned format. freq accepts daily/weekly/monthly/yearly. Optional fields: interval (positive int), byday (array of two-letter weekday codes — MO/TU/WE/TH/FR/SA/SU; positional prefixes like 1MO or -1FR allowed), bymonth (array of 1-12), bymonthday (array of 1-31 or negative for end-of-month, e.g. -1 = last day), bysetpos (array of 1-366 or negative), wkst (single weekday code), until (YYYY-MM-DD inclusive), count (positive int — mutually exclusive with until). Returns the full updated task object.";

    write add_task_recurrence_exception(AddTaskRecurrenceExceptionArgs)
        -> lifecycle::add_task_recurrence_exception;
        "Add a recurrence exception date to skip a specific occurrence of a recurring task. The date must be a valid occurrence of the recurrence pattern. Returns the full updated task object.";

    write remove_task_recurrence_exception(RemoveTaskRecurrenceExceptionArgs)
        -> lifecycle::remove_task_recurrence_exception;
        "Remove a recurrence exception date, restoring a previously skipped occurrence of a recurring task. Returns the full updated task object.";

    write set_task_ai_notes(SetTaskAiNotesArgs) -> lifecycle::set_task_ai_notes;
        "Replace the assistant-maintained context block for a task without changing canonical task notes. Pass an empty notes string to clear the block. Returns the full updated task object.";

    write append_to_task_body(AppendToTaskBodyArgs) -> lifecycle::append_to_task_body;
        "Append text to a task's body/notes without replacing existing content. The text is added after a blank line separator. Use this for adding observations, context, or quick notes to a task. Returns the full updated task object.";

    write defer_task(DeferTaskArgs) -> lifecycle::defer_task;
        "Set a task's planned_date to an absolute target day. Canonical deferral semantics are absolute, not relative. Increments defer_count, records reason in ai_notes, and keeps the task status=open. Optional `structured_reason` selects from a fixed enum (one of: not_today, blocked, low_energy, needs_breakdown, needs_info) and is stored in last_defer_reason for analytics; the free-form `reason` is the prose appended to ai_notes. Returns the full updated task object.";

    write set_task_reminders(SetTaskRemindersArgs) -> lifecycle::set_task_reminders;
        "Replace all pending reminders for a task. Pass an empty array to clear. Previously notified reminders are preserved. Use when setting multiple reminders at once or replacing all existing reminders. Returns the full updated task object.";

    write add_task_reminder(AddTaskReminderArgs) -> lifecycle::add_task_reminder;
        "Append one reminder to a task without replacing its other pending reminders. Use this for one-off reminder additions at a specific time and return the full updated task object.";

    write add_task_checklist_item(AddTaskChecklistItemArgs)
        -> lifecycle::add_task_checklist_item;
        "Append or insert one checklist item on a task. Use position to insert at a zero-based index; omit it to append. Returns the full updated task object with checklist_items.";

    write update_task_checklist_item(UpdateTaskChecklistItemArgs)
        -> lifecycle::update_task_checklist_item;
        "Update one checklist item's text and return the full updated parent task object with checklist_items.";

    write toggle_task_checklist_item(ToggleTaskChecklistItemArgs)
        -> lifecycle::toggle_task_checklist_item;
        "Set one checklist item's completed state. Pass completed=true to mark complete or completed=false to mark incomplete. Returns the full updated parent task object with checklist_items.";

    write remove_task_checklist_item(RemoveTaskChecklistItemArgs)
        -> lifecycle::remove_task_checklist_item;
        "Remove one checklist item by item_id and return the full updated parent task object with checklist_items.";

    write reorder_task_checklist_items(ReorderTaskChecklistItemsArgs)
        -> lifecycle::reorder_task_checklist_items;
        "Reorder a task's checklist by supplying the full ordered item_ids array. The array must contain every existing checklist item exactly once. Returns the full updated parent task object with checklist_items.";

    write remove_task_reminder(RemoveTaskReminderArgs) -> lifecycle::remove_task_reminder;
        "Remove a single reminder from a task by reminder ID. Use when the user wants to cancel a specific reminder without affecting other reminders on the same task. Returns the full updated task object.";

    write complete_task(CompleteTaskArgs) -> lifecycle::complete_task;
        "Mark a task as completed. Returns {completed, next_occurrence, newly_unblocked} — includes any spawned recurring instance and tasks that were waiting on this one.";

    write reopen_task(ReopenTaskArgs) -> lifecycle::reopen_task;
        "Reopen a completed or cancelled task (set back to open status). Clears completed_at, planned_date, last_deferred_at, and defer_count. For completed recurring tasks, also cancels auto-spawned successor instances to prevent duplicates. Returns the full updated task object.";

    raw {
        #[::rmcp::tool(
            description = "Soft-delete a task (status=cancelled). For recurring tasks: by default, cancellation skips this occurrence and spawns the next one (the series continues). Pass cancel_series=true to stop the entire series. Pass dry_run=true to preview the cascade (cancelled reminders, dependency unblocks, recurrence successor spawn) before committing. Returns {cancelled, next_occurrence, dependency_updates, dry_run?}."
        )]
        pub(crate) fn cancel_task(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<CancelTaskArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            let task_id = args.id.clone();
            self.dispatch_dry_run(
                dry_run,
                "cancel_task",
                lorvex_domain::naming::ENTITY_TASK,
                move |_| format!("cancel task {task_id}"),
                |value| {
                    value
                        .get("cancelled")
                        .map(crate::system::handler_support::extract_top_level_id)
                        .unwrap_or_default()
                },
                move |conn| lifecycle::cancel_task(conn, args),
            )
        }

        #[::rmcp::tool(
            description = "Irreversibly delete a task row from the database. Prefer cancel_task for soft-delete. Only use for duplicates or test data. Pass dry_run=true to preview the pre-delete snapshot (and confirm the archive gate is passed) without actually deleting. Pass idempotency_key when retrying after transport failure so the original hard-delete response is replayed. Returns {id, deleted, previous, dry_run?}."
        )]
        pub(crate) fn permanent_delete_task(
            &self,
            ::rmcp::handler::server::wrapper::Parameters(args):
                ::rmcp::handler::server::wrapper::Parameters<PermanentDeleteTaskArgs>,
        ) -> Result<String, String> {
            let dry_run = args.dry_run;
            let task_id = args.id.clone();
            self.dispatch_dry_run(
                dry_run,
                "permanent_delete_task",
                lorvex_domain::naming::ENTITY_TASK,
                move |_| format!("permanently delete task {task_id}"),
                crate::system::handler_support::extract_top_level_id,
                move |conn| lifecycle::permanent_delete_task(conn, args),
            )
        }
    }
}
