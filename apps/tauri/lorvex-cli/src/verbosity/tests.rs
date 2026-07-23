use super::*;
use std::sync::{Mutex, MutexGuard, OnceLock};

fn rust_log_test_lock() -> MutexGuard<'static, ()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
        .lock()
        .expect("lock RUST_LOG test guard")
}

struct RustLogGuard {
    previous: Option<String>,
}

impl RustLogGuard {
    fn capture() -> Self {
        Self {
            previous: std::env::var("RUST_LOG").ok(),
        }
    }

    fn set(&self, value: &str) {
        unsafe {
            std::env::set_var("RUST_LOG", value);
        }
    }

    fn clear(&self) {
        unsafe {
            std::env::remove_var("RUST_LOG");
        }
    }
}

impl Drop for RustLogGuard {
    fn drop(&mut self) {
        unsafe {
            match self.previous.as_deref() {
                Some(value) => std::env::set_var("RUST_LOG", value),
                None => std::env::remove_var("RUST_LOG"),
            }
        }
    }
}

fn s(args: &[&str]) -> Vec<String> {
    args.iter().map(std::string::ToString::to_string).collect()
}

#[test]
fn extract_verbosity_strips_flags_only_before_subcommand() {
    let _lock = rust_log_test_lock();
    let rust_log = RustLogGuard::capture();
    rust_log.clear();

    // Global flags BEFORE the subcommand are stripped and resolved.
    let (rest, lvl) = extract_verbosity_override(s(&["-v", "today", "-l", "5"]));
    assert_eq!(rest, s(&["today", "-l", "5"]));
    assert_eq!(lvl, CliLogLevel::Info);

    let (rest, lvl) = extract_verbosity_override(s(&["-vv", "today"]));
    assert_eq!(rest, s(&["today"]));
    assert_eq!(lvl, CliLogLevel::Debug);

    let (rest, lvl) = extract_verbosity_override(s(&["-v", "-v", "-v", "today"]));
    assert_eq!(rest, s(&["today"]));
    assert_eq!(lvl, CliLogLevel::Trace);

    let (rest, lvl) = extract_verbosity_override(s(&["--quiet", "today"]));
    assert_eq!(rest, s(&["today"]));
    assert_eq!(lvl, CliLogLevel::Quiet);

    // --quiet wins over --verbose (quiet is the stronger intent).
    let (_rest, lvl) = extract_verbosity_override(s(&["-v", "-q", "today"]));
    assert_eq!(lvl, CliLogLevel::Quiet);
}

/// Regression: a positional value or sub-flag value that happens to
/// equal `-v` / `--quiet` MUST NOT be eaten as a verbosity flag.
/// Memory keys and capture titles are free-form user strings — losing one
/// to verbosity stripping is silent data corruption.
#[test]
fn extract_verbosity_preserves_v_and_q_after_subcommand() {
    let _lock = rust_log_test_lock();
    let rust_log = RustLogGuard::capture();
    rust_log.clear();

    // Subcommand `today`, then a flag value that equals `-v`.
    let (rest, lvl) = extract_verbosity_override(s(&["today", "-v", "-l", "5"]));
    assert_eq!(rest, s(&["today", "-v", "-l", "5"]));
    assert_eq!(lvl, CliLogLevel::Warn); // default; nothing stripped

    // Capture command with a literal "-q" as the title.
    let (rest, lvl) = extract_verbosity_override(s(&["capture", "-q"]));
    assert_eq!(rest, s(&["capture", "-q"]));
    assert_eq!(lvl, CliLogLevel::Warn);

    // Memory write with a "--verbose"-named key.
    let (rest, _) = extract_verbosity_override(s(&["memory", "write", "--verbose", "value"]));
    assert_eq!(rest, s(&["memory", "write", "--verbose", "value"]));
}

#[test]
fn extract_verbosity_preserves_unknown_args() {
    let _lock = rust_log_test_lock();
    let rust_log = RustLogGuard::capture();
    rust_log.clear();
    let input = s(&["cancel", "task-1", "--series", "--unknown-flag", "value"]);
    let (rest, lvl) = extract_verbosity_override(input.clone());
    assert_eq!(rest, input);
    assert_eq!(lvl, CliLogLevel::Warn);
}

#[test]
fn rust_log_overrides_flags() {
    let _lock = rust_log_test_lock();
    let rust_log = RustLogGuard::capture();
    rust_log.set("debug");
    let (_rest, lvl) = extract_verbosity_override(s(&["today"]));
    assert_eq!(lvl, CliLogLevel::Debug);

    // Target-filtered form: `lorvex_cli=trace` → Trace.
    rust_log.set("lorvex_cli=trace");
    let (_rest, lvl) = extract_verbosity_override(s(&["today"]));
    assert_eq!(lvl, CliLogLevel::Trace);
}
