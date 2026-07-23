//! Pre-clap argv rewrites for subcommand groups that accept a bare
//! "show"-like default.
//!
//! Clap can't express "bare list id is an alias for `list show <id>`"
//! with a plain `#[command(subcommand)]`, so we splice in the implicit
//! `show` verb before the parser sees the argv.

/// Pre-clap argv rewrites for subcommand groups that accept a bare
/// "show"-like default:
///
/// - `lorvex list <list-id> [...]` → `lorvex list show <list-id> [...]`
///   (bare list id is an alias for `list show`; clap can't express
///   this with a plain `#[command(subcommand)]`).
/// - `lorvex focus` / `lorvex focus` → `lorvex focus show [...]`
///   (bare `focus` prints today's focus).
pub(super) fn rewrite_default_subcommands(mut args: Vec<String>) -> Vec<String> {
    // Skip rewrites entirely when the user is asking for help on the
    // subcommand group itself (`lorvex focus --help`, `lorvex list
    // -h`). Otherwise we'd rewrite to `focus show --help` and show
    // per-variant help instead of the group help listing all verbs.
    let wants_group_help = args.iter().any(|a| a == "--help" || a == "-h");

    // `list <id>` → `list show <id>` (bare list-id alias).
    const LIST_EXPLICIT: &[&str] = &["show", "health", "create", "update", "delete"];
    if !wants_group_help && args.len() >= 2 && args[0] == "list" {
        let second = args[1].as_str();
        if !LIST_EXPLICIT.contains(&second) && !second.starts_with('-') {
            args.insert(1, "show".to_string());
        }
    }
    // Bare `focus` (no subcommand, or only group-level flags) → `focus show`.
    if !wants_group_help && !args.is_empty() && args[0] == "focus" {
        const FOCUS_EXPLICIT: &[&str] = &["show", "set", "add", "remove", "clear"];
        let needs_show = args
            .get(1)
            .is_none_or(|next| !FOCUS_EXPLICIT.contains(&next.as_str()) && next.starts_with('-'));
        if needs_show {
            args.insert(1, "show".to_string());
        }
    }
    args
}
