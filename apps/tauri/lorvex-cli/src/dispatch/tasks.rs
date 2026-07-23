//! `lorvex tasks …` dispatcher. Covers the read surfaces (search, list,
//! show, today/overdue/upcoming/deferred, dependency graph), the
//! free-form mutation arms (capture, update, complete, cancel, reopen,
//! defer, append-body, ai-notes, recurrence-exception add/remove, move),
//! and the structured workflow writes (create, set-recurrence, batch
//! create/update, batch-cancel-in-list, permanent-delete, checklist
//! add/update/toggle/remove/reorder).

use crate::cli::TasksCommand;
use crate::commands::mutate::tasks::capture_effects::CaptureTaskOptions;
use crate::commands::mutate::tasks::lifecycle_effects::TaskUpdateFields;
use crate::commands::mutate::{
    run_cancel_tasks, run_capture, run_complete_tasks, run_defer_tasks, run_move_tasks,
    run_reopen_tasks, run_task_add_ai_notes, run_task_add_recurrence_exception,
    run_task_append_body, run_task_remove_recurrence_exception, run_update_task,
};
use crate::commands::query::{
    run_deferred, run_dependency_graph, run_overdue, run_search, run_show, run_tasks, run_today,
    run_upcoming, DependencyGraphCliQuery, TaskListCliQuery,
};
use crate::commands::workflow as wf;
use crate::error::CliError;

