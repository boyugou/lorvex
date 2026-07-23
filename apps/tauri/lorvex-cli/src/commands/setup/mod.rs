use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::{
    capabilities_for, current_sync_owner, get_or_create_device_id, read_local_change_seq,
    resolve_db_location_details, resolve_db_path, SurfaceProfile,
};
use std::fmt::Write;

use crate::cli::{McpInstallTarget, OutputFormat};
use crate::commands::mcp::{
    claim_cli_mcp_host_authority, inspect_mcp_target_status, install_mcp_configs,
    preflight_cli_mcp_host_authority_claim,
};
use crate::commands::shared::{render_mutation_envelope, render_query_envelope};
use crate::models::{DoctorReport, McpTargetStatus};
use crate::render::yes_no;
use crate::tui::load_dashboard_snapshot;

pub(crate) fn run_setup(
    install_target: Option<McpInstallTarget>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let location = resolve_db_location_details();
    let conn = open_db_at_path(&location.resolved_path)?;
    let device_id = get_or_create_device_id(&conn)?;
    let journal_mode: String = conn.query_row("PRAGMA journal_mode", [], |row| row.get(0))?;
    let foreign_keys: i64 = conn.query_row("PRAGMA foreign_keys", [], |row| row.get(0))?;
    let should_install_mcp = install_target.is_some();
    if should_install_mcp {
        preflight_cli_mcp_host_authority_claim(&conn)?;
    }
    let install_summary = install_target
        .map(install_mcp_configs)
        .transpose()?
        .unwrap_or_default();
    if should_install_mcp {
        claim_cli_mcp_host_authority(&conn)?;
    }

    match format {
        OutputFormat::Text => {
            let mut message = format!(
                "Lorvex CLI setup complete\nDB: {}\nDB source: {}\nDevice ID: {}\nJournal mode: {}\nForeign keys: {}",
                location.resolved_path.display(),
                location.source.as_str(),
                device_id,
                journal_mode,
                yes_no(foreign_keys == 1),
            );
            if !install_summary.is_empty() {
                message.push_str("\nMCP install targets:");
                for line in install_summary.lines() {
                    message.push_str("\n  - ");
                    message.push_str(line);
                }
            }
            Ok(message)
        }
        OutputFormat::Json => {
            // first-run automation reads this payload to
            // confirm provisioning succeeded. Shape is intentionally
            // minimal — extend in future versions, don't rename fields.
            // wrap in canonical mutation envelope so
            // CLI consumers can `jq '.action'` and key off `setup.run`
            // alongside every other mutating command.
            let installed: Vec<String> = if install_summary.is_empty() {
                Vec::new()
            } else {
                install_summary
                    .lines()
                    .map(std::string::ToString::to_string)
                    .collect()
            };
            render_mutation_envelope(
                "setup.run",
                &location.resolved_path,
                serde_json::json!({
                    "db_source": location.source.as_str(),
                    "device_id": device_id,
                    "journal_mode": journal_mode,
                    "foreign_keys_enabled": foreign_keys == 1,
                    "installed": installed,
                    "errors": Vec::<String>::new(),
                }),
            )
        }
    }
}

