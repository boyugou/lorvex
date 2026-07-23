use super::super::args::{TagCmd, TagRenameArgs, TagTasksArgs};
use super::super::command::{Command, OutputFormat, TagsCommand};

pub(in crate::cli) fn translate_tag(cmd: TagCmd) -> Command {
    Command::Tags(match cmd {
        TagCmd::Tasks(TagTasksArgs { tag_name }) => TagsCommand::Tasks {
            tag_name: tag_name.join(" "),
            format: OutputFormat::default(),
        },
        TagCmd::Rename(TagRenameArgs { old_name, new_name }) => TagsCommand::Rename {
            old_name,
            new_name,
            format: OutputFormat::default(),
        },
    })
}
