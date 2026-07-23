//! System / setup / mcp / tui / completions / data IO arms.

use clap_complete::Shell;

use super::{McpInstallTarget, OutputFormat};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum SystemCommand {
    Setup {
        install_target: Option<McpInstallTarget>,
    },
    Doctor {
        format: OutputFormat,
    },
    Status {
        format: OutputFormat,
    },
    Changelog {
        limit: u32,
        entity_type: Option<String>,
        operation: Option<String>,
        entity_id: Option<String>,
        since: Option<String>,
        format: OutputFormat,
    },
    /// recent error_logs rows (subset of MCP `get_recent_logs`).
    ErrorLogs {
        source: Option<String>,
        limit: u32,
        format: OutputFormat,
    },
    /// assistant onboarding readiness query (MCP `get_setup_status`).
    SetupStatus {
        format: OutputFormat,
    },
    /// mark assistant onboarding completed (MCP `complete_setup`).
    SetupComplete {
        summary: String,
        format: OutputFormat,
    },
    Export {
        output_path: String,
        format: OutputFormat,
    },
    Import {
        input_path: String,
        format: OutputFormat,
    },
    // Terminal UI
    Tui,
    TuiWatch,
    McpInstall {
        target: McpInstallTarget,
    },
    McpServe,
    /// emit shell completion script to stdout. The
    /// dispatcher in `main.rs` renders the script via
    /// `clap_complete::generate` and exits without touching the DB.
    Completions {
        shell: Shell,
    },
}
