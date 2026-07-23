//! Top-level command dispatcher for the CLI.
//!
//! `main.rs` parses the global flags and the clap argv, then hands the
//! resulting [`crate::cli::Command`] off to [`dispatch_command`]. The
//! match below forwards each variant to a per-domain dispatcher in a
//! sibling module ([`tasks`], [`calendar`], …); each per-domain file
//! owns the imports its arms actually need so the surface area stays
//! navigable as the command tree grows.
//!
//! Most domain dispatchers are synchronous (their arms only call the
//! sync `run_*` helpers that print). The [`system`] domain is the one
//! exception — its `tui-watch` and `mcp-serve` arms drive async loops,
//! so [`system::dispatch_system`] is `async fn` and is awaited on the
//! `Command::System` arm below.

mod calendar;
mod focus;
mod habits;
mod lists;
mod memory;
mod preferences;
mod reminders;
mod review;
mod subscriptions;
mod system;
mod tags;
mod tasks;
mod trash;
mod workflow;

use crate::cli::Command;
use crate::error::CliError;

pub(crate) async fn dispatch_command(command: Command) -> Result<(), CliError> {
    match command {
        Command::System(c) => system::dispatch_system(c).await?,
        Command::Sync(c) => system::dispatch_sync(&c)?,
        Command::Tasks(c) => tasks::dispatch_tasks(c)?,
        Command::Trash(c) => trash::dispatch_trash(c)?,
        Command::Reminders(c) => reminders::dispatch_reminders(c)?,
        Command::Lists(c) => lists::dispatch_lists(c)?,
        Command::Focus(c) => focus::dispatch_focus(c)?,
        Command::Calendar(c) => calendar::dispatch_calendar(c)?,
        Command::Habits(c) => habits::dispatch_habits(c)?,
        Command::Memory(c) => memory::dispatch_memory(c)?,
        Command::Preferences(c) => preferences::dispatch_preferences(c)?,
        Command::Tags(c) => tags::dispatch_tags(c)?,
        Command::Workflow(c) => workflow::dispatch_workflow(c)?,
        Command::Review(c) => review::dispatch_review(c)?,
        Command::Subscription(c) => subscriptions::dispatch_subscriptions(c)?,
    }
    Ok(())
}
