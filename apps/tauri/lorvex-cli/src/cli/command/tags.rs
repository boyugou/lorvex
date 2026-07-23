//! Tag listing, per-tag task query, and rename arms.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum TagsCommand {
    List {
        format: OutputFormat,
    },
    Tasks {
        tag_name: String,
        format: OutputFormat,
    },
    Rename {
        old_name: String,
        new_name: String,
        format: OutputFormat,
    },
}