pub(super) fn dispatch_tasks(command: TasksCommand) -> Result<(), CliError> {
    match command {
        TasksCommand::Search {
            query,
            limit,
            format,
        } => println!("{}", run_search(&query, limit, format)?),
        TasksCommand::List {
            list_id,
            status,
            priority,
            due_from,
            due_to,
            planned_from,
            planned_to,
            completed_from,
            completed_to,
            created_from,
            created_to,
            has_due_date,
            has_planned_date,
            tags,
            text,
            blocked_only,
            blocking_others,
            sort_by,
            sort_direction,
            limit,
            format,
        } => println!(
            "{}",
            run_tasks(
                TaskListCliQuery {
                    list_id,
                    status,
                    priority,
                    due_from,
                    due_to,
                    planned_from,
                    planned_to,
                    completed_from,
                    completed_to,
                    created_from,
                    created_to,
                    has_due_date,
                    has_planned_date,
                    tags,
                    text,
                    blocked_only,
                    blocking_others,
                    sort_by,
                    sort_direction,
                    limit,
                },
                format,
            )?
        ),
        TasksCommand::DependencyGraph {
            task_id,
            list_id,
            include_inactive,
            limit_nodes,
            limit_edges,
            format,
        } => println!(
            "{}",
            run_dependency_graph(
                DependencyGraphCliQuery {
                    task_id,
                    list_id,
                    include_inactive,
                    limit_nodes,
                    limit_edges,
                },
                format,
            )?
        ),
        TasksCommand::Show { task_id, format } => println!("{}", run_show(&task_id, format)?),
        TasksCommand::Today { limit, format } => println!("{}", run_today(limit, format)?),
        TasksCommand::Overdue { limit, format } => println!("{}", run_overdue(limit, format)?),
        TasksCommand::Upcoming {
            days,
            limit,
            format,
        } => println!("{}", run_upcoming(days, limit, format)?),
        TasksCommand::Deferred {
            list_id,
            limit,
            format,
        } => println!("{}", run_deferred(list_id.as_deref(), limit, format)?),
        TasksCommand::Capture {
            title,
            list,
            priority,
            due_date,
            planned_date,
            estimated_minutes,
            tags,
            format,
        } => println!(
            "{}",
            run_capture(
                &title,
                CaptureTaskOptions {
                    list_id_override: list.as_deref(),
                    priority,
                    due_date: due_date.as_deref(),
                    planned_date: planned_date.as_deref(),
                    estimated_minutes,
                    tags: if tags.is_empty() { None } else { Some(&tags) },
                },
                format,
            )?
        ),
        TasksCommand::Update {
            task_id,
            title,
            body,
            ai_notes,
            status,
            raw_input,
            list_id,
            priority,
            due_date,
            due_time,
            planned_date,
            estimated_minutes,
            tags_set,
            tags_add,
            tags_remove,
            depends_on_set,
            depends_on_add,
            depends_on_remove,
            recurrence,
            idempotency_key,
            format,
        } => println!(
            "{}",
            run_update_task(
                &task_id,
                &TaskUpdateFields {
                    title: title.as_deref(),
                    body: body.as_deref(),
                    ai_notes: ai_notes.as_deref(),
                    // thread the new flags through. `status` is a flat option;
                    // the canonical write path resolves the lifecycle side
                    // effects from the requested value.
                    status: status.as_deref(),
                    raw_input: raw_input.as_deref(),
                    list_id: list_id.as_deref(),
                    priority,
                    due_date: due_date.as_deref(),
                    due_time: due_time.as_deref(),
                    planned_date: planned_date.as_deref(),
                    estimated_minutes,
                    tags_set: tags_set.as_deref(),
                    tags_add: tags_add.as_deref(),
                    tags_remove: tags_remove.as_deref(),
                    depends_on_set: depends_on_set.as_deref(),
                    depends_on_add: depends_on_add.as_deref(),
                    depends_on_remove: depends_on_remove.as_deref(),
                    recurrence: recurrence.as_deref(),
                    idempotency_key: idempotency_key.as_deref(),
                },
                format,
            )?
        ),
        TasksCommand::Complete { task_ids, format } => {
            println!("{}", run_complete_tasks(&task_ids, format)?);
        }
        TasksCommand::Cancel {
            task_ids,
            cancel_series,
            format,
        } => println!(
            "{}",
            run_cancel_tasks(&task_ids, cancel_series.unwrap_or(false), format)?
        ),
        TasksCommand::Reopen { task_ids, format } => {
            println!("{}", run_reopen_tasks(&task_ids, format)?);
        }
        TasksCommand::Defer {
            task_ids,
            days,
            reason,
            structured_reason,
            format,
        } => println!(
            "{}",
            run_defer_tasks(
                &task_ids,
                days,
                reason.as_deref(),
                structured_reason.as_deref(),
                format,
            )?
        ),
        TasksCommand::AppendBody {
            task_id,
            text,
            format,
        } => println!("{}", run_task_append_body(&task_id, &text, format)?),
        TasksCommand::AddAiNotes {
            task_id,
            notes,
            format,
        } => println!("{}", run_task_add_ai_notes(&task_id, &notes, format)?),
        TasksCommand::AddRecurrenceException {
            task_id,
            date,
            format,
        } => println!(
            "{}",
            run_task_add_recurrence_exception(&task_id, &date, format)?
        ),
        TasksCommand::RemoveRecurrenceException {
            task_id,
            date,
            format,
        } => println!(
            "{}",
            run_task_remove_recurrence_exception(&task_id, &date, format)?
        ),
        TasksCommand::Move {
            list_id,
            task_ids,
            format,
        } => println!("{}", run_move_tasks(&list_id, &task_ids, format)?),
        TasksCommand::ChecklistAdd {
            task_id,
            text,
            position,
            format,
        } => println!(
            "{}",
            wf::run_checklist_add(&task_id, &text, position, format)?
        ),
        TasksCommand::ChecklistUpdate {
            item_id,
            text,
            format,
        } => println!("{}", wf::run_checklist_update(&item_id, &text, format)?),
        TasksCommand::ChecklistToggle {
            item_id,
            completed,
            format,
        } => println!("{}", wf::run_checklist_toggle(&item_id, completed, format)?),
        TasksCommand::ChecklistRemove { item_id, format } => {
            println!("{}", wf::run_checklist_remove(&item_id, format)?);
        }
        TasksCommand::ChecklistReorder {
            task_id,
            item_ids,
            format,
        } => println!(
            "{}",
            wf::run_checklist_reorder(&task_id, &item_ids, format)?
        ),
        TasksCommand::Create {
            title,
            list_id,
            priority,
            due_date,
            due_time,
            planned_date,
            estimated_minutes,
            tags,
            body,
            ai_notes,
            depends_on,
            reminders,
            recurrence,
            completed,
            idempotency_key,
            format,
        } => println!(
            "{}",
            wf::run_task_create(
                &wf::TaskCreateInputs {
                    title: &title,
                    list_id: list_id.as_deref(),
                    priority,
                    due_date: due_date.as_deref(),
                    due_time: due_time.as_deref(),
                    planned_date: planned_date.as_deref(),
                    estimated_minutes,
                    tags: &tags,
                    body: body.as_deref(),
                    ai_notes: ai_notes.as_deref(),
                    depends_on: &depends_on,
                    reminders: &reminders,
                    recurrence: recurrence.as_deref(),
                    completed,
                    idempotency_key: idempotency_key.as_deref(),
                },
                format,
            )?
        ),
        TasksCommand::SetRecurrence {
            task_id,
            freq,
            interval,
            byday,
            bymonthday,
            until,
            count,
            format,
        } => println!(
            "{}",
            wf::run_set_recurrence(
                &wf::SetRecurrenceInputs {
                    task_id: &task_id,
                    freq,
                    interval,
                    byday: &byday,
                    bymonthday: &bymonthday,
                    until: until.as_deref(),
                    count,
                },
                format,
            )?
        ),
        TasksCommand::PermanentDelete {
            task_id,
            dry_run,
            format,
        } => println!("{}", wf::run_permanent_delete(&task_id, dry_run, format)?),
        TasksCommand::BatchCreate {
            tasks_json,
            include_advice,
            idempotency_key,
            dry_run,
            format,
        } => println!(
            "{}",
            wf::run_batch_create(
                &tasks_json,
                include_advice,
                idempotency_key.as_deref(),
                dry_run,
                format,
            )?
        ),
        TasksCommand::BatchUpdate {
            updates_json,
            dry_run,
            format,
        } => println!("{}", wf::run_batch_update(&updates_json, dry_run, format)?),
        TasksCommand::BatchCancelInList {
            list_id,
            statuses,
            cancel_series,
            dry_run,
            format,
        } => println!(
            "{}",
            wf::run_batch_cancel_in_list(&list_id, &statuses, cancel_series, dry_run, format)?
        ),
    }
    Ok(())
}
