//! Command-line interface for `lorvex-cli`.
//!
//! Issue #2316 migrated the original hand-rolled pattern-match parser
//! to `clap` v4 (derive API). The directory layout splits that work
//! into three layers:
//!
//! - [`command`] — the flat [`Command`] dispatch enum consumed by
//!   `main.rs`, plus [`OutputFormat`] / [`McpInstallTarget`] /
//!   [`CliArgs`] surface types.
//! - [`args`] — clap-derive parse tree ([`args::ClapCli`] root) and
//!   per-domain argument structs.
//! - [`translate`] — flatten the nested clap tree into the wide
//!   `Command` enum, preserving the pre-migration semantic contract.
//!
//! Tests for the whole layer live in this module so they reach across
//! every submodule via `use super::*;`.

mod args;
mod argv_defaults;
mod clap_patch;
mod command;
mod parsers;
mod translate;

pub(crate) use args::ClapCli;
pub(crate) use command::{
    AttendeesPatch, CalendarCommand, CliArgs, Command, FocusCommand, HabitsCommand, ListsCommand,
    McpInstallTarget, MemoryCommand, OutputFormat, PreferencesCommand, RemindersCommand,
    ReviewCommand, SubscriptionCommand, SyncCommand, SystemCommand, TagsCommand, TasksCommand,
    TrashCommand, WorkflowCommand,
};

impl CliArgs {
    /// Parse command-line arguments. On `--help` / `--version` / bad
    /// args clap prints to stderr / stdout and exits the process
    /// directly; this function only returns on a successful parse.
    ///
    /// Exit-code contract preserved from the hand-rolled parser:
    /// - good args → returns, caller runs the command (exit 0 on
    ///   success, 1 on runtime error — handled by `main.rs`).
    /// - `--help` / `-h` / `--version` / `-V` → clap prints + exits 0.
    /// - bad args / unknown subcommand → clap prints + exits 2.
    pub(crate) fn parse(args: Vec<String>) -> Self {
        // Re-insert the program name so clap's usage strings look
        // right. `std::env::args().skip(1)` strips it in `main.rs`.
        let argv: Vec<String> = std::iter::once("lorvex".to_string())
            .chain(argv_defaults::rewrite_default_subcommands(args))
            .collect();
        let clap = <ClapCli as clap::Parser>::parse_from(argv);
        Self {
            command: translate::translate(clap.command),
        }
    }

    /// Test-only fallible parser that returns a `clap::Error` instead
    /// of exiting the process. Enables assertions like "bare `lorvex`
    /// fails with MissingSubcommand" without tearing down the test
    /// process.
    #[cfg(test)]
    pub(crate) fn try_parse(args: Vec<String>) -> Result<Self, clap::Error> {
        let argv: Vec<String> = std::iter::once("lorvex".to_string())
            .chain(argv_defaults::rewrite_default_subcommands(args))
            .collect();
        let clap = <ClapCli as clap::Parser>::try_parse_from(argv)?;
        Ok(Self {
            command: translate::translate(clap.command),
        })
    }
}

#[cfg(test)]
mod tests;
