//! Tag argument structs.

use clap::{Args, Subcommand};

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum TagCmd {
    /// List tasks tagged with the given name.
    Tasks(TagTasksArgs),
    /// Rename a tag across all tasks.
    Rename(TagRenameArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct TagTasksArgs {
    /// One or more words for the tag name (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) tag_name: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct TagRenameArgs {
    pub(in crate::cli) old_name: String,
    pub(in crate::cli) new_name: String,
}
