use crate::cli::McpInstallTarget;
use crate::models::McpTargetStatus;
use lorvex_runtime::mcp_authority::{classify_mcp_host, McpHostAuthorityKind, McpHostKind};
use std::fmt::Write;

fn install_mcp_config(target: McpInstallTarget) -> Result<String, crate::error::CliError> {
    if target == McpInstallTarget::All {
        return Err(crate::error::CliError::Validation(
            "target 'all' must be expanded before installing MCP config".to_string(),
        ));
    }
    let config_path = config_path_for_target(target)?;
    if let Some(parent) = config_path.parent() {
        std::fs::create_dir_all(parent)?;
    }

    match target {
        McpInstallTarget::ClaudeDesktop | McpInstallTarget::ClaudeCode => {
            let existing = match std::fs::read_to_string(&config_path) {
                Ok(content) => content,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => "{}".to_string(),
                Err(e) => return Err(e.into()), // Don't silently overwrite on permission/IO errors
            };
            let merged = merge_json_mcp_config(&existing, target)?;
            std::fs::write(&config_path, merged)?;
        }
        McpInstallTarget::Codex => {
            let existing = match std::fs::read_to_string(&config_path) {
                Ok(content) => content,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => String::new(),
                Err(e) => return Err(e.into()),
            };
            let merged = merge_codex_toml_config(&existing)?;
            std::fs::write(&config_path, &merged)?;
        }
        McpInstallTarget::All => {
            return Err(crate::error::CliError::Validation(
                "target 'all' must be expanded before installing MCP config".to_string(),
            ));
        }
    }

    Ok(format!(
        "Installed Lorvex MCP config for {} at {}",
        mcp_target_name(target),
        config_path.display()
    ))
}

pub(crate) fn install_mcp_configs(
    target: McpInstallTarget,
) -> Result<String, crate::error::CliError> {
    let targets = concrete_mcp_install_targets(target);
    let mut successes = Vec::new();
    let mut errors = Vec::new();
    for concrete_target in targets {
        match install_mcp_config(concrete_target) {
            Ok(msg) => successes.push(msg),
            Err(e) => errors.push(format!("{}: {e}", mcp_target_name(concrete_target))),
        }
    }
    if !errors.is_empty() {
        let mut msg = format!("Failed: {}", errors.join("; "));
        if !successes.is_empty() {
            let _ = write!(msg, "\nSucceeded: {}", successes.join("\n"));
        }
        return Err(crate::error::CliError::Internal(msg));
    }
    Ok(successes.join("\n"))
}

pub(crate) fn claim_cli_mcp_host_authority(
    conn: &rusqlite::Connection,
) -> Result<(), crate::error::CliError> {
    // Claim the host-authority slot; the success value is the typed
    // outcome (`Granted` / `AlreadyOwn` / `Reclaimed`), all of which
    // mean "the claim succeeded" — only the `Err` branch matters here.
    lorvex_runtime::claim_mcp_host_authority(conn, McpHostAuthorityKind::Cli)?;
    Ok(())
}

pub(crate) fn preflight_cli_mcp_host_authority_claim(
    conn: &rusqlite::Connection,
) -> Result<(), crate::error::CliError> {
    // Preflight only: we want to know whether the claim would
    // succeed WITHOUT persisting any state. Wrap the claim in a
    // savepoint that we always roll back. Routes through
    // `lorvex_store::transaction::with_savepoint` so a panic inside
    // `claim_cli_mcp_host_authority` rolls the savepoint back BEFORE
    // the unwind resumes — the previous hand-rolled
    // `SAVEPOINT … ; ROLLBACK TO ; RELEASE` shape would have left
    // the savepoint dangling on the connection on panic, and the
    // next write would have failed with "no such savepoint" even
    // after the outer mutex recovered from poison.
    //
    // The closure ALWAYS returns `Err` so the helper rolls back the
    // savepoint regardless of the inner outcome; the discriminator
    // tells us whether the caller wanted Ok or to surface a real
    // claim failure.
    // `ClaimFailed` boxes its `CliError` payload because the inner enum
    // is itself boxed-up to fit the 128-byte `clippy::result_large_err`
    // threshold; including it inline here would re-inflate every
    // `Result<(), Preflight>` returned by the savepoint helper.
    enum Preflight {
        WouldSucceed,
        ClaimFailed(Box<crate::error::CliError>),
    }
    impl std::fmt::Display for Preflight {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            match self {
                Self::WouldSucceed => write!(f, "preflight would-succeed sentinel"),
                Self::ClaimFailed(error) => write!(f, "preflight claim failed: {error}"),
            }
        }
    }
    impl From<rusqlite::Error> for Preflight {
        fn from(error: rusqlite::Error) -> Self {
            Self::ClaimFailed(Box::new(error.into()))
        }
    }
    impl From<String> for Preflight {
        fn from(message: String) -> Self {
            Self::ClaimFailed(Box::new(crate::error::CliError::Internal(message)))
        }
    }

    let outcome = lorvex_store::transaction::with_savepoint::<(), Preflight>(
        conn,
        "cli_mcp_authority_claim_preflight",
        |conn| match claim_cli_mcp_host_authority(conn) {
            Ok(()) => Err(Preflight::WouldSucceed),
            Err(error) => Err(Preflight::ClaimFailed(Box::new(error))),
        },
    );
    match outcome {
        Err(Preflight::WouldSucceed) => Ok(()),
        Err(Preflight::ClaimFailed(error)) => Err(*error),
        Ok(()) => unreachable!("preflight closure always returns Err sentinel"),
    }
}

