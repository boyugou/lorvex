//! `lorvex tags …` dispatcher.

use crate::cli::TagsCommand;
use crate::commands::mutate::run_tag_rename;
use crate::commands::query::{run_tag_tasks, run_tags};
use crate::error::CliError;

pub(super) fn dispatch_tags(command: TagsCommand) -> Result<(), CliError> {
    match command {
        TagsCommand::List { format } => println!("{}", run_tags(format)?),
        TagsCommand::Tasks { tag_name, format } => {
            println!("{}", run_tag_tasks(&tag_name, format)?);
        }
        TagsCommand::Rename {
            old_name,
            new_name,
            format,
        } => println!("{}", run_tag_rename(&old_name, &new_name, format)?),
    }
    Ok(())
}
