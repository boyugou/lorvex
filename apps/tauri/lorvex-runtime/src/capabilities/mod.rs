/// marked `#[non_exhaustive]` so external crates that
/// match on `SurfaceProfile` MUST handle a wildcard arm. Adding a new
/// variant (e.g. `MobileMcpPeer` once mobile MCP ships) would otherwise
/// silently break every downstream `match` site that didn't get a
/// targeted compiler error during the rollout. With `non_exhaustive`,
/// the wildcard is mandatory and the new variant ships behind a named
/// concrete arm in the producer crate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub enum SurfaceProfile {
    DesktopApp,
    DesktopCliAgent,
    DesktopCliTui,
    MobilePeer,
}

/// marked `#[non_exhaustive]` so external crates that
/// destructure or pattern-match on `SurfaceCapabilities` cannot break
/// when a new capability flag is added. The struct is intentionally
/// public so consumers (CLI doctor, app diagnostics) can read the
/// fields, but adding a new boolean (e.g. `notifications_owner`) must
/// not silently flip the meaning of an existing exhaustive `let` /
/// pattern in another crate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[non_exhaustive]
pub struct SurfaceCapabilities {
    pub gui_surface: bool,
    /// Whether this surface can serve MCP (has the binary/runtime).
    /// Note: whether it's the *active* external MCP host is decided by
    /// the MCP host authority system, not by this flag.
    pub mcp_host: bool,
    pub tui_surface: bool,
}

pub const fn capabilities_for(profile: SurfaceProfile) -> SurfaceCapabilities {
    match profile {
        SurfaceProfile::DesktopApp => SurfaceCapabilities {
            gui_surface: true,
            // The macOS App bundle ships the embedded MCP server at
            // `Lorvex.app/Contents/Resources/lorvex-mcp` for MAS users.
            // Windows / Linux App builds do NOT bundle the helper —
            // see `mcp_authority::cli_binary_candidates` for the
            // platform-conditional install paths. Without this gate
            // (audit F12 / #2841) anything that branches on
            // `capabilities_for(DesktopApp).mcp_host` to register an
            // MCP endpoint pointed at a missing binary on Windows.
            mcp_host: cfg!(target_os = "macos"),
            tui_surface: false,
        },
        SurfaceProfile::DesktopCliAgent => SurfaceCapabilities {
            gui_surface: false,
            // Issue #2994 L18 (clarify): the CLI agent surface IS the
            // distribution that ships the `lorvex-mcp-server` binary —
            // the workspace builds it as a sibling target, the homebrew
            // tap installs it next to `lorvex`, and the cargo-install
            // path puts both into `~/.cargo/bin/`. So `mcp_host: true`
            // is platform-independent here, NOT a Linux/Windows lie:
            // unlike `DesktopApp` (which only bundles the helper inside
            // a macOS .app), every CLI install includes the helper.
            // The `mcp_authority::detect_cli_installation` runtime probe
            // is the layer that confirms "binary exists at an executable
            // path"; capability flags only declare the static contract.
            mcp_host: true,
            tui_surface: false,
        },
        SurfaceProfile::DesktopCliTui => SurfaceCapabilities {
            gui_surface: false,
            mcp_host: false,
            tui_surface: true,
        },
        SurfaceProfile::MobilePeer => SurfaceCapabilities {
            gui_surface: true,
            mcp_host: false,
            tui_surface: false,
        },
    }
}

#[cfg(test)]
mod tests;
