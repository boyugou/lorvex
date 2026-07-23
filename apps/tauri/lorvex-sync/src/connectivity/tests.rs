use super::*;
use crate::error::SyncError;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

/// Test probe that flips from "online" to "offline" after N calls.
///
/// Counts calls so tests can assert on how many times the transport
/// consulted the probe. AcqRel on `fetch_add` plus Acquire on
/// `calls()` keep concurrent push-callback simulations deterministic
/// across thread schedules.
#[derive(Default, Clone)]
struct MockConnectivityProbe {
    calls: Arc<AtomicU64>,
    reachable_initially: bool,
    flip_after: u64,
}

impl MockConnectivityProbe {
    fn new(reachable_initially: bool, flip_after: u64) -> Self {
        Self {
            calls: Arc::new(AtomicU64::new(0)),
            reachable_initially,
            flip_after,
        }
    }

    fn always_online() -> Self {
        Self::new(true, u64::MAX)
    }

    fn always_offline() -> Self {
        Self::new(false, u64::MAX)
    }

    fn calls(&self) -> u64 {
        self.calls.load(Ordering::Acquire)
    }

    fn is_reachable(&self) -> bool {
        let n = self.calls.fetch_add(1, Ordering::AcqRel);
        if self.flip_after == u64::MAX {
            return self.reachable_initially;
        }
        if n < self.flip_after {
            self.reachable_initially
        } else {
            !self.reachable_initially
        }
    }
}

#[test]
fn looks_like_connection_drop_matches_posix_errors() {
    assert!(looks_like_connection_drop(
        "Connection reset by peer (os error 54)"
    ));
    assert!(looks_like_connection_drop("Broken pipe"));
    assert!(looks_like_connection_drop("ECONNRESET"));
    assert!(looks_like_connection_drop("ETIMEDOUT"));
    assert!(looks_like_connection_drop("Network is unreachable"));
    assert!(looks_like_connection_drop("No route to host"));
}

#[test]
fn looks_like_connection_drop_matches_nsurl_errors() {
    assert!(looks_like_connection_drop("NSURLErrorDomain error -1009"));
    assert!(looks_like_connection_drop(
        "The Internet connection appears to be offline. (NSURLErrorDomain error -1009)"
    ));
    assert!(looks_like_connection_drop("NSURLErrorDomain error -1005"));
    // the URL-domain timeout code (-1001) is
    // still a transport-level drop signal; "operation timed
    // out" alone is NOT (rate-limit responses share the
    // localized text on some macOS versions). The combined
    // string still matches because of the -1001 substring.
    assert!(looks_like_connection_drop(
        "NSURLErrorDomain error -1001: The operation timed out."
    ));
}

/// a bare "operation timed out" without
/// a transport-layer locator (CFURL / NSURL code, POSIX errno
/// mnemonic) MUST NOT be classified as a connection drop. On some
/// Some provider stacks return a localized
/// description ("The request timed out") collides with this
/// substring; pre-fix, the rate-limit response was misreported as
/// "network lost" in the user-facing diagnostics surface. The
/// transport's normal retry / backoff path handles rate-limits.
#[test]
fn looks_like_connection_drop_rejects_bare_operation_timed_out() {
    assert!(!looks_like_connection_drop(
        "The operation timed out. (HTTP 429 request rate limited)"
    ));
    assert!(!looks_like_connection_drop("operation timed out"));
}

#[test]
fn looks_like_connection_drop_matches_urlsession_network_codes() {
    assert!(looks_like_connection_drop("NSURLErrorDomain error -1009"));
    assert!(looks_like_connection_drop("NSURLErrorDomain error -1005"));
}

#[test]
fn looks_like_connection_drop_rejects_app_level_errors() {
    assert!(!looks_like_connection_drop("Permission denied"));
    assert!(!looks_like_connection_drop(
        "Unknown record type 'Task' — schema not deployed"
    ));
    assert!(!looks_like_connection_drop(
        "Provider conflict: server record changed"
    ));
    assert!(!looks_like_connection_drop("Quota exceeded"));
}

#[test]
fn classify_and_abort_returns_none_for_app_level_errors() {
    // Even with the probe offline, a schema-mismatch error must not
    // short-circuit to NetworkDropped — otherwise permanent app-
    // level failures would masquerade as connectivity issues and
    // never burn retry budget.
    let probe = MockConnectivityProbe::always_offline();
    let result = classify_and_abort("Provider permission denied", || probe.is_reachable());
    assert!(result.is_none());
    assert_eq!(
        probe.calls(),
        0,
        "probe should not be consulted for app-level errors"
    );
}

#[test]
fn classify_and_abort_returns_none_when_probe_says_online() {
    // A "looks like a drop" error can happen on a single hiccuped
    // connection while the device is still on the network. The
    // transport's retry path handles it.
    let probe = MockConnectivityProbe::always_online();
    let result = classify_and_abort("Connection reset by peer", || probe.is_reachable());
    assert!(result.is_none());
    assert_eq!(probe.calls(), 1);
}

