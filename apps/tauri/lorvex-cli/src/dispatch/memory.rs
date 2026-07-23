//! `lorvex memory …` dispatcher (durable agent memory KV).

use crate::cli::MemoryCommand;
use crate::commands::mutate::{run_memory_delete, run_memory_restore, run_memory_write};
use crate::commands::query::{run_memory_history, run_memory_list, run_memory_show};
use crate::error::CliError;

pub(super) fn dispatch_memory(command: MemoryCommand) -> Result<(), CliError> {
    match command {
        MemoryCommand::List { format } => println!("{}", run_memory_list(format)?),
        MemoryCommand::Show { key, format } => println!("{}", run_memory_show(&key, format)?),
        MemoryCommand::Write {
            key,
            content,
            format,
        } => println!("{}", run_memory_write(&key, &content, format)?),
        MemoryCommand::Delete { key, format } => {
            println!("{}", run_memory_delete(&key, format)?);
        }
        MemoryCommand::History { key, limit, format } => {
            println!("{}", run_memory_history(&key, limit, format)?);
        }
        MemoryCommand::Restore {
            revision_id,
            format,
        } => println!("{}", run_memory_restore(&revision_id, format)?),
    }
    Ok(())
}
