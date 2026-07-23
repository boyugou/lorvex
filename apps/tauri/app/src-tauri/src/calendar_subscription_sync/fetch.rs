//! HTTP fetcher for ICS feed bodies.
//!
//! Each subscription fetch builds a fresh
//! [`reqwest::blocking::Client`] with the resolved `SocketAddr`s pinned
//! onto the host. Pinning is what defeats DNS rebinding
//! the OS resolver is NOT consulted during the connect phase, so an
//! attacker-controlled TTL=0 domain can't return a different IP between
//! validation and connect. Auto-redirect is disabled — every 3xx hop
//! re-enters [`super::validation::validate_ics_url_safety`] with a fresh
//! pin, so an intermediate redirect to an internal IP cannot bypass
//! SSRF validation.
//!
//! Body reading enforces both a running size cap
//! ([`MAX_ICS_RESPONSE_BYTES`], 10 MB) and a mid-stream idle timeout
//! ([`ICS_READ_IDLE_TIMEOUT_SECS`]). The idle timeout
//! defeats trickle-feed denial: a hostile or malfunctioning server that
//! drips bytes one-per-second for 29.9s can't burn the full radio
//! budget; we abandon the wedged connection after 10s of zero-byte
//! progress.

use lorvex_workflow::calendar_subscription::sync::{FetchBackend, FetchedIcs, FetchedIcsError};
use lorvex_workflow::calendar_subscription::truncation::detect_ics_truncation;
use lorvex_workflow::calendar_subscription::validation::{
    sanitize_url_for_display, validate_ics_url_safety, DefaultHostResolver, HostResolver,
};

use super::errors::{IcsBodyReadError, IcsFetchError};
use crate::error::AppError;

/// [`FetchBackend`] impl wired into the workflow sync orchestrator.
///
/// Carries no state — every fetch builds a fresh
/// [`reqwest::blocking::Client`] with pinned `SocketAddr`s for the
/// resolved host (see [`fetch_ics_content`]). Constructed inline by
/// the Tauri IPC commands that drive the orchestrator.
pub(crate) struct TauriFetchBackend;

impl FetchBackend for TauriFetchBackend {
    fn fetch_ics(&self, url: &str, _etag: Option<&str>) -> Result<FetchedIcs, FetchedIcsError> {
        match fetch_ics_content(url) {
            Ok(body) => Ok(FetchedIcs {
                body,
                etag: None,
                status: 200,
            }),
            Err(IcsFetchError::RateLimited {
                retry_after_secs,
                safe_url,
            }) => Err(FetchedIcsError::RateLimited {
                retry_after_secs,
                safe_url,
            }),
            Err(IcsFetchError::Truncated { reason, safe_url }) => {
                Err(FetchedIcsError::Truncated { reason, safe_url })
            }
            Err(IcsFetchError::Other(err)) => Err(FetchedIcsError::Other(err.to_string())),
        }
    }
}

/// Maximum response body size for ICS feed fetching (10 MB).
const MAX_ICS_RESPONSE_BYTES: usize = 10 * 1024 * 1024;

/// Mid-stream idle timeout for ICS body reads.
///
/// The total `.timeout(30s)` budget covers the whole request, including
/// body read, but it only fires once the 30s has fully elapsed. On a
/// throttled cellular link a hostile or malfunctioning server can drip
/// bytes one-per-second for 29.9s and only trip the total timeout at
/// the very end — wasting 30s of radio wake + battery on a response
/// that was never going to arrive in time. The per-read timeout
/// (plumbed through `reqwest::ClientBuilder::read_timeout`, which maps
/// to the socket-level `SO_RCVTIMEO` on the blocking client) fires
/// when a single read operation returns no bytes within the window —
/// i.e. "we've been idle waiting for more data this long." 10s is
/// short enough to abandon a wedged connection promptly, long enough
/// that a legitimate backend GC pause or transient network hiccup
/// doesn't trip it.
const ICS_READ_IDLE_TIMEOUT_SECS: u64 = 10;

