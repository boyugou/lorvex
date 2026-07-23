//! User-preference key/value arms.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum PreferencesCommand {
    List {
        format: OutputFormat,
    },
    Get {
        key: String,
        format: OutputFormat,
    },
    Set {
        key: String,
        value_json: String,
        format: OutputFormat,
    },
    Delete {
        key: String,
        format: OutputFormat,
    },
}
