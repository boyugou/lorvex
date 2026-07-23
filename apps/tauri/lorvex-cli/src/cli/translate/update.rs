use super::super::args::TaskUpdateArgs;
use super::super::clap_patch::{optional_vec_patch, tri_state_clearable};
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_update(args: Box<TaskUpdateArgs>) -> Command {
    let TaskUpdateArgs {
        task_id,
        title,
        body,
        clear_body,
        ai_notes,
        clear_ai_notes,
        status,
        raw_input,
        list,
        priority,
        clear_priority,
        due_date,
        clear_due_date,
        due_time,
        clear_due_time,
        planned_date,
        clear_planned_date,
        estimated_minutes,
        clear_estimated_minutes,
        tag_set,
        clear_tags,
        tag_add,
        tag_remove,
        depends_on_set,
        clear_depends_on,
        depends_on_add,
        depends_on_remove,
        recurrence,
        clear_recurrence,
        idempotency_key,
    } = *args;
    Command::Tasks(TasksCommand::Update {
        task_id,
        title,
        body: tri_state_clearable(body, clear_body),
        ai_notes: tri_state_clearable(ai_notes, clear_ai_notes),
        // pass status / raw_input through to
        // the patch handler. Both are flat options because
        // neither column supports a "clear" semantic in the
        // current write path (status is non-null; raw_input
        // wasn't even reachable from the CLI before).
        status,
        raw_input,
        list_id: list,
        priority: tri_state_clearable(priority, clear_priority),
        due_date: tri_state_clearable(due_date, clear_due_date),
        due_time: tri_state_clearable(due_time, clear_due_time),
        planned_date: tri_state_clearable(planned_date, clear_planned_date),
        estimated_minutes: tri_state_clearable(estimated_minutes, clear_estimated_minutes),
        tags_set: if clear_tags {
            Some(Vec::new())
        } else {
            optional_vec_patch(tag_set)
        },
        tags_add: optional_vec_patch(tag_add),
        tags_remove: optional_vec_patch(tag_remove),
        depends_on_set: if clear_depends_on {
            Some(Vec::new())
        } else {
            optional_vec_patch(depends_on_set)
        },
        depends_on_add: optional_vec_patch(depends_on_add),
        depends_on_remove: optional_vec_patch(depends_on_remove),
        recurrence: tri_state_clearable(recurrence, clear_recurrence),
        idempotency_key,
        format: OutputFormat::default(),
    })
}
