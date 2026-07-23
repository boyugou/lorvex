//! Diagnostic-text redaction shared across the MCP server and the Tauri app.
//!
//! Error messages, stack traces, and HTTP response fragments that land in
//! `error_logs` or `ai_changelog` summaries can incidentally contain access
//! tokens, bearer authorization headers, `sk_…`/`AKIA…`-style API keys, and
//! JSON-serialized password / token fields. These live alongside genuinely
//! diagnostic content (file paths, task ids, HTTP status codes) and need to
//! survive persistence long enough to show up in Settings → Diagnostics —
//! but must not ship out of the machine in a copy-to-clipboard bug report.
//!
//! Every write to `error_logs` and every read that feeds the user-visible
//! diagnostic surfaces should pass through `redact_diagnostic_text` first.

/// Redact bearer tokens, API-key-prefixed strings, `key=value` /
/// `"key":"value"` secret patterns, email addresses, and user home
/// directory path fragments in a free-form diagnostic string.
///
/// Works at the whitespace-token level: a purely-noise fallback that is
/// safe to apply to any user-facing string, never widens the surface (no
/// new characters introduced that weren't already there), and preserves
/// enough structure that the sanitized message remains useful for triage.
pub fn redact_diagnostic_text(value: &str) -> String {
    /// Keys that mask their `key=value` / `"key":"value"` shapes.
    /// `lower.contains` checks against lowercase ASCII so the keys
    /// themselves are stored lowercase; the loop produces the
    /// `key=` / `"key":` patterns by appending the literal terminator
    /// in place rather than allocating a fresh `format!` String per
    /// (token, key) pair.
    const KV_KEYS: &[&str] = &[
        "password", "passwd", "secret", "token", "api_key", "api-key",
    ];

    // Stream redacted tokens directly into a single output buffer
    // instead of materializing a `Vec<String>` of per-token results
    // and joining at the end. Most tokens pass through unchanged
    // (no secret pattern matches) — the previous shape allocated a
    // fresh `String` for every passthrough plus the backing vec on
    // every `error_logs` write. Pass-through tokens now write
    // straight from the input slice.
    let mut out = String::with_capacity(value.len());
    let mut skip_next_bearer_value = false;
    let mut first = true;

    let push_sep = |out: &mut String, first: &mut bool| {
        if *first {
            *first = false;
        } else {
            out.push(' ');
        }
    };

    for token in value.split_whitespace() {
        if skip_next_bearer_value {
            skip_next_bearer_value = false;
            continue;
        }

        let lower = token.to_ascii_lowercase();
        if lower == "bearer" {
            push_sep(&mut out, &mut first);
            out.push_str("Bearer [REDACTED]");
            skip_next_bearer_value = true;
            continue;
        }
        if lower.starts_with("bearer:") || lower.starts_with("bearer=") {
            push_sep(&mut out, &mut first);
            out.push_str("Bearer [REDACTED]");
            continue;
        }
        if lower.starts_with("authorization:bearer") || lower.starts_with("authorization=bearer") {
            push_sep(&mut out, &mut first);
            out.push_str("Authorization: Bearer [REDACTED]");
            if lower == "authorization:bearer" || lower == "authorization=bearer" {
                skip_next_bearer_value = true;
            }
            continue;
        }
        if token.starts_with("sk_")
            || token.starts_with("rk_")
            || token.starts_with("pk_")
            || token.starts_with("AKIA")
        {
            push_sep(&mut out, &mut first);
            out.push_str("[REDACTED_TOKEN]");
            continue;
        }
        // URL query + userinfo redaction runs BEFORE the kv-secret
        // pass so `https://…/feed?token=abc` is masked as a URL
        // rather than leaving the bare URL prefix behind when
        // `token=` triggers the kv rule.
        if let Some(redacted) = redact_http_url(token) {
            push_sep(&mut out, &mut first);
            out.push_str(&redacted);
            continue;
        }
        let mut masked_kv_secret = false;
        for key in KV_KEYS {
            // Substring-search on the lowercased token without
            // allocating a fresh `format!`-built pattern per (token,
            // key). `lower.find(key)` finds the key, then we verify
            // the byte at the matching offset is `=` (kv) or that
            // the key is wrapped in quotes followed by `:` (json).
            let mut start = 0;
            while let Some(rel) = lower[start..].find(key) {
                let pos = start + rel;
                let after = pos + key.len();
                // `key=` form
                if lower.as_bytes().get(after).copied() == Some(b'=') {
                    let prefix = token.split('=').next().unwrap_or("secret");
                    push_sep(&mut out, &mut first);
                    out.push_str(prefix);
                    out.push_str("=[REDACTED]");
                    masked_kv_secret = true;
                    break;
                }
                // `"key":` form — the key must be preceded by `"`
                // and followed by `":` to count as a JSON object
                // entry.
                if pos > 0
                    && lower.as_bytes()[pos - 1] == b'"'
                    && lower.as_bytes().get(after).copied() == Some(b'"')
                    && lower.as_bytes().get(after + 1).copied() == Some(b':')
                {
                    push_sep(&mut out, &mut first);
                    out.push_str("[REDACTED_JSON_SECRET]");
                    masked_kv_secret = true;
                    break;
                }
                start = pos + key.len();
            }
            if masked_kv_secret {
                break;
            }
        }
        if masked_kv_secret {
            continue;
        }
        // Email redaction: covers most RFC-5322-adjacent shapes
        // (`user+tag@example.com`) without pulling in a regex crate.
        // Anything with an `@` separating two dot-bearing tokens of
        // reasonable shape is treated as an email. The pattern
        // \`user@host.tld\` is broad enough to catch most real cases
        // while narrow enough not to redact \`@mentions\` or
        // \`key@value\` strings that lack a host dot.
        if token_is_email_like(token) {
            push_sep(&mut out, &mut first);
            out.push_str("[REDACTED_EMAIL]");
            continue;
        }
        // Absolute path redaction: user home dir prefixes leak the
        // account name into shareable bug reports. Redact just the
        // user component, leave the tail so the diagnostic stays
        // useful (`[~]/Library/Application Support/…`).
        if let Some(redacted) = redact_home_path(token) {
            push_sep(&mut out, &mut first);
            out.push_str(&redacted);
            continue;
        }
        push_sep(&mut out, &mut first);
        out.push_str(token);
    }

    out
}

