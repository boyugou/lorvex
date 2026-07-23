use super::super::args::CaptureArgs;
use super::super::command::{Command, OutputFormat, TasksCommand};

pub(in crate::cli) fn translate_capture(args: CaptureArgs) -> Command {
    let CaptureArgs {
        title,
        list,
        priority,
        due_date,
        planned_date,
        estimated_minutes,
        tags,
    } = args;
    Command::Tasks(TasksCommand::Capture {
        title: title.join(" "),
        list,
        priority,
        due_date,
        planned_date,
        estimated_minutes,
        tags,
        format: OutputFormat::default(),
    })
}
