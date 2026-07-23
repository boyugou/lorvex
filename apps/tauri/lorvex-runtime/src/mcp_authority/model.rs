pub(super) const MCP_HOST_CLI: &str = "cli";
pub(super) const MCP_HOST_APP: &str = "app";
pub(super) const MCP_HOST_KIND_PRIORITIES: &[(&str, u8)] = &[(MCP_HOST_CLI, 2), (MCP_HOST_APP, 1)];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum McpHostAuthorityKind {
    App,
    Cli,
}

impl McpHostAuthorityKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::App => MCP_HOST_APP,
            Self::Cli => MCP_HOST_CLI,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct McpHostAuthorityRecord {
    pub(super) host: String,
    pub(super) host_path: Option<String>,
    pub(super) updated_at: i64,
}

/// Which binary is currently configured as the MCP host.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum McpHostKind {
    /// The App's embedded MCP helper binary.
    App,
    /// The standalone CLI binary (`lorvex mcp serve`).
    Cli,
    /// Unknown or unrecognized binary.
    Unknown(String),
}

#[cfg(test)]
pub(super) fn mcp_host_priority(kind: &McpHostKind) -> u8 {
    // Route through `priority_for_kind_str` (which reads
    // `MCP_HOST_KIND_PRIORITIES`) so the priority numbers stay in
    // lockstep with the SQL-bind path. Pre-fix this function
    // hard-coded `Cli => 2, App => 1, Unknown => 0` in parallel with
    // the slice — adding a new kind to the table would have left a
    // typed-enum tier silently disagreeing with the string-bind
    // tier. `Unknown` deliberately falls
    // through to the slice's "not present" case, which yields 0.
    match kind {
        McpHostKind::Cli => priority_for_kind_str(MCP_HOST_CLI),
        McpHostKind::App => priority_for_kind_str(MCP_HOST_APP),
        McpHostKind::Unknown(name) => priority_for_kind_str(name),
    }
}

/// Same as [`mcp_host_priority`] but takes the canonical kind string
/// (`"app"` or `"cli"`) for the SQL bind path. Returns `0` for unknown
/// strings so a typo never accidentally outranks a known kind.
/// reads from [`MCP_HOST_KIND_PRIORITIES`] so any new
/// kind added to the table is automatically picked up here without a
/// parallel `match`-arm edit.
pub(super) fn priority_for_kind_str(kind: &str) -> u8 {
    MCP_HOST_KIND_PRIORITIES
        .iter()
        .find(|(k, _)| *k == kind)
        .map_or(0, |(_, p)| *p)
}

/// Outcome of [`claim_mcp_host_authority`]. The
/// previous `Result<bool, _>` shape conflated three semantically
/// distinct cases: (a) we wrote a fresher row, (b) a peer wrote a
/// fresher row first, (c) the row already held the desired value so
/// the CAS predicate didn't update. Callers that retry on `false`
/// would re-attempt forever in case (c) without making progress, and
/// callers that escalate on `false` would noisily report a "lost
/// race" when the system is in fact already in the desired state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum McpHostWriteOutcome {
    /// We wrote our value (or our value beat the prior row in the
    /// CAS guard). Caller is now authoritative.
    Stored,
    /// A peer wrote a fresher / higher-priority value first. Caller
    /// should re-read and decide whether to retry.
    LostRace,
    /// The row already held the desired host, so no write was needed.
    /// Distinct from `LostRace` because the system IS in the desired
    /// state — retrying would not make progress, and escalating an
    /// alarm here would be a false positive.
    AlreadyCorrect,
}
