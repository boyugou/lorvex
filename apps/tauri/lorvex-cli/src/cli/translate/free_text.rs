//! Free-text mutators that just splice CLI positional args back into a
//! single string before reaching the store: `append-body` and
//! `add-ai-notes`.

use super::super::args::TaskFreeTextArgs;
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_append_body(args: TaskFreeTextArgs) -> Command {
    let TaskFreeTextArgs { task_id, text } = args;
    Command::Tasks(TasksCommand::AppendBody {
        task_id,
        text: text.join(" "),
        format: OutputFormat::default(),
    })
}

pub(in crate::cli) fn translate_add_ai_notes(args: TaskFreeTextArgs) -> Command {
    let TaskFreeTextArgs { task_id, text } = args;
    Command::Tasks(TasksCommand::AddAiNotes {
        task_id,
        notes: text.join(" "),
        format: OutputFormat::default(),
    })
}
