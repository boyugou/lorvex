//! `lorvex task <subcommand>` — explicit task-write namespace
//! (create, set-recurrence, permanent-delete, batch-create,
//! batch-update, batch-cancel-in-list).

use super::super::args::{
    BatchCancelInListArgs, BatchCreateArgs, BatchUpdateArgs, PermanentDeleteArgs,
    SetRecurrenceArgs, TaskCreateArgs, TaskWriteCmd,
};
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_task(cmd: TaskWriteCmd) -> Command {
    match cmd {
        TaskWriteCmd::Create(TaskCreateArgs {
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
        }) => Command::Tasks(TasksCommand::Create {
            title: title.join(" "),
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
            format: OutputFormat::default(),
        }),
        TaskWriteCmd::SetRecurrence(SetRecurrenceArgs {
            task_id,
            freq,
            interval,
            byday,
            bymonthday,
            until,
            count,
        }) => Command::Tasks(TasksCommand::SetRecurrence {
            task_id,
            freq: freq.as_serde_value(),
            interval,
            byday,
            bymonthday,
            until,
            count,
            format: OutputFormat::default(),
        }),
        TaskWriteCmd::PermanentDelete(PermanentDeleteArgs { task_id, dry_run }) => {
            Command::Tasks(TasksCommand::PermanentDelete {
                task_id,
                dry_run,
                format: OutputFormat::default(),
            })
        }
        TaskWriteCmd::BatchCreate(BatchCreateArgs {
            tasks_json,
            include_advice,
            idempotency_key,
            dry_run,
        }) => Command::Tasks(TasksCommand::BatchCreate {
            tasks_json,
            include_advice,
            idempotency_key,
            dry_run,
            format: OutputFormat::default(),
        }),
        TaskWriteCmd::BatchUpdate(BatchUpdateArgs {
            updates_json,
            dry_run,
        }) => Command::Tasks(TasksCommand::BatchUpdate {
            updates_json,
            dry_run,
            format: OutputFormat::default(),
        }),
        TaskWriteCmd::BatchCancelInList(BatchCancelInListArgs {
            list_id,
            statuses,
            cancel_series,
            dry_run,
        }) => Command::Tasks(TasksCommand::BatchCancelInList {
            list_id,
            statuses,
            cancel_series: cancel_series.then_some(true),
            dry_run,
            format: OutputFormat::default(),
        }),
    }
}
