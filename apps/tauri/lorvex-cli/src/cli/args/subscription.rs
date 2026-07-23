//! Calendar subscription argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::parse_hex_color;

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum SubscriptionCmd {
    /// List every calendar subscription with sync health, last fetch,
    /// and backoff state.
    List(SubscriptionListArgs),
    /// Add a new ICS calendar subscription.
    Add(SubscriptionAddArgs),
    /// Remove a subscription by id.
    Remove(SubscriptionIdArgs),
    /// Manually refresh a single subscription or every enabled feed.
    Refresh(SubscriptionRefreshArgs),
    /// Toggle a subscription between enabled and disabled.
    Toggle(SubscriptionIdArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct SubscriptionListArgs {
    /// Show every column (last_fetched_at, next_retry_at, error
    /// message, color, consecutive-failure count). Default output
    /// truncates to feed_url / name / status / refreshed_ago for
    /// scannability (#4492 item 5).
    #[arg(long = "verbose", short = 'v')]
    pub(in crate::cli) verbose: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct SubscriptionAddArgs {
    /// Feed URL (must be `https://` and pass SSRF / private-IP
    /// validation).
    pub(in crate::cli) url: String,
    /// Optional display name; defaults to the host portion of the URL.
    #[arg(long = "name")]
    pub(in crate::cli) name: Option<String>,
    /// Optional `#rrggbb` color hex, mirroring the Tauri Settings →
    /// Subscriptions surface.
    #[arg(long = "color", value_parser = parse_hex_color)]
    pub(in crate::cli) color: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct SubscriptionIdArgs {
    /// Subscription id.
    pub(in crate::cli) id: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct SubscriptionRefreshArgs {
    /// Subscription id to refresh. Omit when passing `--all`.
    pub(in crate::cli) id: Option<String>,
    /// Refresh every enabled subscription whose backoff gate has
    /// elapsed (equivalent to the Tauri 60-min poll cycle).
    #[arg(long = "all", conflicts_with = "id")]
    pub(in crate::cli) all: bool,
}
