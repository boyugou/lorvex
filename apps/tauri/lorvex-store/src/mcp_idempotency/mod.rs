//! MCP idempotency cache (issue #2238).
//!
//! Clients that retry `create_task` / `batch_create_tasks` on transient
//! failure — e.g. transport timeouts that fire *after* the DB already
//! committed the INSERT but *before* the caller observed the response —
//! would otherwise produce silent duplicate rows, because each attempt
//! mints a fresh UUID and runs the INSERT unconditionally.
//!
//! The fix: the client supplies an `idempotency_key` with the request.
//! The handler consults this cache before writing; on a same-tool hit
//! it returns the cached response payload byte-for-byte. On a miss the
//! write proceeds and the response is recorded here with a 24h TTL.
//!
//! All timestamps written here flow through
//! [`lorvex_domain::sync_timestamp_now`] / [`lorvex_domain::normalize_sync_timestamp`]
//! so the canonical millisecond-`Z` shape (matching `sync_outbox.created_at`,
//! `ai_changelog.timestamp`, and `strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`) is
//! the only formatter in the workspace; future precision changes happen in
//! one place.
//!
//! Rows past `expires_at` are cleaned up at MCP-server boot via
//! [`sweep_expired`]. This keeps the cache bounded without any
//! background thread — a stdio MCP child process is short-lived enough
//! that a sweep-on-start is sufficient.
//!
//! there is intentionally no scheduled GC for this
//! cache. A long-running session that doesn't restart the MCP child
//! accumulates expired rows until the next boot, but every read path
//! filters by `expires_at > now` so stale rows can never satisfy a
//! cache hit — the only cost is disk space proportional to the
//! 24-hour write rate. If a future deployment shape produces a
//! genuinely-long-lived MCP server (months between restarts), wire a
//! periodic `sweep_expired` call into the apply-cycle retention loop;
//! today every supported launch path (Claude Desktop, MCP-capable IDE)
//! tears the child down on session close, so boot-only sweeping is
//! sufficient.

use chrono::{DateTime, Duration, Utc};
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use std::sync::atomic::{AtomicI64, Ordering};

/// Default retention window for idempotency records. Chosen to be long
/// enough to absorb every realistic retry burst (network blips,
/// assistant reconnects, laptop sleeps) while short enough that a stale
/// cache can't mask a genuinely new request that happens to reuse a
/// stringy key.
pub const DEFAULT_TTL_HOURS: i64 = 24;

/// Result of a cache lookup attempt.
#[derive(Debug, PartialEq, Eq)]
pub enum LookupOutcome {
    /// No cached row for this tool/key pair (or the row has expired).
    Miss,
    /// A cached row exists and the supplied checksum matches the
    /// stored checksum — the response payload is safe to replay.
    Hit(String),
    /// A cached row exists but its stored checksum disagrees with the
    /// caller's. This means the assistant reused the idempotency
    /// token for a semantically different request; the caller must
    /// surface this as a Validation error rather than silently replay
    /// the prior response. Carries the stored tool_name so the
    /// diagnostic can pinpoint the original tool.
    ChecksumMismatch {
        stored_tool: String,
        stored_checksum: String,
        supplied_checksum: String,
    },
}

/// Compute the canonical checksum fingerprint cached
/// idempotency requests. The hash is over the byte sequence of the
/// caller-supplied request representation; callers are responsible
/// for normalizing the input (e.g. canonical JSON) so logically
/// equivalent payloads produce the same hash. Returns the SHA-256 hex
/// digest as a 64-char lowercase string.
///
/// this is the gate that keeps a cache hit from
/// poisoning a fresh request. If a future request supplies a
/// different `request_repr` for the same key, the lookup arm
/// distinguishes "this is a retry of the same call" from "this is a
/// new call that accidentally reuses the token."
pub fn compute_request_checksum(request_repr: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(request_repr.as_bytes());
    let digest = hasher.finalize();
    hex_lower(&digest)
}

fn hex_lower(bytes: &[u8]) -> String {
    use std::fmt::Write as _;
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        // `write!` writes the formatted hex pair directly into `out`'s
        // buffer; the previous `push_str(&format!(...))` allocated a
        // throwaway String per byte just to copy it back. Writing into
        // `String` is infallible.
        write!(out, "{byte:02x}").expect("write! to String is infallible");
    }
    out
}

/// Compute an `expires_at` timestamp `hours` into the future from `from`,
/// formatted in the canonical sync shape via
/// [`lorvex_domain::format_sync_timestamp`].
fn expires_at_from(from: DateTime<Utc>, hours: i64) -> String {
    lorvex_domain::format_sync_timestamp(from + Duration::hours(hours))
}

