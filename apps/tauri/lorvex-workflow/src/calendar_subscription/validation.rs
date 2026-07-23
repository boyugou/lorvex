//! URL safety + IP-denylist + DNS-rebinding defense.
//!
//! Subscription URLs are an untrusted input boundary. Before any HTTP
//! connection is opened we:
//!
//! 1. Sanitize URLs for display so error logs cannot leak bearer-style
//!    tokens carried in `?token=...` query strings (iCloud, Google,
//!    Outlook published URLs).
//! 2. Reject literal-IP URLs that point at loopback / link-local /
//!    private / cloud-metadata addresses
//!    ([`is_denied_ipv4`] / [`is_denied_ipv6`]).
//! 3. Reject domain hostnames that match a hard-coded local-network
//!    denylist (`localhost`, `*.local`, `host.docker.internal`,
//!    `metadata.google.internal`).
//! 4. DNS-resolve domain hostnames via [`HostResolver`]
//!    and reject the URL if ANY resolved address falls in a denied
//!    range. The resolved addresses are returned so the caller can
//!    pin them onto the HTTP client (`reqwest::Client::builder().resolve(...)`)
//!    to defeat DNS-rebinding races between validation and connect.

use super::error::CalendarSubscriptionError;

type Result<T> = std::result::Result<T, CalendarSubscriptionError>;

/// Return a URL with any query string and userinfo stripped, suitable
/// for interpolation into user-visible error messages. Published
/// calendar URLs (iCloud, Google, Outlook) carry bearer-equivalent
/// tokens in the query string (`?token=…`, `?calrenderkey=…`); those
/// survive verbatim in `error_logs` and `last_error` diagnostics
/// unless stripped at the source. If the URL fails to parse, fall
/// back to a generic placeholder rather than echoing the raw string.
pub fn sanitize_url_for_display(raw: &str) -> String {
    match reqwest::Url::parse(raw) {
        Ok(mut url) => {
            url.set_query(None);
            let _ = url.set_password(None);
            let _ = url.set_username("");
            url.set_fragment(None);
            url.to_string()
        }
        Err(_) => "<unparseable URL>".to_string(),
    }
}

/// Cloud-metadata IPv4 literals that are NOT caught by
/// `Ipv4Addr::is_link_local()` / `is_private()` etc. on their own but
/// are well-known SSRF targets and must be blocked explicitly.
///
/// - `169.254.169.254` — AWS / Azure / DigitalOcean / Oracle Cloud IMDS
///   (also inside the 169.254.0.0/16 link-local range, but we name it
///   explicitly for documentation + defense-in-depth clarity).
/// - `100.100.100.200` — Alibaba Cloud IMDS (public IP space, not
///   caught by any stdlib predicate; must be an explicit literal).
const CLOUD_METADATA_IPV4: &[std::net::Ipv4Addr] = &[
    std::net::Ipv4Addr::new(169, 254, 169, 254),
    std::net::Ipv4Addr::new(100, 100, 100, 200),
];

/// Return true if an IPv4 address must not be reached by a calendar
/// subscription fetch. Shared between the literal-IP URL path and the
/// DNS-resolution path so A-records pointing at e.g. `10.0.0.1` get
/// rejected with exactly the same predicate as the string literal.
pub fn is_denied_ipv4(addr: std::net::Ipv4Addr) -> bool {
    if addr.is_loopback()
        || addr.is_private()
        || addr.is_link_local()
        || addr.is_broadcast()
        || addr.is_unspecified()
        || addr.is_documentation()
        // 100.64.0.0/10 CGNAT (shared address space, RFC 6598).
        || (addr.octets()[0] == 100 && (addr.octets()[1] & 0xc0) == 64)
        // Multicast + reserved (class D/E), also 240.0.0.0/4.
        || addr.octets()[0] >= 224
    {
        return true;
    }
    // Explicit cloud-metadata IPs (defense in depth; 169.254.169.254
    // is already rejected by is_link_local(), but 100.100.100.200 is
    // in public IP space and is not caught by any stdlib predicate).
    CLOUD_METADATA_IPV4.contains(&addr)
}

/// Return true if an IPv6 address must not be reached by a calendar
/// subscription fetch. Mirror of `is_denied_ipv4` for the v6 path.
pub fn is_denied_ipv6(addr: std::net::Ipv6Addr) -> bool {
    if addr.is_loopback()
        || addr.is_unspecified()
        || addr.is_multicast()
        // ULA fc00::/7
        || addr.segments()[0] & 0xfe00 == 0xfc00
        // Link-local fe80::/10
        || addr.segments()[0] & 0xffc0 == 0xfe80
    {
        return true;
    }
    // IPv4-mapped IPv6 `::ffff:x.x.x.x` — validate the embedded v4.
    if let Some(v4) = addr.to_ipv4_mapped() {
        return is_denied_ipv4(v4);
    }
    false
}

/// Check a resolved `IpAddr` (from DNS or literal) against the denied
/// ranges. Thin dispatch over `is_denied_ipv4` / `is_denied_ipv6`.
pub fn is_denied_ip(addr: std::net::IpAddr) -> bool {
    match addr {
        std::net::IpAddr::V4(v4) => is_denied_ipv4(v4),
        std::net::IpAddr::V6(v6) => is_denied_ipv6(v6),
    }
}

/// Abstraction over host-to-IP resolution so tests can inject a fake
/// resolver and assert DNS-rebinding defenses without touching the
/// network. Production uses `DefaultHostResolver`, which delegates to
/// `ToSocketAddrs`.
pub trait HostResolver {
    /// Resolve `host:port` to the concrete `SocketAddr`s the OS would
    /// connect to. Must return at least one address on success.
    fn resolve(&self, host: &str, port: u16) -> std::io::Result<Vec<std::net::SocketAddr>>;
}

