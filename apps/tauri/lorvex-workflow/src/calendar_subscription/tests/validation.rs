use super::super::validation::{validate_ics_url_safety, HostResolver};

// -----------------------------------------------------------------------
// SSRF / DNS-rebinding defenses
// -----------------------------------------------------------------------

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

/// Test-only resolver that returns a fixed answer for a given
/// host, letting us assert that a domain A-record pointing at an
/// internal address is rejected by `validate_ics_url_safety`
/// without touching the network.
struct FakeResolver {
    host: String,
    addrs: Vec<SocketAddr>,
}

impl HostResolver for FakeResolver {
    fn resolve(&self, host: &str, port: u16) -> std::io::Result<Vec<SocketAddr>> {
        if host.eq_ignore_ascii_case(&self.host) {
            // Preserve the port the URL is asking for so the
            // assertion actually mirrors what reqwest would pin.
            let answers: Vec<SocketAddr> = self
                .addrs
                .iter()
                .map(|s| SocketAddr::new(s.ip(), port))
                .collect();
            Ok(answers)
        } else {
            Err(std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("unexpected host lookup: {host}"),
            ))
        }
    }
}

fn parsed(url: &str) -> reqwest::Url {
    reqwest::Url::parse(url).expect("test URL must parse")
}

#[test]
fn validate_ics_url_rejects_domain_resolving_to_private_range() {
    // Pre-a domain like `good-calendar.example.com`
    // with a plain A-record to `10.0.0.1` passed the string-only
    // denylist and the subsequent connect hit the internal
    // endpoint. Post-fix: the resolver path runs the same
    // predicate as literal-IP hosts and rejects this.
    let resolver = FakeResolver {
        host: "good-calendar.example.com".to_string(),
        addrs: vec![SocketAddr::new(IpAddr::V4(Ipv4Addr::new(10, 0, 0, 1)), 443)],
    };
    let err = validate_ics_url_safety(
        &parsed("https://good-calendar.example.com/feed.ics"),
        &resolver,
    )
    .expect_err("should reject domain resolving to RFC1918 10/8");
    let msg = format!("{err}");
    assert!(
        msg.contains("private or local-network"),
        "expected SSRF rejection, got: {msg}"
    );
}

#[test]
fn validate_ics_url_rejects_domain_resolving_to_169_254_169_254() {
    // Cloud-metadata rebinding: attacker hosts `meta.evil.example`
    // that resolves to the AWS IMDS address. Must be rejected by
    // the same code path that rejects a literal URL of
    // `https://169.254.169.254/`.
    let resolver = FakeResolver {
        host: "meta.evil.example".to_string(),
        addrs: vec![SocketAddr::new(
            IpAddr::V4(Ipv4Addr::new(169, 254, 169, 254)),
            443,
        )],
    };
    let err = validate_ics_url_safety(&parsed("https://meta.evil.example/feed.ics"), &resolver)
        .expect_err("should reject AWS/Azure IMDS rebind");
    let msg = format!("{err}");
    assert!(
        msg.contains("private or local-network"),
        "expected SSRF rejection, got: {msg}"
    );
}

#[test]
fn validate_ics_url_rejects_domain_resolving_to_alibaba_metadata() {
    // 100.100.100.200 is in PUBLIC IP space — no stdlib
    // predicate catches it. The explicit cloud-metadata list in
    // `is_denied_ipv4` must reject it.
    let resolver = FakeResolver {
        host: "meta.alicloud.example".to_string(),
        addrs: vec![SocketAddr::new(
            IpAddr::V4(Ipv4Addr::new(100, 100, 100, 200)),
            443,
        )],
    };
    let err = validate_ics_url_safety(&parsed("https://meta.alicloud.example/feed.ics"), &resolver)
        .expect_err("should reject Alibaba IMDS literal");
    let msg = format!("{err}");
    assert!(
        msg.contains("private or local-network"),
        "expected SSRF rejection, got: {msg}"
    );
}

#[test]
fn validate_ics_url_rejects_domain_resolving_to_ipv6_ula() {
    // IPv6 Unique Local Addresses (fc00::/7) are the v6
    // equivalent of RFC1918. A resolver answer in this range
    // must be rejected alongside v4 private ranges.
    let ula: Ipv6Addr = "fc00::1".parse().unwrap();
    let resolver = FakeResolver {
        host: "v6-internal.example".to_string(),
        addrs: vec![SocketAddr::new(IpAddr::V6(ula), 443)],
    };
    let err = validate_ics_url_safety(&parsed("https://v6-internal.example/feed.ics"), &resolver)
        .expect_err("should reject IPv6 ULA");
    let msg = format!("{err}");
    assert!(
        msg.contains("private or local-network"),
        "expected SSRF rejection, got: {msg}"
    );
}

#[test]
fn validate_ics_url_rejects_ipv4_mapped_ipv6_loopback() {
    // ::ffff:127.0.0.1 — IPv4-mapped IPv6 loopback. Must be
    // rejected via the embedded-v4 unwrap in `is_denied_ipv6`,
    // both for literal hosts and for resolver answers.
    let mapped: Ipv6Addr = "::ffff:127.0.0.1".parse().unwrap();
    let resolver = FakeResolver {
        host: "trojan.example".to_string(),
        addrs: vec![SocketAddr::new(IpAddr::V6(mapped), 443)],
    };
    let err = validate_ics_url_safety(&parsed("https://trojan.example/feed.ics"), &resolver)
        .expect_err("should reject ipv4-mapped ipv6 loopback");
    let msg = format!("{err}");
    assert!(
        msg.contains("private or local-network"),
        "expected SSRF rejection, got: {msg}"
    );
}