/// Looks up a cached response for `tool_name` and verifies its stored
/// checksum matches `supplied_checksum`. Returns one of
/// `LookupOutcome::{Miss, Hit, ChecksumMismatch}`. Callers must use
/// this entry point on every idempotent retry path so that a same-tool
/// key collision produces a loud Validation error instead of silently
/// replaying a stale, unrelated response.
///
fn lookup_checked_at(
    conn: &Connection,
    tool_name: &str,
    key: &str,
    supplied_checksum: &str,
    now: DateTime<Utc>,
) -> rusqlite::Result<LookupOutcome> {
    let row: Option<(String, String, String)> = conn
        .prepare_cached(
            "SELECT tool_name, request_checksum, response_payload \
             FROM mcp_idempotency \
             WHERE tool_name = ?1 AND key = ?2 AND expires_at > ?3",
        )?
        .query_row(
            params![tool_name, key, lorvex_domain::format_sync_timestamp(now)],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;
    let Some((tool_name, stored_checksum, payload)) = row else {
        return Ok(LookupOutcome::Miss);
    };
    if stored_checksum == supplied_checksum {
        return Ok(LookupOutcome::Hit(payload));
    }
    Ok(LookupOutcome::ChecksumMismatch {
        stored_tool: tool_name,
        stored_checksum,
        supplied_checksum: supplied_checksum.to_string(),
    })
}

/// Looks up a cached response with checksum verification against the
/// canonical wall clock.
pub fn lookup_checked(
    conn: &Connection,
    tool_name: &str,
    key: &str,
    supplied_checksum: &str,
) -> rusqlite::Result<LookupOutcome> {
    lookup_checked_at(conn, tool_name, key, supplied_checksum, Utc::now())
}

/// Insert or replace the cached response for `(tool_name, key)`. Uses
/// `INSERT OR REPLACE` so a retry that completes after its
/// predecessor's row expired simply overwrites the stale entry instead
/// of erroring on PRIMARY KEY conflict.
///
/// stamps the supplied `request_checksum` so the
/// next lookup can distinguish a true retry (matching checksum) from
/// an accidental key collision (mismatched checksum).
pub fn record_at(
    conn: &Connection,
    key: &str,
    tool_name: &str,
    request_checksum: &str,
    response_payload: &str,
    now: DateTime<Utc>,
    ttl_hours: i64,
) -> rusqlite::Result<()> {
    if request_checksum.is_empty() {
        return Err(rusqlite::Error::InvalidParameterName(
            "request_checksum must not be empty".to_string(),
        ));
    }
    conn.prepare_cached(
        "INSERT OR REPLACE INTO mcp_idempotency \
         (key, tool_name, request_checksum, response_payload, created_at, expires_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
    )?
    .execute(params![
        key,
        tool_name,
        request_checksum,
        response_payload,
        lorvex_domain::format_sync_timestamp(now),
        expires_at_from(now, ttl_hours),
    ])?;
    Ok(())
}

/// Insert or replace the cached response with the default 24h TTL,
/// stamping `created_at` from the canonical sync clock.
pub fn record(
    conn: &Connection,
    key: &str,
    tool_name: &str,
    request_checksum: &str,
    response_payload: &str,
) -> rusqlite::Result<()> {
    record_at(
        conn,
        key,
        tool_name,
        request_checksum,
        response_payload,
        Utc::now(),
        DEFAULT_TTL_HOURS,
    )
}

/// in-memory cache of the most recent successful
/// sweep timestamp (Unix millis). When several MCP clients launch
/// in close succession (Claude Desktop opening a project that
/// auto-connects three MCP servers, or a rapid disconnect /
/// reconnect cycle) the boot-sweep ran N times back-to-back even
/// though the second pass had nothing to delete — the DELETE took
/// the writer lock anyway and momentarily blocked every concurrent
/// MCP write. Skip when the previous sweep ran inside this window.
///
/// 5 minutes is generous: TTL is 24h, so even 12 sweeps/hour keeps
/// the table well under the boot-sweep threshold.
const SWEEP_SKIP_WINDOW_MS: i64 = 5 * 60 * 1000;
static LAST_SWEEP_AT_MILLIS: AtomicI64 = AtomicI64::new(0);

/// Delete all rows whose `expires_at` is less than or equal to `now`.
/// Returns the number of rows removed. Meant to run at MCP-server boot.
fn sweep_expired_at(conn: &Connection, now: DateTime<Utc>) -> rusqlite::Result<usize> {
    let deleted = conn
        .prepare_cached("DELETE FROM mcp_idempotency WHERE expires_at <= ?1")?
        .execute(params![lorvex_domain::format_sync_timestamp(now)])?;
    Ok(deleted)
}

/// Delete all expired rows using the canonical wall clock.
///
/// returns `Ok(0)` immediately if a sweep ran within
/// the last [`SWEEP_SKIP_WINDOW_MS`]. The skip is process-local — a
/// fresh MCP child still sweeps once at boot — but back-to-back
/// boots inside the same process (test suite, embedded host) won't
/// re-run the writer-locking DELETE.
pub fn sweep_expired(conn: &Connection) -> rusqlite::Result<usize> {
    let now = Utc::now();
    let now_millis = now.timestamp_millis();
    let last = LAST_SWEEP_AT_MILLIS.load(Ordering::Acquire);
    if last != 0 && now_millis.saturating_sub(last) < SWEEP_SKIP_WINDOW_MS {
        return Ok(0);
    }
    // Atomically claim the sweep slot. A bare load-then-store would
    // let two threads both pass the skip check and each fire
    // `sweep_expired_at`, doubling the writer-locking DELETE cost in
    // the test harness and any embedded host that boots multiple
    // connections concurrently. `compare_exchange` with AcqRel
    // ordering ensures exactly one caller wins the claim; the loser
    // short-circuits as if a recent sweep had already run.
    if LAST_SWEEP_AT_MILLIS
        .compare_exchange(last, now_millis, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return Ok(0);
    }
    sweep_expired_at(conn, now)
}

#[cfg(test)]
mod tests;