/// Production resolver — synchronous, uses the OS resolver via
/// `ToSocketAddrs`. Matches the resolver path taken by `reqwest` when
/// no custom DNS is configured.
pub struct DefaultHostResolver;

impl HostResolver for DefaultHostResolver {
    fn resolve(&self, host: &str, port: u16) -> std::io::Result<Vec<std::net::SocketAddr>> {
        use std::net::ToSocketAddrs;
        let addrs: Vec<_> = (host, port).to_socket_addrs()?.collect();
        Ok(addrs)
    }
}

/// Reject URLs that resolve to loopback, link-local, private, or otherwise
/// unsafe addresses. Applied to both the initial URL (before any request is
/// sent) and the final URL after redirects, because a string-prefix host
/// check alone was bypassable by decimal/octal/hex IP literals, IPv6
/// loopback (`[::1]`), IPv4-mapped IPv6 (`::ffff:127.0.0.1`), `*.local`
/// mDNS names, and `host.docker.internal`.
///
/// domain hosts are now DNS-resolved via the supplied
/// `HostResolver`, and every resolved address is checked against the
/// private-range predicates. The resolved addresses are returned so the
/// caller can pin them onto the HTTP client (via
/// `reqwest::Client::builder().resolve(...)`) to defeat DNS-rebinding
/// races between validation and connect. An empty vector is returned
/// for literal-IP URLs — reqwest already knows how to dial those.
pub fn validate_ics_url_safety(
    url: &reqwest::Url,
    resolver: &dyn HostResolver,
) -> Result<Vec<std::net::SocketAddr>> {
    // only https:// is accepted. Plaintext
    // http:// would leak the feed URL (often a bearer-equivalent token
    // in the path or query string), the response body, and the device's
    // browsing pattern to anyone on the network path. The
    // proxy_env helper still honors HTTP_PROXY at the transport layer
    // for legitimate corporate-proxy setups (the proxy hop itself can
    // be HTTP-only), but we no longer let the user-supplied calendar
    // URL itself be plaintext.
    if url.scheme() != "https" {
        return Err(CalendarSubscriptionError::Validation(format!(
            "Calendar subscription URL must use https:// scheme: {url}"
        )));
    }
    let host = url.host().ok_or_else(|| {
        CalendarSubscriptionError::Validation(format!(
            "Calendar subscription URL missing host: {url}"
        ))
    })?;
    match host {
        url::Host::Ipv4(addr) => {
            if is_denied_ipv4(addr) {
                return Err(CalendarSubscriptionError::Validation(format!(
                    "This calendar URL points at a private or local-network address ({url}), which Lorvex doesn't fetch for security reasons. Use a public https:// URL."
                )));
            }
            Ok(Vec::new())
        }
        url::Host::Ipv6(addr) => {
            if is_denied_ipv6(addr) {
                return Err(CalendarSubscriptionError::Validation(format!(
                    "This calendar URL points at a private or local-network address ({url}), which Lorvex doesn't fetch for security reasons. Use a public https:// URL."
                )));
            }
            Ok(Vec::new())
        }
        url::Host::Domain(name) => {
            let lowered = name.to_ascii_lowercase();
            // Block common containment-breaking hostnames up-front so
            // an attacker can't even reach the DNS resolver path with
            // them. `metadata.google.internal` resolves to
            // 169.254.169.254 in a GCE VM — the resolver path would
            // also reject it, but explicit string-level rejection
            // surfaces a clearer error.
            if lowered == "localhost"
                || lowered.ends_with(".localhost")
                || lowered.ends_with(".local")
                || lowered == "host.docker.internal"
                || lowered == "metadata.google.internal"
            {
                return Err(CalendarSubscriptionError::Validation(format!(
                    "This calendar URL points at a local-network or private hostname ({url}). Use a public https:// URL that's reachable from the internet."
                )));
            }

            // DNS-rebinding / A-record-to-internal defense.
            // The string checks above block only a hard-coded denylist;
            // a domain like `good.example.com` with an A-record pointing
            // at `10.0.0.1` (or `169.254.169.254`, or a TTL=0 record
            // that flips on the second lookup) would sail through
            // validation and hit the internal endpoint at connect time.
            // Resolve now, reject if ANY answer is in a denied range,
            // and return the resolved `SocketAddr`s so the caller can
            // pin them onto the HTTP client for the connect phase —
            // preventing the OS resolver from returning a different IP
            // between validation and connect.
            let port = url.port_or_known_default().ok_or_else(|| {
                CalendarSubscriptionError::Validation(format!(
                    "Calendar subscription URL missing a usable port: {url}"
                ))
            })?;
            let resolved = resolver.resolve(&lowered, port).map_err(|e| {
                CalendarSubscriptionError::Validation(format!(
                    "Failed to resolve calendar subscription host ({url}): {e}"
                ))
            })?;
            if resolved.is_empty() {
                return Err(CalendarSubscriptionError::Validation(format!(
                    "Calendar subscription host resolved to no addresses: {url}"
                )));
            }
            for sock in &resolved {
                if is_denied_ip(sock.ip()) {
                    return Err(CalendarSubscriptionError::Validation(format!(
                        "This calendar URL ({url}) resolves to a private or local-network address ({}), which Lorvex doesn't fetch for security reasons. Use a public https:// URL.",
                        sock.ip()
                    )));
                }
            }
            Ok(resolved)
        }
    }
}
