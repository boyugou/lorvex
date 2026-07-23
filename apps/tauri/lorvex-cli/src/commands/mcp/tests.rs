use super::*;

#[test]
fn merge_json_config_sets_lorvex_server() {
    let rendered = merge_json_mcp_config("{}", McpInstallTarget::ClaudeCode).expect("merge json");
    let json: serde_json::Value = serde_json::from_str(&rendered).expect("parse merged json");
    assert_eq!(json["mcpServers"]["lorvex"]["type"], "stdio");
    assert_eq!(json["mcpServers"]["lorvex"]["args"][0], "mcp");
}

#[test]
fn merge_codex_config_replaces_existing_lorvex_section() {
    let rendered = merge_codex_toml_config(
        "[mcp_servers.lorvex]\ncommand = \"old\"\nargs = [\"old\"]\n\n[foo]\nbar = 1\n",
    )
    .expect("merge codex config");
    assert!(rendered.contains("[mcp_servers.lorvex]"));
    assert!(rendered.contains("[foo]"));
    assert!(!rendered.contains("command = \"old\""));
}

#[test]
fn concrete_mcp_install_targets_expands_all() {
    let targets = concrete_mcp_install_targets(McpInstallTarget::All);
    assert_eq!(
        targets,
        vec![
            McpInstallTarget::ClaudeDesktop,
            McpInstallTarget::ClaudeCode,
            McpInstallTarget::Codex,
        ]
    );
}

#[test]
fn preflight_cli_mcp_authority_claim_rolls_back_probe_write() {
    let conn = rusqlite::Connection::open_in_memory().expect("open in-memory db");
    lorvex_runtime::local_state::initialize_local_runtime_tables(&conn).expect("init");

    preflight_cli_mcp_host_authority_claim(&conn).expect("preflight");
    assert!(
        lorvex_runtime::get_mcp_host_authority(&conn)
            .expect("read authority")
            .is_none(),
        "preflight must verify writeability without persisting authority"
    );

    claim_cli_mcp_host_authority(&conn).expect("claim");
    assert_eq!(
        lorvex_runtime::get_mcp_host_authority(&conn)
            .expect("read authority")
            .as_deref(),
        Some("cli")
    );
}

#[test]
fn merge_json_config_rejects_invalid_json() {
    let err = merge_json_mcp_config("not json", McpInstallTarget::ClaudeCode)
        .expect_err("should reject invalid JSON");
    assert!(
        err.to_string().contains("invalid JSON"),
        "error should mention 'invalid JSON': {err}"
    );
}

#[test]
fn merge_json_config_rejects_non_object_root() {
    let err = merge_json_mcp_config("[1,2,3]", McpInstallTarget::ClaudeCode)
        .expect_err("should reject array root");
    assert!(
        err.to_string().contains("array"),
        "error should mention 'array': {err}"
    );
}

#[test]
fn merge_json_config_handles_whitespace_only() {
    let rendered =
        merge_json_mcp_config("   ", McpInstallTarget::ClaudeCode).expect("whitespace-only");
    let json: serde_json::Value = serde_json::from_str(&rendered).expect("parse");
    assert_eq!(json["mcpServers"]["lorvex"]["type"], "stdio");
}

#[test]
fn merge_json_config_preserves_existing_servers() {
    let existing = r#"{"mcpServers":{"other":{"type":"stdio","command":"other"}}}"#;
    let rendered = merge_json_mcp_config(existing, McpInstallTarget::ClaudeCode).expect("merge");
    let json: serde_json::Value = serde_json::from_str(&rendered).expect("parse");
    assert_eq!(json["mcpServers"]["other"]["command"], "other");
    assert_eq!(json["mcpServers"]["lorvex"]["type"], "stdio");
}

#[test]
fn extract_codex_mcp_command_reads_lorvex_section() {
    let command = extract_codex_mcp_command(
        "[mcp_servers.lorvex]\ncommand = \"/tmp/lorvex\"\nargs = [\"mcp\", \"serve\"]\n",
    );
    assert_eq!(command.as_deref(), Some("/tmp/lorvex"));
}

/// a path containing escaped quotes is a legal TOML
/// basic string. The previous hand-rolled line parser truncated at
/// the first inner quote — the `toml` crate parses correctly.
#[test]
fn extract_codex_mcp_command_handles_embedded_escaped_quotes() {
    let command = extract_codex_mcp_command(
        "[mcp_servers.lorvex]\n\
         command = \"/Applications/My \\\"Cool\\\" App/lorvex\"\n",
    );
    assert_eq!(
        command.as_deref(),
        Some("/Applications/My \"Cool\" App/lorvex"),
    );
}

/// TOML literal strings (single-quoted) are also a
/// legal value form for paths that contain backslashes (e.g.
/// Windows-native paths). Hand-rolled parser left the single quotes
/// in the result; `toml` strips them.
#[test]
fn extract_codex_mcp_command_handles_literal_strings() {
    let command = extract_codex_mcp_command(
        "[mcp_servers.lorvex]\n\
         command = '/usr/local/bin/lorvex'\n",
    );
    assert_eq!(command.as_deref(), Some("/usr/local/bin/lorvex"));
}

/// a malformed config returns `None` rather than
/// silently extracting the dangling head of an unclosed string.
#[test]
fn extract_codex_mcp_command_returns_none_on_malformed_config() {
    let command = extract_codex_mcp_command("[mcp_servers.lorvex\ncommand = \"/tmp/lorvex\n");
    assert!(command.is_none());
}

/// missing section produces `None` (not a partial
/// match against unrelated `command = …` lines elsewhere in the
/// document).
#[test]
fn extract_codex_mcp_command_returns_none_when_section_absent() {
    let command = extract_codex_mcp_command("[mcp_servers.other]\ncommand = \"/tmp/other\"\n");
    assert!(command.is_none());
}
