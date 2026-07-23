//! HTTP proxy configuration from standard environment variables.
//!
//! reqwest's default `Client::builder()` behaviour is to
//! call `Proxy::system()` implicitly, which on Unix reads
//! `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` (plus their lowercase
//! twins) and `NO_PROXY`. That implicit path is racy in two ways:
//!
//! 1. It snapshots env vars the first time a client is built and caches
//!    the result for the rest of the process, so a user who exports
//!    `HTTPS_PROXY` after the ICS fetcher has already warmed a client
//!    never sees the proxy applied.
//! 2. It only runs on Unix. On Windows reqwest pulls proxy config from
//!    WinHTTP, which silently ignores the env vars corporate IT often
//!    scripts onto machines.
//!
//! This module reads the env vars explicitly on every client build and
//! wires a matching `reqwest::Proxy` into the supplied
//! `ClientBuilder`. It honors basic-auth embedded in the proxy URL
//! (`http://user:pass@host:port`) because reqwest parses it natively,
//! and it respects `NO_PROXY` as a comma-separated list of hostnames /
//! domain suffixes / `*` via `Proxy::no_proxy`.
//!
//! Scope: HTTP + HTTPS only. SOCKS would require the `socks` reqwest
//! feature, which is intentionally out of scope for this audit; if
//! `ALL_PROXY` names a `socks5://` URL, reqwest will surface the
//! unsupported-scheme error and the caller will fall through to a
//! direct connection.

use reqwest::{NoProxy, Proxy};

/// Route proxy-env parse failures through the app's `error_logs`
/// surface (visible in Settings → Diagnostics). Logging to stderr
/// alone would be invisible on packaged builds — Windows hides
/// stderr under `windows_subsystem = "windows"`, and macOS `.app`
/// bundles run detached from any console — so a user with a
/// malformed `HTTPS_PROXY` would silently fall through to a direct
/// connection with no way to discover why.
fn append_proxy_diagnostic_with_conn(
    conn: &rusqlite::Connection,
    detail: &str,
) -> Result<(), String> {
    crate::commands::diagnostics::append_error_log_internal(
        conn,
        "proxy_env",
        detail,
        None,
        Some("warn".to_string()),
    )
}

/// Best-effort: when the diagnostic DB itself is unreachable (early
/// startup, migrations not yet applied, locked file), drop the
/// diagnostic rather than writing release-invisible stderr.
fn report_proxy_diagnostic(detail: &str) {
    let Ok(conn) = crate::db::get_conn() else {
        return;
    };
    let _ = append_proxy_diagnostic_with_conn(&conn, detail);
}

fn report_malformed_proxy_env_with(
    env_name: &str,
    error: &dyn std::fmt::Display,
    report: impl FnOnce(&str),
) {
    report(&format!(
        "proxy_env: ignoring malformed {env_name} ({})",
        scrub_proxy_credentials(&error.to_string())
    ));
}

fn report_malformed_proxy_env(env_name: &str, error: &dyn std::fmt::Display) {
    report_malformed_proxy_env_with(env_name, error, report_proxy_diagnostic);
}

/// scrub `user:pass@host` basic-auth segments from
/// proxy URLs before they reach the diagnostic surface. The reqwest
/// URL parse error message (and sometimes the URL we hand it back
/// ourselves) can echo the originating string verbatim, which would
/// leak credentials into the structured `error_logs` table — captured
/// by `export_diagnostics_bundle` when the user is collecting a
/// support bundle (#2183). We do a purely textual replace because
/// the URL may have already failed to parse; matching with
/// `url::Url` would lose the malformed input. Pattern:
/// `://<userinfo>@<host>...` → `://[redacted]@<host>...`.
fn scrub_proxy_credentials(value: &str) -> String {
    // Operate on bytes for simple offsets, then slice the original
    // `value` so any non-ASCII bytes (which cannot legally appear in
    // userinfo per RFC 3986 but might land here from a corrupted env
    // var) survive the scrub without mojibake. Each region we copy
    // out is guaranteed to start and end on a `&str` boundary because
    // we only split at ASCII delimiters (`://`, `@`, `/`, `?`, `#`,
    // whitespace), which never appear inside a multi-byte UTF-8
    // sequence.
    let bytes = value.as_bytes();
    let mut out = String::with_capacity(value.len());
    let mut cursor = 0usize;
    while cursor < bytes.len() {
        if cursor + 2 < bytes.len() && &bytes[cursor..cursor + 3] == b"://" {
            // Copy any pending prefix that didn't already get pushed
            // (the loop below pushes byte-by-byte for the non-match
            // path, so this branch only fires when cursor is at the
            // exact `://` start).
            out.push_str("://");
            cursor += 3;
            // Probe the userinfo region for a terminating `@`.
            let mut probe = cursor;
            let mut at_pos = None;
            while probe < bytes.len() {
                let b = bytes[probe];
                if b == b'@' {
                    at_pos = Some(probe);
                    break;
                }
                if matches!(b, b'/' | b'?' | b'#' | b' ' | b'\t' | b'\n' | b'\r') {
                    break;
                }
                probe += 1;
            }
            if let Some(at) = at_pos {
                if at > cursor {
                    out.push_str("[redacted]");
                }
                out.push('@');
                cursor = at + 1;
                continue;
            }
            // No `@` — nothing to redact in this segment; fall through
            // and let the byte-copy loop handle the host portion.
        }
        // Default: copy a single UTF-8 character. `value[cursor..]`
        // is valid UTF-8 because `cursor` only advances by either 3
        // (the `://` literal), `at + 1` (one past an ASCII `@`), or
        // the length of the next UTF-8 char.
        if let Some(ch) = value[cursor..].chars().next() {
            out.push(ch);
            cursor += ch.len_utf8();
        } else {
            break;
        }
    }
    out
}

