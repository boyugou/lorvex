use super::doctor_diagnostics;
use crate::models::{DoctorReport, McpTargetStatus};

#[test]
fn app_hosted_mcp_config_is_info_not_warning() {
    let absent = McpTargetStatus {
        present: false,
        points_to_current_cli: None,
        host_kind: None,
    };
    let app_hosted = McpTargetStatus {
        present: true,
        points_to_current_cli: Some(false),
        host_kind: Some("app".to_string()),
    };
    let stale = McpTargetStatus {
        present: true,
        points_to_current_cli: Some(false),
        host_kind: Some("unknown (/bad/path)".to_string()),
    };

    // Claude Code points to app => info, not warning
    let (warnings, info) = doctor_diagnostics("wal", true, &absent, &app_hosted, &absent);
    assert!(
        warnings.is_empty(),
        "expected no warnings, got: {warnings:?}"
    );
    assert_eq!(info.len(), 1);
    assert!(info[0].contains("INFO_MCP_CLAUDE_CODE"));
    assert!(info[0].contains("valid MCP host"));

    // Claude Desktop points to unknown path => warning, not info
    let (warnings, info) = doctor_diagnostics("wal", true, &stale, &absent, &absent);
    assert_eq!(warnings.len(), 1);
    assert!(warnings[0].contains("STALE_MCP_CLAUDE_DESKTOP"));
    assert!(info.is_empty());
}

#[test]
fn cli_hosted_config_produces_no_diagnostic() {
    let cli_current = McpTargetStatus {
        present: true,
        points_to_current_cli: Some(true),
        host_kind: Some("cli".to_string()),
    };
    let absent = McpTargetStatus {
        present: false,
        points_to_current_cli: None,
        host_kind: None,
    };
    let (warnings, info) = doctor_diagnostics("wal", true, &absent, &cli_current, &absent);
    assert!(warnings.is_empty());
    assert!(info.is_empty());
}

#[test]
fn doctor_report_json_supports_runtime_fields() {
    let report = DoctorReport {
        db_path: "/tmp/lorvex.db".to_string(),
        db_source: "platform_data_dir".to_string(),
        platform_default_db_path: "/tmp/lorvex.db".to_string(),
        device_id: "device-1".to_string(),
        local_change_seq: 3,
        db_exists_before_open: true,
        journal_mode: "wal".to_string(),
        foreign_keys_enabled: true,
        mcp_host: true,
        filesystem_bridge_owner: "desktop-app".to_string(),
        claude_desktop_config_present: false,
        claude_code_config_present: true,
        codex_config_present: true,
        claude_desktop_points_to_current_cli: None,
        claude_code_points_to_current_cli: Some(true),
        codex_points_to_current_cli: Some(false),
        mcp_host_authority: Some("cli".to_string()),
        warnings: vec!["codex config does not point to the current Lorvex CLI binary".to_string()],
        info: vec![],
    };
    let rendered = serde_json::to_string_pretty(&report).expect("serialize doctor report");
    let value: serde_json::Value = serde_json::from_str(&rendered).expect("parse doctor report");
    assert_eq!(value["db_source"], "platform_data_dir");
    assert_eq!(value["journal_mode"], "wal");
    assert_eq!(value["foreign_keys_enabled"], true);
    assert_eq!(value["codex_points_to_current_cli"], false);
    assert_eq!(
        value["warnings"][0],
        "codex config does not point to the current Lorvex CLI binary"
    );
}