/// Shared User-Agent for subscription fetches. Built from the package
/// version at compile time rather than a hardcoded
/// literal so providers + our own log-trawlers can pin which build
/// emitted a request. Includes a contact URL per RFC 9110 §10.1.5.
const SUBSCRIPTION_USER_AGENT: &str = concat!(
    "Lorvex/",
    env!("CARGO_PKG_VERSION"),
    " (+https://github.com/boyugou/ai-native-todo) Calendar Subscription"
);

/// Maximum number of HTTP redirects to follow before giving up. Kept
/// at 5 to match the prior `Policy::limited(5)` auto-redirect cap.
const MAX_REDIRECTS: u8 = 5;

/// Build a fresh `reqwest::blocking::Client` for a single redirect hop,
/// with the resolved `SocketAddr`s pinned onto the host via
/// `ClientBuilder::resolve`. Pinning is what defeats DNS rebinding:
/// the OS resolver is NOT consulted during the connect phase, so an
/// attacker-controlled TTL=0 domain can't return a different IP
/// between validation and connect.
///
/// The client has auto-redirect DISABLED because the caller handles
/// redirect-follow manually; each 3xx hop is re-validated + has a
/// fresh client built with a fresh pin, so that intermediate hops
/// can't bypass SSRF validation.
fn build_pinned_fetch_client(
    current: &reqwest::Url,
    resolved: &[std::net::SocketAddr],
) -> reqwest::Result<reqwest::blocking::Client> {
    let mut builder = reqwest::blocking::Client::builder()
        // without an explicit connect_timeout, the
        // total `.timeout(30s)` budget would be burned by the TCP
        // SYN phase alone on unresponsive hosts, leaving ~0s for
        // the body read and poisoning `last_error` with a
        // misleading "read timeout" message. Give the handshake a
        // bounded slice so body read has its own ceiling.
        .connect_timeout(std::time::Duration::from_secs(10))
        .timeout(std::time::Duration::from_secs(30))
        // disable auto-redirect. The caller manually
        // follows 3xx responses so each hop goes through the full
        // validate + DNS-resolve + pin pipeline. Without this, a
        // redirect to an internal IP would never re-enter
        // `validate_ics_url_safety`.
        .redirect(reqwest::redirect::Policy::none())
        .user_agent(SUBSCRIPTION_USER_AGENT);

    // honor HTTPS_PROXY / HTTP_PROXY / ALL_PROXY / NO_PROXY
    // explicitly. reqwest's implicit `Proxy::system()` path is Unix-only
    // and snapshots env vars once per process, so corporate users on
    // Windows — or users who export the proxy after the first fetch
    // warms a client — never see it applied. Routing through the
    // dedicated helper makes the wiring testable and uniform with the
    // updater client.
    builder = crate::proxy_env::apply_proxy_from_env(builder);

    // Pin the resolved addresses for the current host. `resolved` is
    // empty when the URL used a literal IP — reqwest already knows
    // how to dial those directly, so there's nothing to pin. If the
    // resolver returned multiple answers (e.g. A + AAAA, or
    // geo-distributed CDN edges) we pin the first one to eliminate
    // any remaining race; every entry was already approved by
    // `validate_ics_url_safety`, so ordering is a performance choice,
    // not a safety one.
    if let (Some(url::Host::Domain(host)), Some(sock)) = (current.host(), resolved.first()) {
        builder = builder.resolve(host, *sock);
    }

    builder.build()
}