pub(crate) fn inspect_mcp_target_status(
    target: McpInstallTarget,
) -> Result<McpTargetStatus, crate::error::CliError> {
    let path = config_path_for_target(target)?;
    if !path.exists() {
        return Ok(McpTargetStatus {
            present: false,
            points_to_current_cli: None,
            host_kind: None,
        });
    }

    let existing = std::fs::read_to_string(&path)?;
    let current_exe = std::env::current_exe()?.display().to_string();
    let configured_command = match target {
        McpInstallTarget::ClaudeDesktop | McpInstallTarget::ClaudeCode => {
            extract_json_mcp_command(&existing)?
        }
        McpInstallTarget::Codex => extract_codex_mcp_command(&existing),
        McpInstallTarget::All => None,
    };

    let host_kind = configured_command
        .as_deref()
        .map(|cmd| match classify_mcp_host(cmd) {
            McpHostKind::App => "app".to_string(),
            McpHostKind::Cli => "cli".to_string(),
            McpHostKind::Unknown(path) => format!("unknown ({path})"),
        });

    // Verify both command path AND args match the current CLI's MCP serve invocation
    let points_to_current_cli = configured_command.map(|command| {
        if command != current_exe {
            return false;
        }
        // Also verify args are ["mcp", "serve"] for JSON configs
        let configured_args = match target {
            McpInstallTarget::ClaudeDesktop | McpInstallTarget::ClaudeCode => {
                extract_json_mcp_args(&existing).ok().flatten()
            }
            _ => None, // Codex TOML uses a different args format; command-only check is sufficient
        };
        // If we can't extract args, command match is sufficient
        configured_args.is_none_or(|args| args == vec!["mcp", "serve"])
    });

    Ok(McpTargetStatus {
        present: true,
        points_to_current_cli,
        host_kind,
    })
}

pub(crate) fn concrete_mcp_install_targets(target: McpInstallTarget) -> Vec<McpInstallTarget> {
    match target {
        McpInstallTarget::All => vec![
            McpInstallTarget::ClaudeDesktop,
            McpInstallTarget::ClaudeCode,
            McpInstallTarget::Codex,
        ],
        target => vec![target],
    }
}

fn config_path_for_target(
    target: McpInstallTarget,
) -> Result<std::path::PathBuf, crate::error::CliError> {
    let home = dirs::home_dir()
        .ok_or_else(|| std::io::Error::other("unable to resolve home directory"))?;
    let path = match target {
        McpInstallTarget::ClaudeDesktop => {
            #[cfg(target_os = "macos")]
            {
                home.join("Library")
                    .join("Application Support")
                    .join("Claude")
                    .join("claude_desktop_config.json")
            }
            #[cfg(target_os = "windows")]
            {
                dirs::config_dir()
                    .unwrap_or_else(|| home.clone())
                    .join("Claude")
                    .join("claude_desktop_config.json")
            }
            #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
            {
                home.join(".config")
                    .join("Claude")
                    .join("claude_desktop_config.json")
            }
        }
        McpInstallTarget::ClaudeCode => home.join(".claude.json"),
        McpInstallTarget::Codex => home.join(".codex").join("config.toml"),
        McpInstallTarget::All => {
            return Err(crate::error::CliError::Validation(
                "cannot resolve a single config path for target 'all'".to_string(),
            ));
        }
    };
    Ok(path)
}

fn lorvex_mcp_command_and_args() -> Result<(String, Vec<String>), crate::error::CliError> {
    let command = std::env::current_exe()?;
    Ok((
        command.display().to_string(),
        vec!["mcp".to_string(), "serve".to_string()],
    ))
}

