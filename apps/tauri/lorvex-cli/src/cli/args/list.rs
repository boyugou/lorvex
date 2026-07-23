//! List CRUD argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::{parse_hex_color, parse_list_id, parse_positive_u32};

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum ListCmd {
    /// Show tasks in a list (default when given a bare list id).
    Show(ListShowArgs),
    /// Show per-list open/overdue/due-today health counts.
    Health(ListHealthArgs),
    /// Create a new list.
    Create(ListCreateArgs),
    /// Update list metadata.
    Update(ListUpdateArgs),
    /// Delete a list.
    Delete(ListDeleteArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ListShowArgs {
    #[arg(value_parser = parse_list_id)]
    pub(in crate::cli) list_id: String,
    #[arg(short = 'l', long = "limit", default_value_t = 50, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ListHealthArgs {
    #[arg(short = 'l', long = "limit", default_value_t = 50, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ListCreateArgs {
    /// One or more words for the list name (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) name: Vec<String>,
    #[arg(long = "color", value_parser = parse_hex_color)]
    pub(in crate::cli) color: Option<String>,
    #[arg(long = "icon")]
    pub(in crate::cli) icon: Option<String>,
    #[arg(long = "description")]
    pub(in crate::cli) description: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ListUpdateArgs {
    #[arg(value_parser = parse_list_id)]
    pub(in crate::cli) list_id: String,
    #[arg(short = 'n', long = "name")]
    pub(in crate::cli) name: Option<String>,
    // Bring CLI parity with the MCP `update_list` contract. The MCP
    // shape supports `Patch<T>` (Set vs Clear vs Unset) for
    // color / icon / description / ai_notes; the CLI surface mirrors
    // that with explicit `--clear-*` flags alongside the value flags.
    // `conflicts_with` rejects "set and clear at the same time" at
    // the clap layer.
    #[arg(long = "color", value_parser = parse_hex_color, conflicts_with = "clear_color")]
    pub(in crate::cli) color: Option<String>,
    #[arg(long = "clear-color")]
    pub(in crate::cli) clear_color: bool,
    #[arg(long = "icon", conflicts_with = "clear_icon")]
    pub(in crate::cli) icon: Option<String>,
    #[arg(long = "clear-icon")]
    pub(in crate::cli) clear_icon: bool,
    #[arg(long = "description", conflicts_with = "clear_description")]
    pub(in crate::cli) description: Option<String>,
    #[arg(long = "clear-description")]
    pub(in crate::cli) clear_description: bool,
    #[arg(long = "ai-notes", conflicts_with = "clear_ai_notes")]
    pub(in crate::cli) ai_notes: Option<String>,
    #[arg(long = "clear-ai-notes")]
    pub(in crate::cli) clear_ai_notes: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ListDeleteArgs {
    #[arg(value_parser = parse_list_id)]
    pub(in crate::cli) list_id: String,
}
