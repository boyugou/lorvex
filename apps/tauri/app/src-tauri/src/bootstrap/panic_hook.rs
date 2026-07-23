//! Process-wide panic handling.
//!
//! [`install_panic_hook`] persists every panic message + backtrace to
//! `error_logs` after redaction, so a Windows release build (which has
//! no console, `windows_subsystem = "windows"`) still leaves a
//! post-mortem trail. The macOS notification-action delegate uses
//! [`catch_unwind_without_default_panic_hook`] to swallow panics
//! locally without polluting the persistent log with duplicates.

use crate::db;

thread_local! {
    static SUPPRESS_DEFAULT_PANIC_HOOK: std::cell::Cell<bool> =
        const { std::cell::Cell::new(false) };
}

pub(crate) fn catch_unwind_without_default_panic_hook<F, R>(f: F) -> std::thread::Result<R>
where
    F: FnOnce() -> R + std::panic::UnwindSafe,
{
    SUPPRESS_DEFAULT_PANIC_HOOK.with(|flag| {
        let previous = flag.replace(true);
        let result = std::panic::catch_unwind(f);
        flag.set(previous);
        result
    })
}

/// Install a panic hook that appends the panic message + location to
/// `error_logs` (post-redaction via `redact_diagnostic_text`) and then
/// chains to the default hook on platforms that expose one.
///
/// Round-26 CLI/env audit: on Windows release builds
/// (`windows_subsystem = "windows"`), there's no console — a panic
/// silently vanishes with zero diagnostic trace. Route the panic
/// through `error_logs` so next-launch diagnostics can surface it.
/// macOS / Linux get the same row plus the output the default hook
/// produces.
pub(crate) fn install_panic_hook() {
    // Preserve the upstream default hook so stderr still gets the
    // conventional backtrace on platforms that have a console.
    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let message = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| (*s).to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "panic with non-string payload".to_string());
        let location = info.location().map_or_else(
            || "<unknown location>".to_string(),
            |l| format!("{}:{}:{}", l.file(), l.line(), l.column()),
        );
        // capture the backtrace into error_logs.details.
        // On Windows release (`windows_subsystem = "windows"`) there's
        // no console, so stderr from the default hook vanishes — the
        // error_logs row is the only post-mortem surface. Without a
        // backtrace, triage required reproducing the crash, defeating
        // the point of persisting it.
        //
        // `force_capture()` honours RUST_BACKTRACE being disabled in
        // some environments by still producing a best-effort trace
        // (vs `capture()` which returns `Disabled` when the env var
        // is unset). The resulting string can carry absolute paths
        // through `src/` — `redact_diagnostic_text` already masks
        // user-home prefixes, so the redacted output stays safe for
        // a bug-report bundle.
        let backtrace = std::backtrace::Backtrace::force_capture();
        let raw_details = format!("panic at {location}: {message}\n{backtrace}");
        let redacted_details = lorvex_domain::diagnostics::redact_diagnostic_text(&raw_details);
        // `message` can contain arbitrary caller-controlled text
        // (e.g. `.expect("missing title for task: 'Therapy with
        // alice@clinic.com'")` or a `serde_json::from_str` panic
        // that formats the failing JSON fragment). Bind a fixed
        // content-free summary to the `message` column and keep the
        // full (redacted) payload only in `details`, so `message`
        // can never leak PII even if the redactor misses something.
        let message_summary = format!("rust panic at {location}");
        // Best-effort append. If the DB is unavailable during a normal
        // panic, the default hook still preserves crash context on
        // platforms that expose it. Suppressed callbacks are already
        // handling their own structured diagnostic, so the hook must
        // stay silent there.
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            if let Ok(conn) = db::get_conn() {
                let now = lorvex_domain::sync_timestamp_now();
                let id = lorvex_domain::new_entity_id_string();
                let _ = conn.execute(
                    "INSERT INTO error_logs (id, source, level, message, details, created_at) \
                     VALUES (?1, 'rust.panic', 'error', ?2, ?3, ?4)",
                    rusqlite::params![id, &message_summary, &redacted_details, now],
                );
            }
        }));
        let suppress_default = SUPPRESS_DEFAULT_PANIC_HOOK.with(std::cell::Cell::get);
        if !suppress_default {
            // Chain to the default hook so the backtrace still reaches
            // the platform panic surface when one exists.
            default_hook(info);
        }
    }));
}