pub(crate) fn merge_json_mcp_config(
    existing: &str,
    target: McpInstallTarget,
) -> Result<String, crate::error::CliError> {
    let trimmed = existing.trim();
    let mut root: serde_json::Value = if trimmed.is_empty() || trimmed == "{}" {
        serde_json::json!({})
    } else {
        let parsed: serde_json::Value = serde_json::from_str(trimmed)
            .map_err(|e| crate::error::CliError::Validation(format!("existing config file has invalid JSON: {e}. Fix or back up the file before installing.")))?;
        if !parsed.is_object() {
            return Err(crate::error::CliError::Validation(format!(
                "Existing config file root is {}, expected an object. Fix or back up the file before installing.",
                if parsed.is_array() { "an array" } else { "not an object" }
            )));
        }
        parsed
    };
    let (command, args) = lorvex_mcp_command_and_args()?;
    let server_entry = match target {
        McpInstallTarget::ClaudeCode => serde_json::json!({
            "type": "stdio",
            "command": command,
            "args": args,
        }),
        _ => serde_json::json!({
            "command": command,
            "args": args,
        }),
    };

    let mcp_servers = root
        .as_object_mut()
        .ok_or_else(|| crate::error::CliError::Validation(
            "Config root is not a JSON object after parsing. Fix or back up the file before installing.".to_string(),
        ))?
        .entry("mcpServers".to_string())
        .or_insert_with(|| serde_json::json!({}));
    if !mcp_servers.is_object() {
        return Err(crate::error::CliError::Validation("existing config has a non-object 'mcpServers' field. Fix or back up the file before installing.".to_string()));
    }
    mcp_servers
        .as_object_mut()
        .ok_or_else(|| crate::error::CliError::Internal(
            "mcpServers field is not a JSON object after validation. Fix or back up the file before installing.".to_string(),
        ))?
        .insert("lorvex".to_string(), server_entry);

    Ok(serde_json::to_string_pretty(&root)?)
}

pub(crate) fn merge_codex_toml_config(existing: &str) -> Result<String, crate::error::CliError> {
    let mut filtered = Vec::new();
    let mut skipping = false;
    for line in existing.lines() {
        let trimmed = line.trim();
        if trimmed == "[mcp_servers.lorvex]" {
            skipping = true;
            continue;
        }
        if skipping && trimmed.starts_with('[') {
            skipping = false;
        }
        if !skipping {
            filtered.push(line.to_string());
        }
    }

    let (command, args) = lorvex_mcp_command_and_args()?;
    if filtered.last().is_some_and(|line| !line.is_empty()) {
        filtered.push(String::new());
    }
    filtered.push("[mcp_servers.lorvex]".to_string());
    filtered.push(format!("command = {command:?}"));
    filtered.push(format!("args = [{:?}, {:?}]", args[0], args[1]));
    filtered.push("startup_timeout_sec = 20".to_string());
    filtered.push("tool_timeout_sec = 120".to_string());
    Ok(filtered.join("\n") + "\n")
}

fn extract_json_mcp_args(existing: &str) -> Result<Option<Vec<String>>, crate::error::CliError> {
    let root: serde_json::Value = serde_json::from_str(existing)?;
    Ok(root
        .get("mcpServers")
        .and_then(|v| v.get("lorvex"))
        .and_then(|v| v.get("args"))
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(ToString::to_string))
                .collect()
        }))
}

fn extract_json_mcp_command(existing: &str) -> Result<Option<String>, crate::error::CliError> {
    let root: serde_json::Value = serde_json::from_str(existing)?;
    Ok(root
        .get("mcpServers")
        .and_then(|value| value.get("lorvex"))
        .and_then(|value| value.get("command"))
        .and_then(serde_json::Value::as_str)
        .map(ToString::to_string))
}

/// Read the `mcp_servers.lorvex.command` value from a Codex `config.toml`
/// document, returning `None` when the section or key is absent.
///
/// the previous implementation was a hand-rolled
/// line-prefix parser that called `trim_matches('"')` on the raw line
/// suffix. Any TOML-legal value form that isn't a simple
/// double-quoted basic string with no embedded escapes was silently
/// mis-parsed:
/// - `command = "/Applications/My \"Cool\" App/lorvex"` returned a
///   prefix ending at the first inner quote.
/// - Literal strings (single-quoted) had their delimiters preserved.
/// - Multi-line strings were not handled.
///
/// Routing through the `toml` crate handles every TOML string form
/// the spec defines.
pub(crate) fn extract_codex_mcp_command(existing: &str) -> Option<String> {
    let value: toml::Value = toml::from_str(existing).ok()?;
    let command = value
        .get("mcp_servers")?
        .get("lorvex")?
        .get("command")?
        .as_str()?;
    Some(command.to_string())
}

const fn mcp_target_name(target: McpInstallTarget) -> &'static str {
    match target {
        McpInstallTarget::ClaudeDesktop => "Claude Desktop",
        McpInstallTarget::ClaudeCode => "Claude Code",
        McpInstallTarget::Codex => "Codex",
        McpInstallTarget::All => "all supported MCP clients",
    }
}

#[cfg(test)]
mod tests;
