//! Long-term memory key/value arms (list/show/write/delete + history).

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum MemoryCommand {
    List {
        format: OutputFormat,
    },
    Show {
        key: String,
        format: OutputFormat,
    },
    Write {
        key: String,
        content: String,
        format: OutputFormat,
    },
    Delete {
        key: String,
        format: OutputFormat,
    },
    History {
        key: String,
        limit: u32,
        format: OutputFormat,
    },
    Restore {
        revision_id: String,
        format: OutputFormat,
    },
}
