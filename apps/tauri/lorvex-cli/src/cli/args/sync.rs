//! Sync diagnostics + assistant changelog argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::parse_positive_u32;
#[derive(Subcommand, Debug)]
pub(in crate::cli) enum SyncCmd {
    /// Show sync queue, checkpoint, and backend health counters.
    Status,
    /// List unsynced sync_outbox entries in FIFO order.
    Outbox(SyncOutboxArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct SyncOutboxArgs {
    #[arg(short = 'l', long = "limit", default_value_t = 100, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ChangelogArgs {
    #[arg(short = 'l', long = "limit", default_value_t = 50, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
    #[arg(long = "entity-type")]
    pub(in crate::cli) entity_type: Option<String>,
    #[arg(long = "operation")]
    pub(in crate::cli) operation: Option<String>,
    #[arg(long = "entity-id")]
    pub(in crate::cli) entity_id: Option<String>,
    #[arg(long = "since")]
    pub(in crate::cli) since: Option<String>,
}