pub(crate) fn run_doctor(format: OutputFormat) -> Result<String, crate::error::CliError> {
    let location = resolve_db_location_details();
    let db_exists_before_open = location.resolved_path.exists();
    let conn = open_db_at_path(&location.resolved_path)?;
    let device_id = get_or_create_device_id(&conn)?;
    let local_change_seq = read_local_change_seq(&conn)?;
    let journal_mode: String = conn.query_row("PRAGMA journal_mode", [], |row| row.get(0))?;
    let foreign_keys_enabled: i64 = conn.query_row("PRAGMA foreign_keys", [], |row| row.get(0))?;
    let capabilities = capabilities_for(SurfaceProfile::DesktopCliAgent);
    let filesystem_bridge_owner = current_sync_owner(&conn, "filesystem_bridge")?
        .map_or_else(|| "none".to_string(), |lease| lease.owner_id);
    let mcp_host_authority = lorvex_runtime::get_mcp_host_authority(&conn)?;
    let claude_desktop_status = inspect_mcp_target_status(McpInstallTarget::ClaudeDesktop)?;
    let claude_code_status = inspect_mcp_target_status(McpInstallTarget::ClaudeCode)?;
    let codex_status = inspect_mcp_target_status(McpInstallTarget::Codex)?;
    let (warnings, info) = doctor_diagnostics(
        &journal_mode,
        foreign_keys_enabled == 1,
        &claude_desktop_status,
        &claude_code_status,
        &codex_status,
    );

    let report = DoctorReport {
        db_path: location.resolved_path.display().to_string(),
        db_source: location.source.as_str().to_string(),
        platform_default_db_path: location.platform_default_path.display().to_string(),
        device_id,
        local_change_seq: i64::try_from(local_change_seq)
            .map_err(|e| crate::error::CliError::Internal(e.to_string()))?,
        db_exists_before_open,
        journal_mode,
        foreign_keys_enabled: foreign_keys_enabled == 1,
        mcp_host: capabilities.mcp_host,
        filesystem_bridge_owner,
        claude_desktop_config_present: claude_desktop_status.present,
        claude_code_config_present: claude_code_status.present,
        codex_config_present: codex_status.present,
        claude_desktop_points_to_current_cli: claude_desktop_status.points_to_current_cli,
        claude_code_points_to_current_cli: claude_code_status.points_to_current_cli,
        codex_points_to_current_cli: codex_status.points_to_current_cli,
        mcp_host_authority,
        warnings,
        info,
    };

    match format {
        OutputFormat::Text => {
            let mut out = String::new();
            out.push_str("Lorvex CLI Doctor\n");
            let _ = writeln!(out, "  Database:          {}", report.db_path);
            let _ = writeln!(out, "  DB source:         {}", report.db_source);
            let _ = writeln!(
                out,
                "  Platform default:  {}",
                report.platform_default_db_path
            );
            let _ = writeln!(
                out,
                "  DB existed:        {}",
                yes_no(report.db_exists_before_open)
            );
            let _ = writeln!(out, "  Journal mode:      {}", report.journal_mode);
            let _ = writeln!(
                out,
                "  Foreign keys:      {}",
                yes_no(report.foreign_keys_enabled)
            );
            let _ = writeln!(out, "  Device ID:         {}", report.device_id);
            let _ = writeln!(out, "  Local change seq:  {}", report.local_change_seq);
            out.push('\n');
            out.push_str("Capabilities\n");
            let _ = writeln!(out, "  MCP host:          {}", report.mcp_host);
            let _ = writeln!(
                out,
                "  FS bridge owner:   {}",
                report.filesystem_bridge_owner
            );
            let _ = writeln!(
                out,
                "  MCP host auth:     {}",
                report.mcp_host_authority.as_deref().unwrap_or("not set")
            );
            out.push('\n');
            out.push_str("MCP Client Configs\n");
            let _ = writeln!(
                out,
                "  Claude Desktop:    {}{}",
                yes_no(report.claude_desktop_config_present),
                format_mcp_target_detail(&claude_desktop_status)
            );
            let _ = writeln!(
                out,
                "  Claude Code:       {}{}",
                yes_no(report.claude_code_config_present),
                format_mcp_target_detail(&claude_code_status)
            );
            let _ = writeln!(
                out,
                "  Codex:             {}{}",
                yes_no(report.codex_config_present),
                format_mcp_target_detail(&codex_status)
            );
            if !report.info.is_empty() {
                let _ = writeln!(out, "\nInfo ({})", report.info.len());
                for i in &report.info {
                    let _ = writeln!(out, "  - {i}");
                }
            }
            if report.warnings.is_empty() {
                out.push_str("\nNo warnings.");
            } else {
                let _ = writeln!(out, "\nWarnings ({})", report.warnings.len());
                for w in &report.warnings {
                    let _ = writeln!(out, "  - {w}");
                }
            }
            Ok(out)
        }
        // route through render_query_envelope so
        // the doctor output matches the universal envelope shape
        // (`{action, db_path, ...}`).
        // DoctorReport JSON without `.action`, breaking the
        // consumer contract that #3033-M6 set for every other
        // CLI surface.
        OutputFormat::Json => render_query_envelope(
            "query.cli.doctor",
            &location.resolved_path,
            serde_json::to_value(&report)?,
        ),
    }
}

