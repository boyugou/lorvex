use super::*;

#[test]
fn desktop_cli_agent_is_agent_first_not_gui_first() {
    let capabilities = capabilities_for(SurfaceProfile::DesktopCliAgent);
    assert!(capabilities.mcp_host);
    assert!(!capabilities.gui_surface);
    assert!(!capabilities.tui_surface);
}

#[test]
fn desktop_app_mcp_host_is_macos_only() {
    let capabilities = capabilities_for(SurfaceProfile::DesktopApp);
    // Audit F12 / #2841: the App bundle ships the embedded MCP
    // helper only on macOS. The flag MUST mirror the runtime
    // reality so external code that branches on it (e.g. doctor
    // recommendations) doesn't try to launch a missing binary on
    // Windows / Linux.
    assert_eq!(capabilities.mcp_host, cfg!(target_os = "macos"));
}

#[test]
fn desktop_cli_tui_exposes_terminal_surface_only() {
    let capabilities = capabilities_for(SurfaceProfile::DesktopCliTui);
    assert!(capabilities.tui_surface);
    assert!(!capabilities.gui_surface);
    assert!(!capabilities.mcp_host);
}

/// pin the contract that adding a new
/// `SurfaceProfile` variant or a new `SurfaceCapabilities` field
/// is a forward-compatible change for consumers in other crates.
/// We can't easily probe the attribute via the type system at
/// runtime, but we can pin behavior: every variant the producer
/// declares must round-trip through `capabilities_for`, and the
/// match on `profile` inside `capabilities_for` is the ONLY site
/// that needs to enumerate variants exhaustively. A wildcard
/// safety net here makes that assumption explicit.
#[test]
fn capabilities_for_handles_every_known_profile_today() {
    // If a future variant lands, this loop will need to grow with
    // it, but consumers in other crates won't break thanks to
    // #[non_exhaustive] forcing them to carry a wildcard arm.
    for profile in [
        SurfaceProfile::DesktopApp,
        SurfaceProfile::DesktopCliAgent,
        SurfaceProfile::DesktopCliTui,
        SurfaceProfile::MobilePeer,
    ] {
        // Round-trip — must not panic, must produce a struct.
        let _capabilities = capabilities_for(profile);
    }
}
