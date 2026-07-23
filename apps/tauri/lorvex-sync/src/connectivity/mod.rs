//! Connectivity probing for sync transports.
//!
//! the sync runtime only checks network reachability once
//! before a push/pull cycle starts. If the connection drops mid-fetch
//! (e.g. Wi-Fi drops two seconds into a long provider upload
//! batch), the operation blocks on TCP timeouts until the full per-
//! request timeout elapses — wasting radio wake + battery, holding the
//! writer mutex, and surfacing a misleading "push timeout" as the
//! user-visible reason instead of "network lost."
//!
//! Rather than run a background timer that pings every few seconds
//! (fails the "no ping-like probes on a timer" design constraint), this
//! module exposes a **reactive** probe: on each IO failure that looks
//! like a connection drop (`ECONNRESET`, `ETIMEDOUT`, provider
//! network-unavailable, NSURLErrorDomain -1009, ...), the transport
//! asks the probe whether the device still has a reachable upstream.
//! If the probe returns `false`, the transport short-circuits the rest
//! of the cycle with [`SyncError::NetworkDropped`] so the cycle exits
//! in the probe's budget (typically <1s) rather than riding out the
//! full HTTP timeout.
//!
//! Production callers use [`TcpReachabilityProbe`], which attempts a
//! short TCP connect to a well-known public endpoint. Tests substitute
//! [`MockConnectivityProbe`] (gated under `#[cfg(test)]`).

use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

/// TCP-based reachability probe. Tries to open a TCP socket to a well-
/// known public host with a short timeout; success means "some path to
/// the internet exists from this device." Does not validate DNS or
/// TLS — those are the transport's job.
///
/// The default target is Cloudflare's public DNS resolver on port 53
/// because it responds fast globally and is not gated on DNS
/// resolution (we pass a literal IP).
pub struct TcpReachabilityProbe {
    addrs: Vec<SocketAddr>,
    timeout: Duration,
}

impl TcpReachabilityProbe {
    /// Probe Cloudflare's DNS at 1.1.1.1:53 with a 750ms timeout.
    ///
    /// 750ms is short enough that a reactive probe after an IO error
    /// doesn't meaningfully delay the cycle's exit on a genuinely
    /// dropped network (the probe will time out fast when there's no
    /// route), yet long enough that a lightly-loaded connection
    /// doesn't flap into false "dropped" abandons.
    pub fn default_probe() -> Self {
        Self {
            addrs: vec![
                SocketAddr::from(([1, 1, 1, 1], 53)),
                SocketAddr::from(([8, 8, 8, 8], 53)),
            ],
            timeout: Duration::from_millis(750),
        }
    }

    /// Build a custom probe (used by tests + alternative transports).
    pub fn new(targets: impl IntoIterator<Item = SocketAddr>, timeout: Duration) -> Self {
        Self {
            addrs: targets.into_iter().collect(),
            timeout,
        }
    }

    /// Returns `true` when at least one configured target accepts a TCP
    /// connection within the budget. `false` means we should abort the
    /// current sync cycle rather than retry in place.
    pub fn is_reachable(&self) -> bool {
        for addr in &self.addrs {
            if TcpStream::connect_timeout(addr, self.timeout).is_ok() {
                return true;
            }
        }
        false
    }
}

/// Heuristic: does this error message look like a *connection-level*
/// drop (TCP reset, no route, provider network-unavailable) rather
/// than an application-level failure (schema mismatch, permission
/// denied, bad record)?
///
/// Only connection-level drops justify consulting the reachability
/// probe and aborting the cycle. Application errors still flow through
/// the existing per-record retry bookkeeping.
///
/// Substring matching mirrors `commands::sync_error_kind` on the app
/// side — the error type here is a `String` that has already been
/// flattened from `NSError.localizedDescription`, `reqwest::Error`,
/// and `std::io::Error`.
pub fn looks_like_connection_drop(message: &str) -> bool {
    let lower = message.to_ascii_lowercase();
    // std::io::ErrorKind stringified forms.
    if lower.contains("connection reset")
        || lower.contains("connection aborted")
        || lower.contains("connection closed")
        || lower.contains("broken pipe")
        || lower.contains("network is unreachable")
        || lower.contains("network unreachable")
        || lower.contains("no route to host")
        || lower.contains("host is unreachable")
        || lower.contains("host unreachable")
    {
        return true;
    }
    // POSIX errno mnemonics — rusqlite / blocking reqwest sometimes
    // bubble these through their Display impls verbatim.
    if lower.contains("econnreset")
        || lower.contains("econnaborted")
        || lower.contains("etimedout")
        || lower.contains("enetunreach")
        || lower.contains("ehostunreach")
        || lower.contains("enetdown")
    {
        return true;
    }
    // URLSession and provider-neutral network error codes. These surface in
    // localized error text from filesystem, HTTP, and future non-Apple sync
    // providers.
    if lower.contains("nsurlerrordomain error -1009") // kCFURLErrorNotConnectedToInternet
        || lower.contains("nsurlerrordomain error -1005") // kCFURLErrorNetworkConnectionLost
        || lower.contains("nsurlerrordomain error -1004") // kCFURLErrorCannotConnectToHost
        || lower.contains("nsurlerrordomain error -1003") // kCFURLErrorCannotFindHost
        || lower.contains("nsurlerrordomain error -1001")
    // kCFURLErrorTimedOut
    {
        return true;
    }
    // "operation timed out" is a weak signal — on
    // some provider stacks use it for server throttling errors'
    // localized description ("The request timed out. (HTTP 429)"),
    // which is an APPLICATION-level signal (server is throttling),
    // not a connectivity drop. Promote the match only when paired
    // with a transport-level locator (CFURL / NSURL / no-route /
    // POSIX timeout mnemonic, all of which are matched above and
    // returned early). On its own, treat it as a per-request hiccup
    // and let the transport's normal retry path handle it. The
    // false-positive UX cost (showing "network lost" for a
    // server-side rate-limit) is what we're fixing.
    false
}

/// The reactive decision helper: given a connection-level IO error, ask
/// the probe whether the upstream is still reachable. Returns
/// `Some(SyncError::NetworkDropped { .. })` when the probe reports
/// offline (caller should abort the cycle); returns `None` when the
/// probe says we're still online (caller should fall back to its
/// normal retry path — the original error was probably a per-request
/// hiccup, not a connectivity loss).
///
/// The helper is cheap — the probe's reachability check runs inline —
/// but it's only called on errors that already passed
/// [`looks_like_connection_drop`], so the amortized cost of a healthy
/// sync cycle (no drops) is zero.
pub fn classify_and_abort(
    original_message: &str,
    is_reachable: impl FnOnce() -> bool,
) -> Option<crate::error::SyncError> {
    if !looks_like_connection_drop(original_message) {
        return None;
    }
    if is_reachable() {
        // The error looked like a drop but the probe still gets
        // through — probably a single-connection hiccup. Let the
        // transport's normal retry logic handle it.
        return None;
    }
    Some(crate::error::SyncError::NetworkDropped {
        message: original_message.to_string(),
    })
}

#[cfg(test)]
mod tests;
