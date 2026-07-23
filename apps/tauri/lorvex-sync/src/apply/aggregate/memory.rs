//! Apply handlers for the `memory` aggregate (KV PK = `key`).
//!
//! Inbound `content` is scrubbed and clamped at the domain byte cap so
//! a peer cannot push an arbitrarily-long jailbreak/prompt-injection
//! payload via memory entries. Truncation is recorded in
//! `sync_conflict_log` for debugging visibility.

use rusqlite::{named_params, Connection};

use lorvex_domain::ids::MemoryKey;

use super::super::LwwTieBreak;
use super::helpers::{required_str, scrub};
use super::ApplyError;

pub(crate) fn apply_memory_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    loser_device_id: &str,
    apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: thread the typed `MemoryKey` through the
    // apply body. The dispatch table holds fn-pointer types shared
    // across every aggregate handler so the public signature stays
    // `&str`, but the function body operates on the typed key from
    // the very first line — SQL bind sites and the conflict-log
    // entity_id field both flow through the typed key (zero-copy
    // via the rusqlite ToSql impl on the newtype).
    let memory_key = MemoryKey::from_trusted(entity_id.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    // Unicode hygiene (#2427): memory content is rendered to the
    // assistant at session start; invisible controls must be stripped.
    let content_owned = scrub(required_str(&val, "content", "memory")?);
    let content: &str = &content_owned;
    let updated_at = required_str(&val, "updated_at", "memory")?;

    use lorvex_domain::memory::{MAX_MEMORY_CONTENT_LENGTH, MEMORY_TRUNCATION_SENTINEL};
    // `MEMORY_TRUNCATION_SENTINEL` is now a
    // `LazyLock<String>` so the byte-cap literal stays coupled to
    // `MAX_MEMORY_CONTENT_LENGTH`. Bind once and pass the borrow
    // through; `LazyLock<String>::deref()` returns `&String` which
    // coerces to `&str` for `push_str` / `len`.
    let sentinel: &str = &MEMORY_TRUNCATION_SENTINEL;
    let (clamped_content, truncated) = if content.len() > MAX_MEMORY_CONTENT_LENGTH {
        // Reserve room for the sentinel so the final string still fits in
        // the app-side input validator envelope.
        let sentinel_bytes = sentinel.len();
        let budget = MAX_MEMORY_CONTENT_LENGTH.saturating_sub(sentinel_bytes);
        // Walk back to a UTF-8 char boundary ≤ budget.
        let mut cut = budget.min(content.len());
        while cut > 0 && !content.is_char_boundary(cut) {
            cut -= 1;
        }
        let mut clamped = String::with_capacity(cut + sentinel_bytes);
        clamped.push_str(&content[..cut]);
        clamped.push_str(sentinel);
        (clamped, true)
    } else {
        (content.to_string(), false)
    };

    // The `memories` schema PK is an opaque UUIDv7 `id`; sync routes on
    // the `key` (natural-key aggregate — see `EntityKind::is_natural_key`),
    // so `id` is a device-local row identity, insert-only. It is minted
    // here for a brand-new key and left out of the `ON CONFLICT(key)`
    // update arm so a re-echo of an existing memory never rewrites its
    // id. This mirrors `memory_ops::upsert_memory_entry` and cannot use
    // the shared `LwwUpsertSpec` builder, which would emit
    // `id=excluded.id` in the SET clause.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = {
        let pair = SQL_CACHE.get_or_init(|| {
            let build = |cmp: &str| {
                format!(
                    "INSERT INTO memories (id, key, content, updated_at, version) \
                     VALUES (:id, :key, :content, :updated_at, :version) \
                     ON CONFLICT(key) DO UPDATE SET content=excluded.content, \
                     updated_at=excluded.updated_at, version=excluded.version \
                     WHERE excluded.version {cmp} memories.version"
                )
            };
            [
                build(crate::apply::version_cmp(LwwTieBreak::RejectEqual)),
                build(crate::apply::version_cmp(LwwTieBreak::AllowEqual)),
            ]
        });
        match allow_equal_versions {
            LwwTieBreak::RejectEqual => &pair[0],
            LwwTieBreak::AllowEqual => &pair[1],
        }
    };
    let new_id = lorvex_domain::new_entity_id_string();
    conn.prepare_cached(sql)?.execute(named_params! {
        ":id": new_id,
        // bind the typed `MemoryKey` directly via the rusqlite ToSql
        // impl on the newtype — no `.as_str()` allocation, and the
        // typed key is the only path that reaches the SQL layer.
        ":key": &memory_key,
        ":content": clamped_content,
        ":updated_at": updated_at,
        ":version": version,
    })?;

    // Log the truncation conflict ONLY after the upsert actually
    // landed (gated on `conn.changes() > 0`). Firing before the SQL
    // ran would let a stale envelope rejected by the version
    // compare still write a "truncated" entry to the conflict log
    // even though the live row was untouched — misleading the
    // Diagnostics → Conflicts panel and triggering false alerts
    // for operators investigating sync issues.
    if truncated && conn.changes() > 0 {
        // reuse the once-per-envelope `apply_ts` so
        // this conflict-log row's `resolved_at` matches every other
        // row produced by the same envelope apply.
        let now = apply_ts;
        crate::conflict_log::log_conflict(
            conn,
            &crate::conflict_log::ConflictLogEntry {
                id: 0,
                entity_type: std::borrow::Cow::Borrowed(lorvex_domain::naming::ENTITY_MEMORY),
                entity_id: memory_key.as_str().to_string(),
                winner_version: version.to_string(),
                loser_version: version.to_string(),
                loser_device_id: loser_device_id.to_string(),
                // `log_conflict` redacts `content` via scrub_loser_payload.
                loser_payload: Some(payload.to_string()),
                resolved_at: now.to_string(),
                resolution_type: std::borrow::Cow::Borrowed(
                    lorvex_domain::naming::RESOLUTION_CONTENT_TRUNCATED,
                ),
            },
        )?;
    }

    Ok(())
}

/// defense-in-depth LWW guard. Mirrors the
/// `WHERE ?2 >= version` pattern used by every other aggregate-delete
/// handler (task, list, habit, calendar_event).
pub(crate) fn apply_memory_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    // handler doesn't currently consume the apply
    // timestamp, but every aggregate-delete signature carries it for
    // uniform dispatch — `_apply_ts` keeps the parameter shape
    // without the unused-variable warning.
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse to the typed `MemoryKey` once at
    // the handler entry. The shared `lww_gated_delete` helper takes
    // a `&[&str]` slice for PK values, so we feed `memory_key.as_str()`
    // — the typed seam still covers every read of the key in this
    // handler scope, with a single zero-copy borrow at the boundary
    // of the cross-aggregate helper.
    let memory_key = MemoryKey::from_trusted(entity_id.to_string());
    crate::apply::lww_gated_delete(conn, "memories", &["key"], &[memory_key.as_str()], version)?;
    Ok(())
}
