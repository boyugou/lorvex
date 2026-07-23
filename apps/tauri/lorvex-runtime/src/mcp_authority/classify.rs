use super::model::McpHostKind;

pub fn classify_mcp_host(command_path: &str) -> McpHostKind {
    // `to_lowercase()` is Unicode-aware — on a Turkish
    // locale "I" lowercases to a multi-codepoint sequence ("ı"
    // followed by a combining character on some implementations),
    // which then doesn't match the ASCII-only suffix patterns below.
    // Path lookups are byte-stable; use ASCII-only folding so the
    // matching is locale-independent.
    let lower = command_path.to_ascii_lowercase();

    // ANY binary that lives inside an `.app/Contents/` bundle is
    // owned by the App surface — including hypothetical CLI helpers
    // that a future installer might bundle in-app
    // (`/Applications/Lorvex.app/Contents/MacOS/lorvex` for instance).
    // Without this prefix gate, the in-bundle CLI helper would hit
    // the trailing-`/lorvex` arm below and be misclassified as
    // `Cli`, polluting MCP host authority decisions. The prefix
    // matches the canonical `.app/Contents/` directory layout on
    // macOS regardless of which subdirectory (`MacOS/`, `Resources/`,
    // `Frameworks/`, etc.) the binary sits in.
    if lower.contains(".app/contents/") || lower.contains(".app\\contents\\") {
        return McpHostKind::App;
    }

    // CLI binary patterns. Only reachable for paths OUTSIDE an
    // `.app` bundle thanks to the early-return above.
    if lower.ends_with("/lorvex") || lower.ends_with("\\lorvex") || lower.ends_with("lorvex.exe") {
        return McpHostKind::Cli;
    }

    // App resources MCP binary (cross-platform — covers Windows /
    // Linux app installs that don't use the `.app` bundle layout).
    if lower.contains("resources") && lower.contains("lorvex-mcp") {
        return McpHostKind::App;
    }

    // Standalone `lorvex-mcp-server` binary outside an `.app`
    // bundle. Treat everything outside an `.app` bundle as
    // `Unknown` so the doctor flow can warn the user instead of
    // silently feeding the wrong "authority" into install
    // recommendations. (Returning `McpHostKind::App` here would
    // misclassify `.cargo/bin/` installs and dev-built workspace
    // binaries.)
    if lower.ends_with("lorvex-mcp-server") || lower.ends_with("lorvex-mcp-server.exe") {
        // Standalone or workspace-target build — provenance is
        // ambiguous; defer to the caller.
        return McpHostKind::Unknown(unknown_variant_label(command_path));
    }

    McpHostKind::Unknown(unknown_variant_label(command_path))
}

/// Strip the directory prefix off `command_path` so the
/// `McpHostKind::Unknown(_)` variant carries only the basename.
///
/// The variant carries only the basename so a downstream surface
/// that persists the value (`mcp_host_authority`, diagnostics
/// export, error report uploaded to a support channel) can never
/// leak the absolute sandbox / home-directory / network-share path
/// out of process. Every other surface in this module already
/// canonicalizes to the binary's basename; the Unknown arm follows
/// the same rule.
/// Falls back to the raw input if no separator is present (already a
/// basename) so the function is total.
fn unknown_variant_label(command_path: &str) -> String {
    // Split on either separator so Windows paths land at the same
    // basename as POSIX. `rfind` returns the index of the last
    // occurrence; everything after it is the basename.
    let basename = command_path
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(command_path);
    if basename.is_empty() {
        // Path ended in a separator (e.g. `/foo/`) — surface a
        // non-leaking placeholder rather than the raw stripped path.
        return "<unknown>".to_string();
    }
    basename.to_string()
}
