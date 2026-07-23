use super::*;

// ---------------------------------------------------------------------------
// tag upsert with convergence
// ---------------------------------------------------------------------------

pub(crate) fn apply_tag_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    apply_ts: &str,
) -> Result<(), ApplyError> {
    let val: serde_json::Value = serde_json::from_str(payload)?;

    // Unicode hygiene (#2427): scrub the display_name at the sync apply
    // boundary so a peer running an older build cannot push a tag whose
    // display contains bidi overrides or ZWSPs. The `lookup_key` is then
    // re-derived below via `normalize_lookup_key`, which is NFKC-aware and
    // benefits from receiving already-hygienic input.
    let display_name_owned = lorvex_domain::sanitize_user_text(required_str(&val, "display_name")?);
    let display_name: &str = &display_name_owned;
    // `tag.color` is a nullable column where an explicit
    // empty write means "reset to default". The empty-preserving helper
    // distinguishes that clear intent from an absent key so the peer's
    // reset fans out rather than being silently ignored as "no change".
    let color = nullable_str_or_clear(&optional_str_preserving_empty(&val, "color")?);
    let created_at = required_str(&val, "created_at")?;
    let updated_at = required_str(&val, "updated_at")?;

    // Re-derive `lookup_key` from `display_name` instead of trusting the
    // inbound payload. A peer running an older Lorvex build, or any CLI
    // tool that writes envelopes by hand, can produce a `lookup_key` that
    // doesn't match the canonical NFKC + casefold form. Since
    // `merge_duplicate_tags` only converges rows whose `lookup_key`
    // strings compare literally equal, two semantically identical tags
    // from different devices would permanently coexist — and the merge
    // policy's "minimum id wins" invariant would silently break.
    //
    // Normalizing at the apply boundary enforces the invariant at every
    // ingress point so downstream sort/merge logic can trust it.
    let normalized_lookup_key = normalize_lookup_key(display_name);
    let lookup_key = normalized_lookup_key.as_str();

    // Upsert the tag row.
    //
    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "tags",
        columns: &[
            "id",
            "display_name",
            "lookup_key",
            "color",
            "created_at",
            "updated_at",
            "version",
        ],
        conflict: &["id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":id": entity_id,
        ":display_name": display_name,
        ":lookup_key": lookup_key,
        ":color": color,
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":version": version,
    })?;

    // Convergence detection: only run merge if the upsert actually modified a row.
    // If the version check prevented the update (remote was older), conn.changes()
    // is 0 and we must NOT run the merge — a stale envelope with a smaller tag ID
    // could tombstone the live tag.
    let changes = conn.changes();
    if changes > 0 {
        merge_duplicate_tags(conn, entity_id, lookup_key, version, apply_ts)?;
    }

    Ok(())
}

pub(crate) fn apply_tag_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // task_tags rows cascade-deleted via FK.
    // route the in-row LWW guard through `lww_gated_delete` so the
    // typed-HLC parse-then-compare discipline runs here too. The
    // upstream `apply_envelope` already gates by HLC through the
    // tombstone bookkeeping, but the in-row gate keeps the handler
    // safe under shadow-promotion replay and any future replay path
    // that hasn't already gated upstream.
    crate::apply::lww_gated_delete(conn, "tags", &["id"], &[entity_id], version)?;
    Ok(())
}
