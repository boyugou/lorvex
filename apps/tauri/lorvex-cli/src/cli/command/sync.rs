//! Sync status + outbox introspection arms.

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum SyncCommand {
    Status { format: OutputFormat },
    Outbox { limit: u32, format: OutputFormat },
}