/// Read `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` (case-insensitive on
/// Unix per curl convention) from the process environment. Returns the
/// first non-empty value found, checking the upper-case spelling first
/// because that matches what most corporate proxies document.
fn read_env(names: &[&str]) -> Option<String> {
    for name in names {
        if let Ok(value) = std::env::var(name) {
            if !value.trim().is_empty() {
                return Some(value);
            }
        }
    }
    None
}

/// Read the `NO_PROXY` env var (both spellings) as a comma-separated
/// list of hostnames / domain suffixes that should bypass the proxy.
/// Returns `None` when the var is unset or empty so the caller can
/// skip the `no_proxy` configuration entirely.
fn read_no_proxy() -> Option<NoProxy> {
    let raw = read_env(&["NO_PROXY", "no_proxy"])?;
    NoProxy::from_string(&raw)
}

/// Apply `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` to the given
/// reqwest client builder. Each env var maps to its own `Proxy`
/// instance so a user who only exports `HTTPS_PROXY` doesn't
/// accidentally route plaintext HTTP through the same hop.
///
/// Returns the builder unchanged when no relevant env vars are set
/// — the common no-proxy case keeps the direct-connection default.
/// When a URL is malformed, the parse error is logged via
/// `report_proxy_diagnostic` (error_logs surface) and that specific
/// proxy is skipped — a bad `HTTP_PROXY` should not poison an
/// otherwise-valid `HTTPS_PROXY`.
pub(crate) fn apply_proxy_from_env(
    mut builder: reqwest::blocking::ClientBuilder,
) -> reqwest::blocking::ClientBuilder {
    let no_proxy = read_no_proxy();

    // `ALL_PROXY` wins for both schemes when set. We still allow a
    // scheme-specific override below, so exporting ALL_PROXY plus a
    // more specific HTTPS_PROXY behaves the way curl documents:
    // specific wins.
    if let Some(url) = read_env(&["ALL_PROXY", "all_proxy"]) {
        match Proxy::all(&url) {
            Ok(proxy) => builder = builder.proxy(proxy.no_proxy(no_proxy.clone())),
            Err(err) => report_malformed_proxy_env("ALL_PROXY", &err),
        }
    }

    if let Some(url) = read_env(&["HTTPS_PROXY", "https_proxy"]) {
        match Proxy::https(&url) {
            Ok(proxy) => builder = builder.proxy(proxy.no_proxy(no_proxy.clone())),
            Err(err) => report_malformed_proxy_env("HTTPS_PROXY", &err),
        }
    }

    if let Some(url) = read_env(&["HTTP_PROXY", "http_proxy"]) {
        match Proxy::http(&url) {
            Ok(proxy) => builder = builder.proxy(proxy.no_proxy(no_proxy)),
            Err(err) => report_malformed_proxy_env("HTTP_PROXY", &err),
        }
    }

    builder
}

/// Async variant for `reqwest::Client` (non-blocking), used by the
/// Tauri updater builder. The logic is identical to the blocking
/// version; we keep two copies because `reqwest::ClientBuilder` and
/// `reqwest::blocking::ClientBuilder` don't share a trait we can
/// generic over.
pub(crate) fn apply_proxy_from_env_async(
    mut builder: reqwest::ClientBuilder,
) -> reqwest::ClientBuilder {
    let no_proxy = read_no_proxy();

    if let Some(url) = read_env(&["ALL_PROXY", "all_proxy"]) {
        match Proxy::all(&url) {
            Ok(proxy) => builder = builder.proxy(proxy.no_proxy(no_proxy.clone())),
            Err(err) => report_malformed_proxy_env("ALL_PROXY", &err),
        }
    }

    if let Some(url) = read_env(&["HTTPS_PROXY", "https_proxy"]) {
        match Proxy::https(&url) {
            Ok(proxy) => builder = builder.proxy(proxy.no_proxy(no_proxy.clone())),
            Err(err) => report_malformed_proxy_env("HTTPS_PROXY", &err),
        }
    }

    if let Some(url) = read_env(&["HTTP_PROXY", "http_proxy"]) {
        match Proxy::http(&url) {
            Ok(proxy) => builder = builder.proxy(proxy.no_proxy(no_proxy)),
            Err(err) => report_malformed_proxy_env("HTTP_PROXY", &err),
        }
    }

    builder
}

#[cfg(test)]
mod tests;
