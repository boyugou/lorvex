//! Two-level dispatch enum consumed by `main.rs`. The clap-derive layer in
//! [`super::args`] parses the user's argv into a nested tree, and the
//! [`super::translate`] layer flattens it into one `Command::Domain(...)`
//! variant per dispatch arm. Variant shapes are preserved exactly — every
//! field on a variant must be set by the corresponding translator.
//!
//! The umbrella enum here is keyed by domain. Each per-domain enum lives in
//! its own sibling file under [`super::command`], mirroring the existing
//! per-domain organisation in `cli/args/`, `cli/translate/`, `commands/`,
//! and dispatch.

use clap::ValueEnum;

mod calendar;
mod focus;
mod habits;
mod lists;
mod memory;
mod preferences;
mod reminders;
mod review;
mod subscription;
mod sync;
mod system;
mod tags;
mod tasks;
mod trash;
mod workflow;

pub(crate) use calendar::{AttendeesPatch, CalendarCommand};
pub(crate) use focus::FocusCommand;
pub(crate) use habits::HabitsCommand;
pub(crate) use lists::ListsCommand;
pub(crate) use memory::MemoryCommand;
pub(crate) use preferences::PreferencesCommand;
pub(crate) use reminders::RemindersCommand;
pub(crate) use review::ReviewCommand;
pub(crate) use subscription::SubscriptionCommand;
pub(crate) use sync::SyncCommand;
pub(crate) use system::SystemCommand;
pub(crate) use tags::TagsCommand;
pub(crate) use tasks::TasksCommand;
pub(crate) use trash::TrashCommand;
pub(crate) use workflow::WorkflowCommand;

/// Parsed invocation, produced by [`super::CliArgs::parse`]. The wrapping
/// struct exists so callers can pattern-match on `args.command`
/// just like before the clap migration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CliArgs {
    pub(crate) command: Command,
}

/// Top-level dispatch enum. Each variant carries one per-domain
/// sub-enum whose variants mirror the subcommand tree but flatten any
/// deeply-nested groups within that domain.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Command {
    System(SystemCommand),
    Sync(SyncCommand),
    Tasks(TasksCommand),
    Trash(TrashCommand),
    Reminders(RemindersCommand),
    Lists(ListsCommand),
    Focus(FocusCommand),
    Calendar(CalendarCommand),
    Habits(HabitsCommand),
    Memory(MemoryCommand),
    Preferences(PreferencesCommand),
    Tags(TagsCommand),
    Workflow(WorkflowCommand),
    Review(ReviewCommand),
    Subscription(SubscriptionCommand),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub(crate) enum McpInstallTarget {
    #[value(name = "claude-desktop")]
    ClaudeDesktop,
    #[value(name = "claude-code")]
    ClaudeCode,
    #[value(name = "codex")]
    Codex,
    #[value(name = "all")]
    All,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum OutputFormat {
    Text,
    Json,
}

impl OutputFormat {
    /// Return the process-wide default selected by the global
    /// `--format <text|json>` option before clap parses subcommands.
    pub(crate) fn default() -> Self {
        crate::format_override::default_output_format()
    }
}
