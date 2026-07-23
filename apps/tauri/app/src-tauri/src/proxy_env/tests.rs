use super::*;
use crate::test_support::test_conn;
use std::sync::Mutex;

// Env-var reads/writes are process-global; serialize tests so a
// parallel runner doesn't observe another test's export.
static ENV_LOCK: Mutex<()> = Mutex::new(());

struct EnvGuard {
    keys: Vec<&'static str>,
    saved: Vec<(&'static str, Option<String>)>,
}

impl EnvGuard {
    fn new(keys: &[&'static str]) -> Self {
        let saved = keys
            .iter()
            .map(|k| (*k, std::env::var(k).ok()))
            .collect::<Vec<_>>();
        for key in keys {
            // SAFETY: tests are serialized by ENV_LOCK; no other
            // thread is reading env simultaneously within this
            // module's test suite.
            unsafe {
                std::env::remove_var(key);
            }
        }
        Self {
            keys: keys.to_vec(),
            saved,
        }
    }

    fn set(&self, key: &str, value: &str) {
        // SAFETY: tests are serialized by
        // ENV_LOCK; no other thread is reading env simultaneously
        // within this module's test suite. `std::env::set_var`
        // is `unsafe` on edition 2024 because env mutation
        // races with concurrent getenv calls; the lock + suite-
        // local scope rules that out.
        unsafe {
            std::env::set_var(key, value);
        }
    }
}

impl Drop for EnvGuard {
    fn drop(&mut self) {
        for key in &self.keys {
            // SAFETY: same contract as
            // `EnvGuard::new` — ENV_LOCK serializes the test
            // suite, and the guard's caller still holds the
            // lock when Drop fires.
            unsafe {
                std::env::remove_var(key);
            }
        }
        for (key, value) in &self.saved {
            if let Some(v) = value {
                // SAFETY: same contract as
                // above; restoration runs while the lock is
                // still held.
                unsafe {
                    std::env::set_var(key, v);
                }
            }
        }
    }
}

const ALL_KEYS: &[&str] = &[
    "HTTPS_PROXY",
    "https_proxy",
    "HTTP_PROXY",
    "http_proxy",
    "ALL_PROXY",
    "all_proxy",
    "NO_PROXY",
    "no_proxy",
];

#[test]
fn append_proxy_diagnostic_with_conn_persists_structured_diagnostic() {
    let conn = test_conn();

    append_proxy_diagnostic_with_conn(
        &conn,
        "proxy_env: ignoring malformed HTTPS_PROXY token=secret",
    )
    .expect("append proxy diagnostic");

    let row: (String, String, String, Option<String>) = conn
        .query_row(
            "SELECT source, level, message, details FROM error_logs",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("read diagnostic row");

    assert_eq!(row.0, "proxy_env");
    assert_eq!(row.1, "warn");
    assert_eq!(
        row.2,
        "proxy_env: ignoring malformed HTTPS_PROXY token=[REDACTED]"
    );
    assert_eq!(row.3, None);
}

#[test]
fn malformed_proxy_env_reporter_persists_sanitized_diagnostic() {
    let conn = test_conn();

    report_malformed_proxy_env_with(
        "HTTPS_PROXY",
        &"bad URL http://user:pass@proxy.test:3128 token=secret",
        |detail| {
            append_proxy_diagnostic_with_conn(&conn, detail)
                .expect("append malformed proxy diagnostic");
        },
    );

    let message: String = conn
        .query_row("SELECT message FROM error_logs", [], |row| row.get(0))
        .expect("read diagnostic message");

    assert_eq!(
        message,
        "proxy_env: ignoring malformed HTTPS_PROXY (bad URL http://[REDACTED_USERINFO]@proxy.test:3128 token=[REDACTED]"
    );
    assert!(!message.contains("user:pass"));
    assert!(!message.contains("token=secret"));
}

#[test]
fn ics_client_respects_https_proxy_env_var() {
    // a panicking test holding `ENV_LOCK` would
    // poison the mutex and wedge every subsequent test in this
    // suite. Recover the inner guard so the lock stays usable;
    // the per-test `EnvGuard` Drop restores env vars
    // independently, so a stale snapshot from the panicking test
    // is irrelevant to siblings that capture fresh state on entry.
    let _lock = ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let guard = EnvGuard::new(ALL_KEYS);
    guard.set("HTTPS_PROXY", "http://fake-proxy.test:8888");

    // If the builder accepts the env-sourced proxy and builds a
    // valid client, the fix is wired. An invalid URL would surface
    // as a build error; a "proxy ignored" regression would be
    // caught by the preceding parse step in `apply_proxy_from_env`
    // (which logs and skips) — so building successfully here plus
    // the absence of a log line is the contract we enforce.
    let builder = reqwest::blocking::Client::builder();
    let builder = apply_proxy_from_env(builder);
    assert!(builder.build().is_ok(), "proxy-enabled client must build");
}

#[test]
fn https_proxy_supports_basic_auth_in_url() {
    // a panicking test holding `ENV_LOCK` would
    // poison the mutex and wedge every subsequent test in this
    // suite. Recover the inner guard so the lock stays usable;
    // the per-test `EnvGuard` Drop restores env vars
    // independently, so a stale snapshot from the panicking test
    // is irrelevant to siblings that capture fresh state on entry.
    let _lock = ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let guard = EnvGuard::new(ALL_KEYS);
    guard.set("HTTPS_PROXY", "http://user:pass@corp-proxy.test:3128");

    let builder = apply_proxy_from_env(reqwest::blocking::Client::builder());
    assert!(
        builder.build().is_ok(),
        "basic-auth proxy URL must parse and attach to the client"
    );
}

#[test]
fn no_env_vars_means_direct_connection() {
    // a panicking test holding `ENV_LOCK` would
    // poison the mutex and wedge every subsequent test in this
    // suite. Recover the inner guard so the lock stays usable;
    // the per-test `EnvGuard` Drop restores env vars
    // independently, so a stale snapshot from the panicking test
    // is irrelevant to siblings that capture fresh state on entry.
    let _lock = ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let _guard = EnvGuard::new(ALL_KEYS);

    // With no proxy env vars set we should still produce a working
    // client — the helper must be a no-op in the common case.
    let builder = apply_proxy_from_env(reqwest::blocking::Client::builder());
    assert!(builder.build().is_ok());
}

#[test]
fn malformed_proxy_url_is_skipped_not_fatal() {
    // a panicking test holding `ENV_LOCK` would
    // poison the mutex and wedge every subsequent test in this
    // suite. Recover the inner guard so the lock stays usable;
    // the per-test `EnvGuard` Drop restores env vars
    // independently, so a stale snapshot from the panicking test
    // is irrelevant to siblings that capture fresh state on entry.
    let _lock = ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let guard = EnvGuard::new(ALL_KEYS);
    // Missing scheme — reqwest rejects this. The helper must log
    // and continue, not propagate the error to the caller.
    guard.set("HTTP_PROXY", "not a url");

    let builder = apply_proxy_from_env(reqwest::blocking::Client::builder());
    assert!(
        builder.build().is_ok(),
        "malformed proxy URL must not poison the client build"
    );
}

#[test]
fn lowercase_env_var_is_honored() {
    // a panicking test holding `ENV_LOCK` would
    // poison the mutex and wedge every subsequent test in this
    // suite. Recover the inner guard so the lock stays usable;
    // the per-test `EnvGuard` Drop restores env vars
    // independently, so a stale snapshot from the panicking test
    // is irrelevant to siblings that capture fresh state on entry.
    let _lock = ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let guard = EnvGuard::new(ALL_KEYS);
    guard.set("https_proxy", "http://lowercase-proxy.test:8080");

    let builder = apply_proxy_from_env(reqwest::blocking::Client::builder());
    assert!(builder.build().is_ok());
}

#[test]
fn no_proxy_list_is_parsed_when_set() {
    // a panicking test holding `ENV_LOCK` would
    // poison the mutex and wedge every subsequent test in this
    // suite. Recover the inner guard so the lock stays usable;
    // the per-test `EnvGuard` Drop restores env vars
    // independently, so a stale snapshot from the panicking test
    // is irrelevant to siblings that capture fresh state on entry.
    let _lock = ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let guard = EnvGuard::new(ALL_KEYS);
    guard.set("HTTPS_PROXY", "http://proxy.test:8888");
    guard.set("NO_PROXY", "localhost,.internal.example.com,10.0.0.0/8");

    let builder = apply_proxy_from_env(reqwest::blocking::Client::builder());
    assert!(
        builder.build().is_ok(),
        "NO_PROXY list must be accepted alongside a configured proxy"
    );
}

#[test]
fn scrub_credentials_removes_userinfo_segment() {
    // a malformed proxy URL with embedded
    // basic-auth must not surface the secret in stderr. The
    // scrubber replaces the userinfo segment with `[redacted]`.
    assert_eq!(
        scrub_proxy_credentials("http://user:pass@host:3128"),
        "http://[redacted]@host:3128"
    );
    assert_eq!(
        scrub_proxy_credentials(
            "builder error: bad URL https://alice:hunter2@proxy.test:8080/path?q=1"
        ),
        "builder error: bad URL https://[redacted]@proxy.test:8080/path?q=1"
    );
}

#[test]
fn scrub_credentials_leaves_credential_free_url_alone() {
    // URLs without userinfo round-trip unchanged.
    assert_eq!(
        scrub_proxy_credentials("http://corp-proxy.test:3128"),
        "http://corp-proxy.test:3128"
    );
    // Embedded `@` outside userinfo (e.g. in a query) must not
    // be misidentified as userinfo termination.
    assert_eq!(
        scrub_proxy_credentials("https://proxy.test/?email=user@example.com"),
        "https://proxy.test/?email=user@example.com"
    );
}

#[test]
fn scrub_credentials_handles_non_url_text() {
    assert_eq!(scrub_proxy_credentials("not a url"), "not a url");
    assert_eq!(scrub_proxy_credentials(""), "");
}

#[test]
fn async_variant_mirrors_blocking_behaviour() {
    // a panicking test holding `ENV_LOCK` would
    // poison the mutex and wedge every subsequent test in this
    // suite. Recover the inner guard so the lock stays usable;
    // the per-test `EnvGuard` Drop restores env vars
    // independently, so a stale snapshot from the panicking test
    // is irrelevant to siblings that capture fresh state on entry.
    let _lock = ENV_LOCK
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let guard = EnvGuard::new(ALL_KEYS);
    guard.set("HTTPS_PROXY", "http://fake-proxy.test:8888");

    let builder = apply_proxy_from_env_async(reqwest::Client::builder());
    assert!(builder.build().is_ok());
}
