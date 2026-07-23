//! MCP host authority detection.
//!
//! Determines which installed surface (App or CLI) should serve as the
//! canonical external MCP endpoint for agents like Claude Code and Codex.
//!
//! Rule: exactly one Lorvex MCP endpoint should be registered at any time.
//! When both App and CLI are installed, CLI is the recommended host.

mod classify;
mod detect;
mod model;
mod store;
#[cfg(test)]
mod tests;

pub use classify::classify_mcp_host;
pub use detect::{detect_cli_installation, path_is_executable_binary};
pub use model::{McpHostAuthorityKind, McpHostKind, McpHostWriteOutcome};
pub use store::{
    claim_mcp_host_authority, get_mcp_host_authority,
    reclaim_app_mcp_host_authority_when_cli_missing,
};

#[cfg(test)]
use model::mcp_host_priority;
#[cfg(test)]
use store::{read_mcp_host_authority_record, reclaim_app_mcp_host_authority_from_cli_record};
