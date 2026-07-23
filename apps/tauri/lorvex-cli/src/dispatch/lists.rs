//! `lorvex lists …` dispatcher.

use crate::cli::ListsCommand;
use crate::commands::mutate::{run_list_create, run_list_delete, run_list_update};
use crate::commands::query::{run_list_health, run_list_show, run_lists};
use crate::error::CliError;

pub(super) fn dispatch_lists(command: ListsCommand) -> Result<(), CliError> {
    match command {
        ListsCommand::List { format } => println!("{}", run_lists(format)?),
        ListsCommand::Show {
            list_id,
            limit,
            format,
        } => println!("{}", run_list_show(&list_id, limit, format)?),
        ListsCommand::Health { limit, format } => {
            println!("{}", run_list_health(limit, format)?);
        }
        ListsCommand::Create {
            name,
            color,
            icon,
            description,
            format,
        } => println!(
            "{}",
            run_list_create(
                &name,
                color.as_deref(),
                icon.as_deref(),
                description.as_deref(),
                format,
            )?
        ),
        ListsCommand::Update {
            list_id,
            name,
            color,
            icon,
            description,
            ai_notes,
            format,
        } => println!(
            "{}",
            // Borrow each `Patch<String>` as `Patch<&str>` so the handler can
            // route Set/Clear/Unset without owning the underlying strings.
            run_list_update(
                &list_id,
                name.as_deref(),
                color.as_deref(),
                icon.as_deref(),
                description.as_deref(),
                ai_notes.as_deref(),
                format,
            )?
        ),
        ListsCommand::Delete { list_id, format } => {
            println!("{}", run_list_delete(&list_id, format)?);
        }
    }
    Ok(())
}
