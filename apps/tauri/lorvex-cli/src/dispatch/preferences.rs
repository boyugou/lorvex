//! `lorvex preferences …` dispatcher.

use crate::cli::PreferencesCommand;
use crate::commands::mutate::{run_preference_delete, run_preference_set};
use crate::commands::query::{run_preference_get, run_preferences};
use crate::error::CliError;

pub(super) fn dispatch_preferences(command: PreferencesCommand) -> Result<(), CliError> {
    match command {
        PreferencesCommand::List { format } => println!("{}", run_preferences(format)?),
        PreferencesCommand::Get { key, format } => {
            println!("{}", run_preference_get(&key, format)?);
        }
        PreferencesCommand::Set {
            key,
            value_json,
            format,
        } => println!("{}", run_preference_set(&key, &value_json, format)?),
        PreferencesCommand::Delete { key, format } => {
            println!("{}", run_preference_delete(&key, format)?);
        }
    }
    Ok(())
}