pub(crate) fn render_status_dashboard(
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let snapshot = load_dashboard_snapshot(&conn, &db_path)?;

    match format {
        OutputFormat::Text => {
            let next_display = match (&snapshot.next_task, &snapshot.next_task_id) {
                (Some(title), Some(id)) => {
                    let short_id = if id.len() > 8 { &id[..8] } else { id };
                    format!("{title} [{short_id}]")
                }
                (Some(title), None) => title.clone(),
                _ => "none".to_string(),
            };
            Ok(format!(
                "Lorvex Status\nDB: {}\nDevice: {}\nOpen: {}\nOverdue: {}\nNext: {}",
                snapshot.db_path.display(),
                snapshot.device_id,
                snapshot.open_tasks,
                snapshot.overdue_tasks,
                next_display,
            ))
        }
        // route through render_query_envelope so
        // the status dashboard output carries `.action` like every
        // other surface.
        OutputFormat::Json => render_query_envelope(
            "query.cli.status",
            &snapshot.db_path.clone(),
            serde_json::to_value(&snapshot)?,
        ),
    }
}

/// Returns `(warnings, info)` diagnostic vectors.
pub(crate) fn doctor_diagnostics(
    journal_mode: &str,
    foreign_keys_enabled: bool,
    claude_desktop_status: &McpTargetStatus,
    claude_code_status: &McpTargetStatus,
    codex_status: &McpTargetStatus,
) -> (Vec<String>, Vec<String>) {
    let mut warnings = Vec::new();
    let mut info = Vec::new();
    if !journal_mode.eq_ignore_ascii_case("wal") {
        warnings.push(format!(
            "[WAL_MODE] journal_mode is '{journal_mode}', expected 'wal'. \
             Fix: reopen the database or run PRAGMA journal_mode=WAL."
        ));
    }
    if !foreign_keys_enabled {
        warnings.push(
            "[FK_DISABLED] foreign_keys is disabled. \
             Fix: this should be set automatically on connection open; \
             check for PRAGMA overrides."
                .to_string(),
        );
    }
    if !(claude_desktop_status.present || claude_code_status.present || codex_status.present) {
        warnings.push(
            "[NO_MCP_CONFIG] No MCP client config detected. \
             Fix: run 'lorvex mcp install --for <client>' or \
             'lorvex setup --install-mcp-for <client>'."
                .to_string(),
        );
    }
    append_mcp_diagnostic(
        &mut warnings,
        &mut info,
        "Claude Desktop",
        "claude-desktop",
        claude_desktop_status,
    );
    append_mcp_diagnostic(
        &mut warnings,
        &mut info,
        "Claude Code",
        "claude-code",
        claude_code_status,
    );
    append_mcp_diagnostic(&mut warnings, &mut info, "Codex", "codex", codex_status);
    (warnings, info)
}

fn append_mcp_diagnostic(
    warnings: &mut Vec<String>,
    info: &mut Vec<String>,
    label: &str,
    install_target: &str,
    status: &McpTargetStatus,
) {
    if status.present && matches!(status.points_to_current_cli, Some(false)) {
        let tag = install_target.to_uppercase().replace('-', "_");
        if status.host_kind.as_deref() == Some("app") {
            // Config points to the Lorvex desktop app — a valid MCP host, not stale.
            info.push(format!(
                "[INFO_MCP_{tag}] {label} config points to the Lorvex desktop app (valid MCP host).",
            ));
        } else {
            warnings.push(format!(
                "[STALE_MCP_{tag}] {label} config does not point to the current Lorvex CLI binary. \
                 Fix: run 'lorvex mcp install --for {install_target}'.",
            ));
        }
    }
}

fn format_mcp_target_detail(status: &McpTargetStatus) -> String {
    let mut parts = Vec::new();
    if let Some(true) = status.points_to_current_cli {
        parts.push("current cli: yes".to_string());
    } else if let Some(false) = status.points_to_current_cli {
        parts.push("current cli: no".to_string());
    }
    if let Some(ref kind) = status.host_kind {
        parts.push(format!("host: {kind}"));
    }
    if parts.is_empty() {
        String::new()
    } else {
        format!(" ({})", parts.join(", "))
    }
}

#[cfg(test)]
mod tests;
