use super::super::args::{
    ChecklistAddArgs, ChecklistCmd, ChecklistRemoveArgs, ChecklistReorderArgs, ChecklistToggleArgs,
    ChecklistUpdateArgs,
};
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_checklist(cmd: ChecklistCmd) -> Command {
    match cmd {
        ChecklistCmd::Add(ChecklistAddArgs {
            task_id,
            text,
            position,
        }) => Command::Tasks(TasksCommand::ChecklistAdd {
            task_id,
            text: text.join(" "),
            position,
            format: OutputFormat::default(),
        }),
        ChecklistCmd::Update(ChecklistUpdateArgs { item_id, text }) => {
            Command::Tasks(TasksCommand::ChecklistUpdate {
                item_id,
                text: text.join(" "),
                format: OutputFormat::default(),
            })
        }
        ChecklistCmd::Toggle(ChecklistToggleArgs {
            item_id,
            completed,
            uncompleted,
        }) => {
            let completed = completed && !uncompleted;
            Command::Tasks(TasksCommand::ChecklistToggle {
                item_id,
                completed,
                format: OutputFormat::default(),
            })
        }
        ChecklistCmd::Remove(ChecklistRemoveArgs { item_id }) => {
            Command::Tasks(TasksCommand::ChecklistRemove {
                item_id,
                format: OutputFormat::default(),
            })
        }
        ChecklistCmd::Reorder(ChecklistReorderArgs { task_id, item_ids }) => {
            Command::Tasks(TasksCommand::ChecklistReorder {
                task_id,
                item_ids,
                format: OutputFormat::default(),
            })
        }
    }
}