#[test]
fn classify_and_abort_returns_network_dropped_when_probe_offline() {
    let probe = MockConnectivityProbe::always_offline();
    let result = classify_and_abort("NSURLErrorDomain error -1009", || probe.is_reachable());
    match result {
        Some(SyncError::NetworkDropped { message }) => {
            assert!(message.contains("-1009"));
        }
        other => panic!("expected NetworkDropped, got {other:?}"),
    }
    assert_eq!(probe.calls(), 1);
}

#[test]
fn mock_probe_flips_after_n_calls() {
    let probe = MockConnectivityProbe::new(true, 3);
    assert!(probe.is_reachable()); // call 0
    assert!(probe.is_reachable()); // call 1
    assert!(probe.is_reachable()); // call 2
    assert!(!probe.is_reachable()); // call 3 — flipped
    assert!(!probe.is_reachable()); // call 4 — still flipped
    assert_eq!(probe.calls(), 5);
}

// Mid-fetch network drop simulation
// ---------------------------------
// Simulates the exact scenario from issue #2705: a sync cycle
// starts while online, then the network drops mid-fetch. Each
// "batch" in the simulation (1) hits a connection-level error and
// (2) consults the probe. We assert that once the probe flips
// offline, the cycle exits with NetworkDropped rather than riding
// out the full per-request timeout.

/// per-batch yield used by the simulated push
/// loop below. The value mirrors the rough order-of-magnitude
/// pacing a real push cycle takes between IO probes — long
/// enough that `batches_run` is a meaningful proxy for how many
/// iterations we actually executed before the abort fired,
/// short enough that the test still finishes in well under a
/// second so it's safe to run on every cargo invocation. Lifted
/// to a named constant so future tunes happen in one place
/// instead of as a magic 50 sprinkled across the simulator.
const SIMULATED_BATCH_YIELD_MS: u64 = 50;

/// Simulate a push loop that issues 10 batches; each batch fails
/// with a connection-reset error and consults the probe. The probe
/// flips offline after the 2nd call, mirroring Wi-Fi dropping 2s
/// into the cycle.
fn simulate_push_cycle(probe: &MockConnectivityProbe) -> (Option<SyncError>, u64, Duration) {
    let start = Instant::now();
    let mut batches_run = 0_u64;
    let mut final_err: Option<SyncError> = None;
    for _ in 0..10 {
        batches_run += 1;
        // Simulate a per-batch IO failure. In production this is
        // the `rx.recv_timeout(PUSH_TIMEOUT_SECS)` firing — we
        // skip the 120s wait by short-circuiting here on the
        // probe check.
        let raw_err = "Connection reset by peer (os error 54)";
        if let Some(err) = classify_and_abort(raw_err, || probe.is_reachable()) {
            final_err = Some(err);
            break;
        }
        // Simulate some per-batch work so batches_run reflects
        // how many iterations we actually ran before bailing.
        thread::sleep(Duration::from_millis(SIMULATED_BATCH_YIELD_MS));
    }
    (final_err, batches_run, start.elapsed())
}

#[test]
fn push_cycle_exits_within_budget_on_mid_fetch_network_drop() {
    // Probe reports online for the first 2 batches, then flips
    // offline — matches "sync started while online, Wi-Fi drops
    // 2s into the cycle."
    let probe = MockConnectivityProbe::new(true, 2);

    let (err, batches_run, elapsed) = simulate_push_cycle(&probe);

    match err {
        Some(SyncError::NetworkDropped { message }) => {
            assert!(message.contains("Connection reset"), "msg: {message}");
        }
        other => panic!("expected NetworkDropped after probe flipped, got {other:?}"),
    }
    // Probe flipped after call 2, so batches 0 + 1 continued (the
    // probe said online), batch 2's probe call returned offline
    // and we aborted. 3 batches, ~50ms each + probe overhead.
    assert_eq!(
        batches_run, 3,
        "should abort on the 3rd batch (first offline probe), ran {batches_run}"
    );
    // The whole cycle must exit in ~5s at worst. In practice this
    // runs in ~150ms. The upper bound guards against a future
    // regression that reintroduces the 120s-per-batch wait.
    assert!(
        elapsed < Duration::from_secs(5),
        "cycle should exit within 5s on network drop, took {elapsed:?}"
    );
    assert_eq!(probe.calls(), 3);
}

#[test]
fn push_cycle_never_aborts_when_online_throughout() {
    // Sanity: if the probe stays online, classify_and_abort must
    // never return NetworkDropped (even though every batch hit an
    // IO error that "looks like" a drop). This guards against a
    // regression that makes the probe the sole gate — permanent
    // app errors would then masquerade as network blips.
    let probe = MockConnectivityProbe::always_online();
    let (err, batches_run, _) = simulate_push_cycle(&probe);
    assert!(err.is_none(), "online probe must not emit NetworkDropped");
    assert_eq!(batches_run, 10, "full cycle should run to completion");
    assert_eq!(probe.calls(), 10);
}