fn token_is_email_like(token: &str) -> bool {
    // Must contain exactly one `@` with non-empty local + host and a
    // dot in the host — the cheapest narrow filter that catches
    // `alice@example.com`, `user+tag@mail.example.co.uk`, and rejects
    // `@mentions` / `key@value` / `a@b` (no host dot).
    let mut parts = token.splitn(2, '@');
    let Some(local) = parts.next() else {
        return false;
    };
    let Some(host) = parts.next() else {
        return false;
    };
    if local.is_empty() || host.is_empty() {
        return false;
    }
    // Reject additional `@` in host (indicates something other than email).
    if host.contains('@') {
        return false;
    }
    // Host must contain at least one dot and end with an alphanumeric.
    host.contains('.')
        && host
            .chars()
            .last()
            .is_some_and(|c| c.is_ascii_alphanumeric())
        && local
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || "._+-".contains(c))
}

fn redact_home_path(token: &str) -> Option<String> {
    // macOS: `/Users/<name>/...`
    // Linux: `/home/<name>/...`
    // Windows: `C:\Users\<name>\...` (cased `\\` or `/`)
    for prefix in ["/Users/", "/home/"] {
        if let Some(rest) = token.strip_prefix(prefix) {
            let mut parts = rest.splitn(2, '/');
            let _user = parts.next()?;
            let tail = parts.next().unwrap_or("");
            let redacted = if tail.is_empty() {
                "[~]".to_string()
            } else {
                format!("[~]/{tail}")
            };
            return Some(redacted);
        }
    }
    // Windows path with forward or backslashes.
    for prefix in ["C:\\Users\\", "c:\\Users\\", "C:/Users/", "c:/Users/"] {
        if let Some(rest) = token.strip_prefix(prefix) {
            let mut parts = rest.splitn(2, ['\\', '/']);
            let _user = parts.next()?;
            let tail = parts.next().unwrap_or("");
            let redacted = if tail.is_empty() {
                "[~]".to_string()
            } else {
                format!("[~]/{tail}")
            };
            return Some(redacted);
        }
    }
    None
}

/// Mask the query string and userinfo of an http(s) URL while
/// preserving scheme + host + path + any trailing punctuation. No
/// dependency on the `url` crate — we only need to recognize the
/// `http(s)://` prefix and strip the `?...` suffix plus the
/// `user[:pass]@` segment between `//` and the first `/`, `?`, or
/// `#`. Returns `None` if the token isn't an http(s) URL so the
/// caller can fall through to plain-text preservation.
fn redact_http_url(token: &str) -> Option<String> {
    let (scheme_end, rest) = if let Some(rest) = token.strip_prefix("http://") {
        (7, rest)
    } else if let Some(rest) = token.strip_prefix("https://") {
        (8, rest)
    } else {
        return None;
    };
    let scheme = &token[..scheme_end];
    // Separate trailing punctuation ( `.`, `,`, `)` ) so the redacted
    // form preserves sentence punctuation.
    let (body, trailing) = {
        let mut end = rest.len();
        while end > 0 {
            let c = rest.as_bytes()[end - 1] as char;
            if matches!(c, '.' | ',' | ')' | ']' | '>' | '"' | '\'' | ';') {
                end -= 1;
            } else {
                break;
            }
        }
        (&rest[..end], &rest[end..])
    };
    if body.is_empty() {
        return None;
    }
    // Split off fragment first so fragments don't hide a query.
    let (before_fragment, _fragment) = body
        .find('#')
        .map_or((body, ""), |i| (&body[..i], &body[i..]));
    // Strip query.
    let before_query = before_fragment
        .find('?')
        .map_or(before_fragment, |i| &before_fragment[..i]);
    let had_query = before_fragment.contains('?');
    // Strip userinfo: everything up to the first `@` BEFORE the
    // first `/` counts as userinfo (per RFC 3986).
    let path_start = before_query.find('/').unwrap_or(before_query.len());
    let (authority, path) = before_query.split_at(path_start);
    let masked_authority = match authority.find('@') {
        Some(_) => {
            let host = authority.rsplit('@').next().unwrap_or(authority);
            format!("[REDACTED_USERINFO]@{host}")
        }
        None => authority.to_string(),
    };
    let mut out = String::with_capacity(token.len());
    out.push_str(scheme);
    out.push_str(&masked_authority);
    out.push_str(path);
    if had_query {
        out.push_str("?[REDACTED_QUERY]");
    }
    out.push_str(trailing);
    Some(out)
}

#[cfg(test)]
mod tests;
