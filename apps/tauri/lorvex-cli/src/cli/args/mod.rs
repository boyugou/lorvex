//! Clap-derive parse tree. Per-domain argument structs live in sibling
//! modules; this file contains the root [`ClapCli`] plus glob re-exports
//! that flatten the per-domain submodules and the shared widget /
//! [`ClapCommand`] siblings into a single `super::*` namespace for
//! callers in the parent `cli` module.
//!
//! `control_app_ui` and `get_ui_view_state` are
//! intentionally NOT exposed as CLI subcommands. Both tools IPC into a
//! running Tauri app over the desktop process's invoke handler, which
//! does not exist when the CLI is invoked stand-alone (a one-shot
//! lorvex CLI run owns its own process and database connection only).
//! Surfacing them as best-effort no-ops would silently lie to scripted
//! callers who expect "the CLI tool with the same name as the MCP tool
//! does the same thing"; instead we leave the gap explicit so an agent
//! that genuinely needs these tools dispatches them through the MCP
//! server (which routes them through the live app over its IPC channel).
//! Tracked under #2976 so a future refactor that wires a CLI-to-app
//! bridge can revisit.

use clap::Parser;

pub(super) mod calendar;
pub(super) mod checklist;
pub(super) mod focus;
pub(super) mod habit;
pub(super) mod list;
pub(super) mod memory;
pub(super) mod preference;
pub(super) mod reminder;
pub(super) mod review;
pub(super) mod shared;
pub(super) mod subscription;
pub(super) mod sync;
pub(super) mod tag;
pub(super) mod task;
pub(super) mod trash;
pub(super) mod tree;
pub(super) mod workflow;

pub(super) use calendar::*;
pub(super) use checklist::*;
pub(super) use focus::*;
pub(super) use habit::*;
pub(super) use list::*;
pub(super) use memory::*;
pub(super) use preference::*;
pub(super) use reminder::*;
pub(super) use review::*;
pub(super) use shared::*;
pub(super) use subscription::*;
pub(super) use sync::*;
pub(super) use tag::*;
pub(super) use task::*;
pub(super) use trash::*;
pub(super) use tree::*;
pub(super) use workflow::*;

// ---------------------------------------------------------------------------
// clap derive tree
// ---------------------------------------------------------------------------

/// Root of the clap parse tree.
#[derive(Parser, Debug)]
#[command(
    name = "lorvex",
    bin_name = "lorvex",
    version,
    about = "Lorvex CLI — agent-first planning companion",
    long_about = "Lorvex CLI — agent-first planning companion.\n\n\
Pass the global --format json flag before the subcommand for machine-readable output.\n\
Run `lorvex <subcommand> --help` for per-command options and examples.",
    after_help = "EXAMPLES:\n  \
        lorvex today\n  \
        lorvex --format json today\n  \
        lorvex capture \"Write tests\" --list work\n  \
        lorvex focus set task-1 task-2 --briefing \"Deep work\" --date 2026-05-01\n  \
        lorvex defer task-1 -d 3 --reason \"Heads down\"\n  \
        lorvex mcp serve\n\n\
Global options (parsed before the subcommand):\n  \
        --db-path <PATH>         Override DB location (takes precedence over DB_PATH).\n  \
        --format <FMT>           Default output format: text (default), json.\n  \
        -v / --verbose           Increase log verbosity. Repeat for more:\n  \
                                   -v = info, -vv = debug, -vvv = trace.\n  \
        -q / --quiet             Suppress all non-error output.\n  \
                                 RUST_LOG=<level> overrides -v / -q when set.\n\n\
Exit codes (issue #2328):\n  \
        0  Query or mutation succeeded. Zero-row query results still exit 0\n  \
           — Lorvex does NOT follow grep's \"no match → exit 1\" convention\n  \
           because task-listing scripts expect empty lists to be non-fatal.\n  \
        1  Runtime error (DB locked, parse failure, IO error, etc.).\n  \
        2  Argument / usage error (clap-rejected input).",
    disable_help_subcommand = true
)]
pub(crate) struct ClapCli {
    #[command(subcommand)]
    pub(super) command: ClapCommand,
}

impl ClapCli {
    /// Build the clap `Command` tree for callers that need the raw
    /// definition (e.g. `clap_complete::generate` in `main.rs` for the
    /// `completions` subcommand, issue #2307). This wraps
    /// `<Self as CommandFactory>::command()` so `main.rs` does not need
    /// to import `CommandFactory` directly.
    pub(crate) fn command() -> clap::Command {
        <Self as clap::CommandFactory>::command()
    }
}
