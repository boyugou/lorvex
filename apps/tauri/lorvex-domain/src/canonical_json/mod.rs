//! domain-level canonical JSON serializer.
//!
//! Single source of truth for sorted-key, compact JSON serialization
//! across the workspace. Pre-existing canonicalize logic lived only in
//! `lorvex-sync` (which depends on `lorvex-domain`), so callers in
//! `lorvex-store` (which `lorvex-sync` depends on) had to either
//! duplicate the algorithm or rely on `serde_json::Value::to_string`
//! defaulting to sorted keys via the `serde_json::Map = BTreeMap`
//! alias. The latter only holds while the workspace keeps
//! `serde_json` default features ON (no `preserve_order`); a
//! transitive feature unification flipping that contract would
//! silently re-emit insertion-order JSON on store-side payloads.
//!
//! Hoisting the canonical writer here lets `lorvex-store::recurrence`
//! produce key-stable output for `inject_bymonthday`, and
//! `lorvex-sync::canonicalize` re-exports / delegates so the wire
//! envelope contract still funnels through one implementation.
//!
//! # Differences from `lorvex_sync::canonicalize::canonicalize_json`
//!
//! - This function does NOT apply the wire-envelope payload-size cap
//!   (`MAX_CANONICAL_PAYLOAD_BYTES`). Wire-envelope callers should
//!   continue to use the sync-side wrapper that adds the cap;
//!   in-process callers (recurrence rule serialization) don't need
//!   the byte limit because the input shape is bounded at parse time.
//! - This function still enforces `MAX_JSON_DEPTH` to guard the
//!   recursion stack — callers that hand a deeply-nested structure
//!   still get a clean error rather than a stack overflow.

use serde_json::Value;
use std::fmt;

/// Maximum allowed nesting depth for a canonicalized JSON value.
///
/// Mirrors the `lorvex_sync::canonicalize::MAX_JSON_DEPTH` cap so the
/// two implementations can never disagree on what counts as "too
/// deep". Bumping one without the other would let a payload pass the
/// store-side encoder and fail the wire-side encoder, or vice versa.
///
/// # Contract (#3051 M14)
///
/// Depths in the half-open range `0..MAX_JSON_DEPTH` are accepted —
/// i.e. `MAX_JSON_DEPTH` distinct nesting levels (the outermost value
/// is depth 0, the innermost legal value is at depth
/// `MAX_JSON_DEPTH - 1`). The first level past the cap (depth equal
/// to `MAX_JSON_DEPTH`) errors with [`CanonError::DepthExceeded`].
/// The gate uses `>=` (not `>`) so the documented cap is exact;
/// `>` would silently accept one level past it.
pub const MAX_JSON_DEPTH: usize = 32;

/// Errors returned by `canonicalize_json`.
#[derive(Debug)]
pub enum CanonError {
    /// The input JSON is nested deeper than [`MAX_JSON_DEPTH`].
    DepthExceeded,
}

impl fmt::Display for CanonError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::DepthExceeded => {
                write!(f, "JSON nesting exceeds maximum depth of {MAX_JSON_DEPTH}")
            }
        }
    }
}

impl std::error::Error for CanonError {}

/// Canonicalize a JSON value: sorted keys, compact format.
///
/// Bytewise output matches the sync-side `canonicalize_json` for any
/// input that survives both depth gates.
pub fn canonicalize_json(value: &Value) -> Result<String, CanonError> {
    let mut out = String::new();
    write_canonical(&mut out, value, 0)?;
    Ok(out)
}

fn write_canonical(out: &mut String, value: &Value, depth: usize) -> Result<(), CanonError> {
    if depth >= MAX_JSON_DEPTH {
        return Err(CanonError::DepthExceeded);
    }
    match value {
        Value::Object(map) => {
            // Collect borrowed key references and sort by key. The
            // sort buffer holds `&String` references, not owned
            // copies — the only allocation per object is the Vec of
            // pointers, regardless of value count or string size.
            let mut entries: Vec<(&String, &Value)> = map.iter().collect();
            entries.sort_unstable_by(|(a, _), (b, _)| a.as_str().cmp(b.as_str()));
            out.push('{');
            for (i, (k, v)) in entries.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_json_string(out, k.as_str());
                out.push(':');
                write_canonical(out, v, depth + 1)?;
            }
            out.push('}');
        }
        Value::Array(arr) => {
            out.push('[');
            for (i, v) in arr.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_canonical(out, v, depth + 1)?;
            }
            out.push(']');
        }
        // Format scalars directly into `out`.
        // through `serde_json::to_writer(&mut Vec::with_capacity(8))`
        // followed by a `from_utf8` + `push_str` — three allocations
        // per scalar even for `null` / `true` / `false`. Numbers route
        // through `serde_json::Number`'s `Display` impl which already
        // produces the canonical wire form, so we can `write!` it
        // straight onto `out`.
        Value::Null => out.push_str("null"),
        Value::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Value::Number(n) => {
            use std::fmt::Write;
            // `Number`'s `Display` impl is infallible for the canonical
            // i64/u64/f64 set — `write!` on a `String` returns
            // `fmt::Result` only because the trait does, never errors.
            let _ = write!(out, "{n}");
        }
        Value::String(s) => write_json_string(out, s.as_str()),
    }
    Ok(())
}

/// Mirrors `serde_json`'s escape table so canonicalized output is
/// byte-identical to what `serde_json::to_string` would have produced
/// from the same value with sorted keys.
fn write_json_string(out: &mut String, s: &str) {
    out.push('"');
    let bytes = s.as_bytes();
    let mut start = 0usize;
    let mut i = 0usize;
    while i < bytes.len() {
        let b = bytes[i];
        let escape: Option<&'static str> = match b {
            b'"' => Some("\\\""),
            b'\\' => Some("\\\\"),
            b'\n' => Some("\\n"),
            b'\r' => Some("\\r"),
            b'\t' => Some("\\t"),
            0x08 => Some("\\b"),
            0x0c => Some("\\f"),
            _ => None,
        };
        if let Some(seq) = escape {
            if start < i {
                out.push_str(&s[start..i]);
            }
            out.push_str(seq);
            i += 1;
            start = i;
        } else if b < 0x20 {
            if start < i {
                out.push_str(&s[start..i]);
            }
            let _ = std::fmt::Write::write_fmt(out, format_args!("\\u{b:04x}"));
            i += 1;
            start = i;
        } else {
            i += 1;
        }
    }
    if start < bytes.len() {
        out.push_str(&s[start..]);
    }
    out.push('"');
}

#[cfg(test)]
mod tests;