/// Read the body from `source` into a byte vector, enforcing a
/// running size cap. Stops and returns `SizeCapExceeded` the instant
/// the total bytes-read would exceed `limit`, so a server streaming
/// gigabytes of garbage never pins more than `limit + 8 KiB` in
/// memory. Propagates I/O errors via `IcsBodyReadError::Io`.
///
/// This flavour is synchronous and does NOT enforce an idle
/// timeout — the caller is responsible for supplying a `Read` whose
/// own socket-level timeouts bound the wait per read. It's intended
/// for the unit-test path (synthetic in-memory streams) and as a
/// reference primitive; production reads all go through
/// `read_body_capped_with_idle_timeout`.
#[cfg(test)]
pub(crate) fn read_body_capped<R: std::io::Read>(
    source: R,
    limit: usize,
) -> Result<Vec<u8>, IcsBodyReadError> {
    // Read one byte past the limit so we can distinguish "exactly
    // `limit` bytes, still valid" from "more than `limit` bytes, cap
    // exceeded." Without the `+ 1` a feed that landed exactly on the
    // boundary would be rejected.
    let mut bounded = source.take(limit as u64 + 1);
    let mut buf: Vec<u8> = Vec::new();
    std::io::Read::read_to_end(&mut bounded, &mut buf).map_err(IcsBodyReadError::Io)?;
    if buf.len() > limit {
        return Err(IcsBodyReadError::SizeCapExceeded { limit });
    }
    Ok(buf)
}

/// Read the body with both a size cap AND a mid-stream idle timeout.
///
/// The blocking `reqwest::Response` only exposes the total
/// `.timeout()` configured at the client level — there's no
/// per-read / per-chunk configuration surface. To enforce "no
/// progress for `idle_window` seconds", we delegate the actual read
/// loop to a worker thread that pushes chunks into a bounded mpsc
/// channel. The caller thread waits on `recv_timeout(idle_window)`;
/// if that fires we abandon the worker and return an `IdleTimeout`
/// error immediately. The orphaned worker eventually exits when the
/// underlying client's total timeout fires (no later than the total
/// `.timeout()` configured on `build_pinned_fetch_client`), so there
/// is no unbounded thread leak.
///
/// The size cap is enforced on the caller side (aggregated from
/// received chunks), which keeps the cap honest even if the worker
/// races ahead faster than we consume from the channel.
pub(super) fn read_body_capped_with_idle_timeout<R>(
    source: R,
    limit: usize,
    idle_window: std::time::Duration,
) -> Result<Vec<u8>, IcsBodyReadError>
where
    R: std::io::Read + Send + 'static,
{
    use std::sync::mpsc;

    // Worker thread streams chunks across the channel. 8 KiB buffers
    // match reqwest's internal chunking and balance per-read syscall
    // cost against memory usage.
    enum WorkerMsg {
        Chunk(Vec<u8>),
        Err(std::io::Error),
        Done,
    }

    let (tx, rx) = mpsc::sync_channel::<WorkerMsg>(4);
    std::thread::spawn(move || {
        let mut source = source;
        // Pre-size the per-iteration buffer once and hand its full
        // backing allocation to the channel via `mem::take`. Reuses the
        // same `Vec<u8>` across the loop and only allocates when the
        // previous one has been consumed by the receiver — avoids the
        // per-chunk `buf[..n].to_vec()` alloc + memcpy that would cost
        // ~128 heap allocs and ~1 MiB of copy on a sustained 1 MiB feed.
        const CHUNK_CAPACITY: usize = 8 * 1024;
        let mut buf: Vec<u8> = vec![0u8; CHUNK_CAPACITY];
        loop {
            match std::io::Read::read(&mut source, &mut buf) {
                Ok(0) => {
                    let _ = tx.send(WorkerMsg::Done);
                    return;
                }
                Ok(n) => {
                    // Truncate to the bytes actually read, hand the
                    // backing allocation to the channel, then
                    // re-allocate a fresh buffer of the same capacity
                    // for the next read. The `truncate` is O(n) only
                    // for non-Drop element types; `u8` is `Copy`, so
                    // it's a constant-time length write.
                    buf.truncate(n);
                    let chunk = std::mem::take(&mut buf);
                    if tx.send(WorkerMsg::Chunk(chunk)).is_err() {
                        // Caller gave up (idle timeout or cap hit) —
                        // stop reading; the underlying connection
                        // drops when `source` goes out of scope at
                        // thread exit.
                        return;
                    }
                    buf = vec![0u8; CHUNK_CAPACITY];
                }
                Err(e) => {
                    let _ = tx.send(WorkerMsg::Err(e));
                    return;
                }
            }
        }
    });

    let mut out: Vec<u8> = Vec::new();
    loop {
        match rx.recv_timeout(idle_window) {
            Ok(WorkerMsg::Chunk(chunk)) => {
                if out.len().saturating_add(chunk.len()) > limit {
                    return Err(IcsBodyReadError::SizeCapExceeded { limit });
                }
                out.extend_from_slice(&chunk);
            }
            Ok(WorkerMsg::Done) => return Ok(out),
            Ok(WorkerMsg::Err(e)) => return Err(IcsBodyReadError::Io(e)),
            Err(mpsc::RecvTimeoutError::Timeout) => {
                return Err(IcsBodyReadError::IdleTimeout {
                    window_secs: idle_window.as_secs(),
                });
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                // Worker dropped the sender without signalling Done
                // — treat as a clean EOF. In practice the worker
                // always sends `Done` before returning, so this arm
                // is defensive rather than expected.
                return Ok(out);
            }
        }
    }
}