#[test]
fn validate_ics_url_passes_domain_resolving_to_public_ip() {
    // Positive case: a public A-record should pass and the
    // returned `SocketAddr`s are what the caller pins onto the
    // reqwest client via `.resolve()`.
    let resolver = FakeResolver {
        host: "calendar.google.com".to_string(),
        addrs: vec![SocketAddr::new(
            IpAddr::V4(Ipv4Addr::new(142, 251, 32, 78)),
            443,
        )],
    };
    let resolved =
        validate_ics_url_safety(&parsed("https://calendar.google.com/feed.ics"), &resolver)
            .expect("public A-record must pass");
    assert_eq!(resolved.len(), 1);
    assert_eq!(
        resolved[0].ip(),
        IpAddr::V4(Ipv4Addr::new(142, 251, 32, 78))
    );
    assert_eq!(resolved[0].port(), 443);
}

#[test]
fn validate_ics_url_rejects_mixed_public_and_private_answer() {
    // If ANY resolved address is denied, the whole lookup is
    // rejected — otherwise an attacker could pair one public IP
    // with one internal IP and hope reqwest dials the private
    // entry. The "any in denied range" predicate closes that.
    let resolver = FakeResolver {
        host: "split-horizon.example".to_string(),
        addrs: vec![
            SocketAddr::new(IpAddr::V4(Ipv4Addr::new(8, 8, 8, 8)), 443),
            SocketAddr::new(IpAddr::V4(Ipv4Addr::new(10, 0, 0, 5)), 443),
        ],
    };
    let err = validate_ics_url_safety(&parsed("https://split-horizon.example/feed.ics"), &resolver)
        .expect_err("any-in-denied-range must reject the whole lookup");
    let msg = format!("{err}");
    assert!(
        msg.contains("private or local-network"),
        "expected SSRF rejection, got: {msg}"
    );
}

#[test]
fn validate_ics_url_rejects_empty_resolver_answer() {
    // A resolver that returns zero addresses is a misconfigured
    // lookup, not a green light. Must fail closed.
    let resolver = FakeResolver {
        host: "empty.example".to_string(),
        addrs: vec![],
    };
    let err = validate_ics_url_safety(&parsed("https://empty.example/feed.ics"), &resolver)
        .expect_err("empty resolver answer must fail closed");
    let msg = format!("{err}");
    assert!(
        msg.contains("resolved to no addresses"),
        "expected no-addresses rejection, got: {msg}"
    );
}

#[test]
fn validate_ics_url_rejects_plaintext_http_scheme() {
    // a calendar subscription URL using
    // `http://` exposes the feed URL (often a bearer-equivalent
    // token), the response body, and the device's browsing pattern
    // to anyone on the network path. The validator must reject the
    // plaintext scheme up-front, before DNS resolution even runs —
    // we use a resolver that would error on any lookup so we can
    // confirm the scheme check fires first.
    let resolver = FakeResolver {
        host: "unused.example".to_string(),
        addrs: vec![],
    };
    let err = validate_ics_url_safety(&parsed("http://feed.example.com/feed.ics"), &resolver)
        .expect_err("plaintext http:// must be rejected");
    let msg = format!("{err}");
    assert!(
        msg.contains("https://"),
        "error must guide user to https://, got: {msg}"
    );
}

#[test]
fn validate_ics_url_literal_ip_needs_no_resolver() {
    // A literal-IP URL should short-circuit the resolver path
    // entirely — any resolver state is irrelevant. Using a
    // public v4 to confirm the happy path; `is_denied_ipv4`
    // covers the private-literal case in a separate test.
    let resolver = FakeResolver {
        host: "unused.example".to_string(),
        addrs: vec![],
    };
    let resolved = validate_ics_url_safety(&parsed("https://142.251.32.78/feed.ics"), &resolver)
        .expect("public literal must pass without consulting resolver");
    assert!(
        resolved.is_empty(),
        "literal-IP URLs should return an empty resolved-addr vec (reqwest dials directly)"
    );
}

#[test]
fn validate_ics_url_rejects_literal_private_ipv4() {
    let resolver = FakeResolver {
        host: "unused.example".to_string(),
        addrs: vec![],
    };
    let err = validate_ics_url_safety(&parsed("https://10.0.0.1/feed.ics"), &resolver)
        .expect_err("RFC1918 literal must be rejected");
    let msg = format!("{err}");
    assert!(
        msg.contains("private or local-network"),
        "expected SSRF rejection, got: {msg}"
    );
}

#[test]
fn validate_ics_url_rejects_string_level_metadata_hostname() {
    // metadata.google.internal resolves to 169.254.169.254 on
    // GCE VMs — we reject it at the string level for a clearer
    // error message, before the DNS path even runs. No resolver
    // should be consulted.
    struct UnreachableResolver;
    impl HostResolver for UnreachableResolver {
        fn resolve(&self, _host: &str, _port: u16) -> std::io::Result<Vec<SocketAddr>> {
            panic!("string-level denylist should reject before the resolver runs");
        }
    }
    let err = validate_ics_url_safety(
        &parsed("https://metadata.google.internal/feed.ics"),
        &UnreachableResolver,
    )
    .expect_err("GCE metadata hostname must be rejected");
    let msg = format!("{err}");
    assert!(
        msg.contains("local-network or private hostname"),
        "expected hostname rejection, got: {msg}"
    );
}
