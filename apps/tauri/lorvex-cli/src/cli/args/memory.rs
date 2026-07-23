//! AI memory store argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::{parse_positive_u32, parse_revision_id};
#[derive(Subcommand, Debug)]
pub(in crate::cli) enum MemoryCmd {
    /// List AI memory entries.
    List,
    /// Show a single memory entry by key.
    Show(MemoryShowArgs),
    /// Write or update an AI memory entry.
    Write(MemoryWriteArgs),
    /// Delete an AI memory entry.
    Delete(MemoryKeyArgs),
    /// Show revision history for an AI memory key.
    History(MemoryHistoryArgs),
    /// Restore an AI memory entry from a revision ID.
    Restore(MemoryRestoreArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct MemoryShowArgs {
    pub(in crate::cli) key: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct MemoryWriteArgs {
    pub(in crate::cli) key: String,
    /// One or more words for the memory content (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) content: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct MemoryKeyArgs {
    pub(in crate::cli) key: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct MemoryHistoryArgs {
    pub(in crate::cli) key: String,
    #[arg(short = 'l', long = "limit", default_value_t = 20, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct MemoryRestoreArgs {
    #[arg(value_parser = parse_revision_id)]
    pub(in crate::cli) revision_id: String,
}