pub(super) fn fetch_ics_content(url: &str) -> Result<String, IcsFetchError> {
    fetch_ics_content_with_resolver(url, &DefaultHostResolver)
}

/// Internal implementation of `fetch_ics_content` that takes an
/// explicit `HostResolver` so unit tests can exercise the
/// DNS-rebinding defenses without touching the network.
fn fetch_ics_content_with_resolver(
    url: &str,
    resolver: &dyn HostResolver,
) -> Result<String, IcsFetchError> {
    let safe_url = sanitize_url_for_display(url);
    let mut current = reqwest::Url::parse(url).map_err(|e| {
        AppError::Validation(format!("Invalid calendar subscription URL {safe_url}: {e}"))
    })?;

    // manual redirect follow. Auto-redirect via reqwest's
    // `Policy::limited(N)` would let an intermediate redirect hop
    // bypass SSRF validation — only the final URL was re-checked,
    // and reqwest had already connected through every intermediate
    // Location. We now validate + resolve every hop, build a client
    // that pins the resolved IP for THAT hop, and follow 3xx
    // responses ourselves.
    let mut redirects_followed: u8 = 0;
    let response = loop {
        let resolved = validate_ics_url_safety(&current, resolver)?;
        let client = build_pinned_fetch_client(&current, &resolved)
            .map_err(|e| AppError::Internal(format!("Failed to initialize HTTP client: {e}")))?;
        let response = client
            .get(current.clone())
            .send()
            .map_err(|e| AppError::Internal(format!("Failed to fetch .ics: {e}")))?;

        let status = response.status();
        if status.is_redirection() {
            if redirects_followed >= MAX_REDIRECTS {
                return Err(IcsFetchError::Other(AppError::Internal(format!(
                    "Too many redirects while fetching calendar feed: {safe_url}"
                ))));
            }
            let location = response
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|v| v.to_str().ok())
                .map(std::string::ToString::to_string);
            let Some(location) = location else {
                // 3xx without a Location header — treat as a normal
                // (non-redirect) response and fall through so the
                // status-code branch below produces a meaningful error.
                break response;
            };
            // #3053 M17: bound the Location header to printable ASCII
            // and a sane length BEFORE handing it to `Url::join`. A
            // hostile feed can emit megabyte-long mojibake here that
            // `url::Url::parse` will happily allocate; bail fast.
            const MAX_LOCATION_HEADER_BYTES: usize = 8 * 1024;
            if location.len() > MAX_LOCATION_HEADER_BYTES {
                return Err(IcsFetchError::Other(AppError::Validation(format!(
                    "Calendar subscription redirect Location header is too long ({} bytes > {} bytes)",
                    location.len(),
                    MAX_LOCATION_HEADER_BYTES,
                ))));
            }
            if !location.bytes().all(|b| b.is_ascii_graphic() || b == b' ') {
                return Err(IcsFetchError::Other(AppError::Validation(
                    "Calendar subscription redirect Location header contains non-printable bytes"
                        .to_string(),
                )));
            }
            let next = current.join(&location).map_err(|e| {
                AppError::Validation(format!(
                    "Calendar subscription redirect target is not a valid URL ({location}): {e}"
                ))
            })?;
            // #3053 M14: gate the JOINED URL on http(s) BEFORE
            // re-running SSRF validation. `current.join("/etc/passwd")`
            // can yield a `file:` scheme when the base URL was
            // weird, and the SSRF check assumes a remote scheme up
            // front. Refuse anything not http/https here.
            if !matches!(next.scheme(), "http" | "https") {
                return Err(IcsFetchError::Other(AppError::Validation(format!(
                    "Calendar subscription redirect target rejected: scheme `{}` is not http/https",
                    next.scheme(),
                ))));
            }
            current = next;
            redirects_followed += 1;
            continue;
        }
        break response;
    };

    if !response.status().is_success() {
        // 429 Too Many Requests: parse Retry-After and surface a
        // distinct, actionable error so the caller can distinguish "be
        // patient" from "the feed is broken" and back off without
        // poisoning the feed's error state as permanent. Retry-After
        // per RFC 9110 is either a seconds integer or an HTTP-date; we
        // only decode the seconds form because that's what major
        // public calendar providers (Google, Outlook public .ics,
        // iCloud published calendars) actually emit.
        if response.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
            let retry_after_secs = response
                .headers()
                .get(reqwest::header::RETRY_AFTER)
                .and_then(|v| v.to_str().ok())
                .and_then(|s| s.trim().parse::<u64>().ok());
            return Err(IcsFetchError::RateLimited {
                retry_after_secs,
                safe_url,
            });
        }
        return Err(IcsFetchError::Other(AppError::Internal(format!(
            "HTTP {}: {}",
            response.status(),
            safe_url
        ))));
    }

    // Captive-portal detection: hotel / coffee-shop Wi-Fi often returns an
    // HTML login page with HTTP 200 instead of the requested resource.
    // Without this check the generic "not a valid iCalendar file" error
    // below gets persisted to `last_error` and the feed shows a permanent
    // red indicator until the user looks at the URL manually. The
    // content-type signal is cheap and distinguishes the two cases so
    // callers can surface a "Check your network" hint instead of
    // poisoning the subscription's error state.
    let content_type = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_ascii_lowercase();
    if content_type.starts_with("text/html") || content_type.starts_with("application/xhtml") {
        return Err(IcsFetchError::Other(AppError::Validation(format!(
            "Expected an .ics file but got HTML from {safe_url}. You may be behind a captive-portal (hotel/coffee-shop) login — sign in, then try again."
        ))));
    }

    // Enforce response body size limit to prevent memory exhaustion from
    // malicious or oversized feeds.
    let content_length = response.content_length().unwrap_or(0) as usize;
    if content_length > MAX_ICS_RESPONSE_BYTES {
        return Err(IcsFetchError::Other(AppError::Validation(format!(
            "Calendar feed exceeds maximum size ({content_length} bytes > {MAX_ICS_RESPONSE_BYTES} bytes)"
        ))));
    }

    // Stream the response body with a running size cap so a server that
    // omits/falsifies Content-Length (or uses chunked encoding with no
    // declared length) cannot stream gigabytes into memory before the
    // post-read size check runs.
    //
    // the body read is wrapped in a mid-stream idle
    // timeout. `reqwest::blocking::ClientBuilder` only exposes a
    // total `.timeout(30s)`, which doesn't fire until the full 30s
    // has elapsed — a throttled link trickling one byte per second
    // would burn 30s of radio + battery before aborting. We track
    // time-between-progress on the caller thread via a worker + mpsc
    // channel and bail out after `ICS_READ_IDLE_TIMEOUT_SECS` of
    // silence, even though the total timeout still has budget left.
    let bytes = read_body_capped_with_idle_timeout(
        response,
        MAX_ICS_RESPONSE_BYTES,
        std::time::Duration::from_secs(ICS_READ_IDLE_TIMEOUT_SECS),
    )
    .map_err(|err| IcsFetchError::Other(err.into_app_error(&safe_url)))?;

    // #3053 M2: avoid the `String::from_utf8_lossy(&bytes).into_owned()`
    // double-allocation that doubled peak RAM on every fetch. If the
    // bytes are already valid UTF-8 (the overwhelmingly common case
    // for .ics feeds), reuse the buffer in place via
    // `String::from_utf8` — zero copies. Only on the rare invalid-
    // UTF-8 path do we fall through to the lossy substitution, which
    // still has to allocate a new buffer because it is replacing
    // bytes with the U+FFFD replacement codepoint. Either way we
    // never hold both copies of the body simultaneously.
    let body = match String::from_utf8(bytes) {
        Ok(s) => s,
        Err(error) => String::from_utf8_lossy(error.as_bytes()).into_owned(),
    };

    // Basic validation
    if !body.contains("BEGIN:VCALENDAR") {
        // Content-Type alone misses captive portals that
        // serve application/json (cloud gateways), text/plain (some
        // enterprise Wi-Fi), or empty/unset content-type with a
        // HTML-ish redirect body. Peek the first KB of the response
        // for signals before attributing the failure to a bad feed —
        // otherwise every subscription shows a permanent red error
        // indicator when the real cause is "Wi-Fi needs sign-in."
        if looks_like_captive_portal_body(&body) {
            return Err(IcsFetchError::Other(AppError::Validation(format!(
                "Expected an .ics file but got what looks like a captive-portal / sign-in page from {safe_url}. If you're on hotel or coffee-shop Wi-Fi, sign in and try again."
            ))));
        }
        return Err(IcsFetchError::Other(AppError::Validation(
            "Response is not a valid iCalendar file".to_string(),
        )));
    }

    // the size-cap reader (#2439) and server-side stream
    // cut-offs can deliver a body that *starts* like an iCalendar file
    // (`BEGIN:VCALENDAR` present above) yet stops mid-stream, leaving a
    // VEVENT open or omitting the `END:VCALENDAR` terminator. The
    // downstream parser is gated on `END:VEVENT` / `END:VCALENDAR`, so
    // every truncated event vanishes silently and the subscription's
    // cached state gets clobbered on the next diff-delete pass. Reject
    // truncated payloads with a dedicated error variant so the caller
    // can preserve the cache and let the retry scheduler pick it up on
    // the next poll.
    if let Err(reason) = detect_ics_truncation(&body) {
        return Err(IcsFetchError::Truncated { reason, safe_url });
    }

    Ok(body)
}

