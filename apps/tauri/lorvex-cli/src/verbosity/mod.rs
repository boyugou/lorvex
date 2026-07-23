//! lightweight verbosity + logging plumbing for `lorvex-cli`.
//!
//! The CLI had no `-v`/`-q` flag and no logging initialization:
//! `RUST_LOG=debug lorvex doctor` produced the same output as an unset env
//! var, leaving a user stuck behind "Error: database is locked" with no way
//! to escalate verbosity. This module adds a minimal, dependency-free
//! verbosity level + an `eprintln!`-gated `cli_log!` macro so we can emit
//! debug/trace hints from anywhere in the crate without pulling in
//! `env_logger` or `tracing_subscriber`.
//!
//! Flag extraction happens in `main.rs` before the clap parser runs
//! (mirroring the `apply_db_path_override` pattern) so every subcommand
//! honors `-v`/`-q` without per-command plumbing.
//!
//! Precedence: `RUST_LOG` env override > `-v`/`-q` flags > default (`Warn`).

use std::sync::atomic::{AtomicU8, Ordering};

/// Log verbosity. Ordered `Quiet < Warn < Info < Debug < Trace`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum CliLogLevel {
    /// Suppress all chatter; only `Error:` prefixed failures still print.
    Quiet = 0,
    /// Default: warnings + errors.
    Warn = 1,
    /// `-v`: high-level progress messages.
    Info = 2,
    /// `-vv`: per-operation diagnostics (SQL calls, file paths, IO kinds).
    Debug = 3,
    /// `-vvv`: maximally noisy, every call site emits.
    Trace = 4,
}

impl CliLogLevel {
    const fn as_u8(self) -> u8 {
        self as u8
    }

    const fn from_u8(v: u8) -> Self {
        match v {
            0 => Self::Quiet,
            1 => Self::Warn,
            2 => Self::Info,
            3 => Self::Debug,
            _ => Self::Trace,
        }
    }

    /// Parse a `RUST_LOG`-style string. Only the level token is honored;
    /// target-filtered forms like `lorvex_cli=debug` are accepted by
    /// stripping the target prefix and reading the tail. This is a
    /// deliberate simplification — we are not `env_logger`, only a shim
    /// until one is adopted.
    fn from_env_token(token: &str) -> Option<Self> {
        let token = token.trim();
        let bare = token
            .rsplit('=')
            .next()
            .unwrap_or(token)
            .to_ascii_lowercase();
        match bare.as_str() {
            "off" | "quiet" => Some(Self::Quiet),
            "error" | "warn" => Some(Self::Warn),
            "info" => Some(Self::Info),
            "debug" => Some(Self::Debug),
            "trace" => Some(Self::Trace),
            _ => None,
        }
    }
}

static LEVEL: AtomicU8 = AtomicU8::new(CliLogLevel::Warn as u8);

/// Install the process-wide verbosity level. Called once from `main.rs`
/// after arg extraction; safe to call from any thread.
pub(crate) fn set_level(level: CliLogLevel) {
    LEVEL.store(level.as_u8(), Ordering::Relaxed);
}

/// Read the current verbosity level.
pub(crate) fn level() -> CliLogLevel {
    CliLogLevel::from_u8(LEVEL.load(Ordering::Relaxed))
}

/// Returns true when the given level should produce output.
pub(crate) fn enabled(at: CliLogLevel) -> bool {
    level() >= at
}

/// Extract `-v`/`--verbose` (repeatable) and `-q`/`--quiet` from the raw
/// arg list, compute the resolved `CliLogLevel` honoring `RUST_LOG` as an
/// override, and return the remaining args with the flags stripped.
///
/// Repeatable `-v` stacks: `-v` = Info, `-vv` = Debug, `-vvv` = Trace.
/// `-q` / `--quiet` forces `Quiet` regardless of `-v` count. `RUST_LOG`
/// takes precedence over both so automation scripts can pin a specific
/// level without editing flag order.
///
/// Only flags appearing **before the first non-flag token** (i.e. before
/// the subcommand name) are stripped. This matches the conventional
/// global-flag boundary and prevents a positional value that happens to
/// equal `-v` / `--quiet` (a memory key or capture title) from being
/// silently eaten and mis-consumed as verbosity.
pub(crate) fn extract_verbosity_override(args: Vec<String>) -> (Vec<String>, CliLogLevel) {
    let mut verbose_count: u8 = 0;
    let mut quiet = false;
    let mut remaining = Vec::with_capacity(args.len());
    let mut past_global_flags = false;
    for arg in args {
        if past_global_flags {
            remaining.push(arg);
            continue;
        }
        match arg.as_str() {
            "-v" | "--verbose" => verbose_count = verbose_count.saturating_add(1),
            "-vv" => verbose_count = verbose_count.saturating_add(2),
            "-vvv" => verbose_count = verbose_count.saturating_add(3),
            "-q" | "--quiet" => quiet = true,
            _ => {
                // First non-verbosity token closes the global-flag window.
                // Subsequent `-v` / `-q` are treated as positional values
                // belonging to the subcommand and are passed through
                // unchanged.
                if !arg.starts_with('-') {
                    past_global_flags = true;
                }
                remaining.push(arg);
            }
        }
    }

    // Flag-derived level (before env override).
    let flag_level = if quiet {
        CliLogLevel::Quiet
    } else {
        match verbose_count {
            0 => CliLogLevel::Warn,
            1 => CliLogLevel::Info,
            2 => CliLogLevel::Debug,
            _ => CliLogLevel::Trace,
        }
    };

    let resolved = std::env::var("RUST_LOG")
        .ok()
        .as_deref()
        .and_then(CliLogLevel::from_env_token)
        .unwrap_or(flag_level);

    (remaining, resolved)
}

/// `eprintln!`-gated log macro. Writes to stderr only when the current
/// level is at least `$lvl`. Used like:
///   `cli_log!(Debug, "opened db at {}", path.display());`
macro_rules! cli_log {
    ($lvl:ident, $($arg:tt)*) => {{
        if $crate::verbosity::enabled($crate::verbosity::CliLogLevel::$lvl) {
            eprintln!("[{}] {}", stringify!($lvl), format_args!($($arg)*));
        }
    }};
}
pub(crate) use cli_log;

#[cfg(test)]
mod tests;
