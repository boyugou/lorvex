//! Surface tag baked into the HLC device suffix so the Tauri app, MCP
//! server, and CLI emit distinct device suffixes despite sharing the
//! same `sync_checkpoints.device_id`.

/// Surface tag baked into the HLC device suffix so the Tauri app,
/// MCP server, and CLI — three separate processes sharing one
/// `sync_checkpoints.device_id` — emit **distinct** device suffixes.
///
/// all three surfaces derived the same 8-char
/// suffix from the shared device_id. Each process holds its own
/// in-memory `HlcState` counter, so two processes that call
/// `generate()` in the same wall-clock millisecond with counter=0
/// produced **identical** HLC strings. LWW then resolved the tie to
/// LocalWins and silently dropped the second write. Hashing
/// `device_id || surface` breaks the collision while keeping each
/// surface's own monotonicity via its own `HlcState`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum HlcSurface {
    /// The Tauri desktop app (user-facing UI writes).
    App,
    /// The MCP server (assistant writes).
    Mcp,
    /// The agent-first CLI.
    Cli,
}

impl HlcSurface {
    /// Stable string tag mixed into the suffix hash. Changing these
    /// values invalidates every already-persisted HLC's collision
    /// isolation; they must stay frozen for the life of the schema.
    pub const fn as_str(&self) -> &'static str {
        match self {
            HlcSurface::App => "app",
            HlcSurface::Mcp => "mcp",
            HlcSurface::Cli => "cli",
        }
    }

    /// All surfaces in a fixed order — used by max-HLC scans that
    /// must aggregate across every suffix this device can emit.
    pub const fn all() -> [HlcSurface; 3] {
        [HlcSurface::App, HlcSurface::Mcp, HlcSurface::Cli]
    }
}