/// captive-portal body-sniff. Called AFTER the `BEGIN:VCALENDAR`
/// check fails, so we only run this heuristic when the response is already
/// known not to be valid iCalendar. Looks at the first ~1 KB (post-trim)
/// for markers that indicate a Wi-Fi sign-in page rather than a malformed
/// feed:
///
/// - Any HTML opener (`<html`, `<!doctype`) — captive portals that don't
///   declare `Content-Type: text/html` are still usually HTML.
/// - Sign-in / portal lexical cues (`captive`, `login`, `portal`,
///   `sign in`, `sign_in`).
/// - A `Location:` header line in a plain-text body — some enterprise
///   gateways return a 200 with a redirect-style body.
pub(crate) fn looks_like_captive_portal_body(body: &str) -> bool {
    // Limit the probe window so a 20 MB valid-but-non-VCALENDAR payload
    // doesn't spend measurable time in `to_ascii_lowercase`.
    let probe_upper = body
        .char_indices()
        .take(1024)
        .last()
        .map_or(0, |(idx, ch)| idx + ch.len_utf8());
    let probe = body[..probe_upper].trim_start().to_ascii_lowercase();
    const MARKERS: &[&str] = &[
        "<html",
        "<!doctype",
        "captive",
        "portal",
        "login",
        "sign in",
        "sign_in",
        "location:",
    ];
    MARKERS.iter().any(|m| probe.contains(m))
}
