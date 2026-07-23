use super::manifest::{SYNCABLE_AGGREGATE_TABLES, SYNCABLE_INDEPENDENT_CHILD_TABLES};
use lorvex_domain::naming::{ENTITY_AI_CHANGELOG, OP_DELETE};

/// enumerate every syncable aggregate-root table and emit
/// an `OP_DELETE` envelope per row. Each call to
/// [`crate::commands::enqueue_to_outbox_typed`] coalesces a row into
/// `sync_outbox` AND records a matching tombstone in `sync_tombstones` (the
/// shared `enqueue_payload_delete` core stamps the tombstone synchronously
/// — see `lorvex_sync::outbox_enqueue::enqueue_payload_internal`). Both
/// tables are deliberately preserved across the bulk wipe so the next sync
/// cycle pushes the deletes to peers.
///
/// Per-row payload is the canonical minimal `{"id": id}` (or `{"key": id}`
/// / `{"date": id}` for naturally-keyed aggregates) shape used by every
/// other delete callsite in the app. The receiver cascade-tombstones edges
/// and collection children (`task_tags`, `task_dependencies`,
/// `task_calendar_event_links`, `task_reminders`, `task_checklist_items`,
/// `current_focus_items`, `focus_schedule_blocks`,
/// `calendar_event_attendees`, `daily_review_*_links`, `habit_completions`,
/// `habit_reminder_policies`) on the apply path — matching the contract of
/// every other aggregate-root delete in the codebase.
///
/// Returns the total number of envelopes (== tombstones) emitted.
pub(super) fn enqueue_aggregate_root_tombstones(
    conn: &rusqlite::Connection,
) -> Result<usize, String> {
    let mut total = 0;

    // First pass: aggregate-root tombstones. The receiver's apply
    // pipeline cascade-tombstones edges and embedded children when it
    // sees one of these.
    for (table, pk_column, entity_type) in SYNCABLE_AGGREGATE_TABLES {
        // defense-in-depth identifier guards before
        // every `format!`-built SQL string. Both columns are
        // `&'static str` constants today; the assert pins that
        // invariant against a future contributor swapping in a
        // dynamic source.
        lorvex_domain::assert_safe_sql_identifier(table);
        lorvex_domain::assert_safe_sql_identifier(pk_column);
        let mut stmt = conn
            .prepare(&format!("SELECT {pk_column} FROM {table}"))
            .map_err(|e| format!("Failed to prepare reset tombstone scan for {table}: {e}"))?;
        let ids: Vec<String> = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .map_err(|e| format!("Failed to query {table} for reset tombstones: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Failed to read {table} row id for reset tombstone: {e}"))?;

        for id in ids {
            // Mirror the natural-key payload shape used by every other
            // delete callsite in the app: `tasks` / `lists` / `tags` /
            // `calendar_events` / `habits` / `calendar_subscriptions`
            // use `id`; `memories` keys on `key`; date-keyed
            // aggregates (`daily_reviews`, `current_focus`,
            // `focus_schedule`) key on `date`. The receiver consumes
            // the envelope `entity_id` for identity; the payload field
            // exists for `before_json`-aware peers.
            let mut payload_obj = serde_json::Map::new();
            payload_obj.insert(
                (*pk_column).to_string(),
                serde_json::Value::String(id.clone()),
            );
            let payload = serde_json::Value::Object(payload_obj);
            crate::commands::enqueue_to_outbox_typed(conn, entity_type, &id, OP_DELETE, &payload)
                .map_err(|e| {
                format!(
                    "Failed to enqueue reset tombstone for {entity_type} '{id}' in {table}: {e}"
                )
            })?;
            total += 1;
        }
    }

    // Second pass: independent-child sync entities. These rows
    // cascade-delete from their parent aggregate via SQLite FK rules,
    // but they ALSO carry their own sync identity in
    // `naming::ALL_SYNCABLE_TYPES`. A peer receiving a late-arriving
    // child upsert AFTER the parent delete has applied would
    // otherwise see the upsert preflight-deferred to
    // `sync_pending_inbox` and age out — leaving stale child state
    // if the upsert ever resurfaces from a third device. Emitting
    // per-row child tombstones here closes that gap.
    for (table, pk_column, parent_fk, entity_type, parent_entity_type) in
        SYNCABLE_INDEPENDENT_CHILD_TABLES
    {
        // defense-in-depth — three identifiers feed the
        // `format!` below; assert all three before composing SQL.
        lorvex_domain::assert_safe_sql_identifier(table);
        lorvex_domain::assert_safe_sql_identifier(pk_column);
        lorvex_domain::assert_safe_sql_identifier(parent_fk);
        let mut stmt = conn
            .prepare(&format!("SELECT {pk_column}, {parent_fk} FROM {table}"))
            .map_err(|e| {
                format!("Failed to prepare reset child-tombstone scan for {table}: {e}")
            })?;
        let rows: Vec<(String, Option<String>)> = stmt
            .query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, Option<String>>(1)?))
            })
            .map_err(|e| format!("Failed to query {table} for reset child tombstones: {e}"))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|e| format!("Failed to read {table} row for reset child tombstone: {e}"))?;

        for (id, parent_id_opt) in rows {
            // Payload carries the child's `id` field plus the parent
            // FK column so the receiver's preflight FK check can
            // resolve to the parent's just-emitted aggregate
            // tombstone (the first-pass writes land in the same
            // outbox / sync_tombstones round, so cluster ordering
            // sees the parent tombstone first by virtue of the
            // physical_ms-ordered outbox emit). For nullable parent
            // FKs, a `null`
            // payload entry is harmless — the FK preflight only runs
            // on non-null values.
            let mut payload_obj = serde_json::Map::new();
            payload_obj.insert(
                (*pk_column).to_string(),
                serde_json::Value::String(id.clone()),
            );
            payload_obj.insert(
                (*parent_fk).to_string(),
                match &parent_id_opt {
                    Some(parent_id) => serde_json::Value::String(parent_id.clone()),
                    None => serde_json::Value::Null,
                },
            );
            // Annotate with the parent entity type for receiver-side
            // diagnostics — not strictly required by the apply
            // pipeline but useful in `sync_pending_inbox` debug
            // output if the envelope ever surfaces there.
            payload_obj.insert(
                "_parent_entity_type".to_string(),
                serde_json::Value::String((*parent_entity_type).to_string()),
            );
            let payload = serde_json::Value::Object(payload_obj);
            crate::commands::enqueue_to_outbox_typed(conn, entity_type, &id, OP_DELETE, &payload)
                .map_err(|e| {
                    format!(
                        "Failed to enqueue reset child tombstone for {entity_type} '{id}' in {table}: {e}"
                    )
                })?;
            total += 1;
        }
    }

    total += enqueue_preference_reset_tombstones(conn)?;
    total += enqueue_ai_changelog_reset_tombstones(conn)?;

    Ok(total)
}

fn enqueue_preference_reset_tombstones(conn: &rusqlite::Connection) -> Result<usize, String> {
    let mut stmt = conn
        .prepare("SELECT key FROM preferences ORDER BY key")
        .map_err(|e| format!("Failed to prepare reset preference tombstone scan: {e}"))?;
    let keys: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| format!("Failed to query preferences for reset tombstones: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Failed to read preference key for reset tombstone: {e}"))?;

    let mut total = 0;
    for key in keys {
        let snapshot = crate::commands::load_preference_pre_delete_snapshot(conn, &key)
            .map_err(|e| format!("Failed to snapshot preference '{key}' for reset: {e}"))?;
        let envelope = crate::commands::DeleteEnvelope::new(key.clone(), snapshot);
        crate::commands::enqueue_preference_delete(conn, envelope)
            .map_err(|e| format!("Failed to enqueue reset preference tombstone '{key}': {e}"))?;
        if !lorvex_domain::preference_keys::is_local_only_preference(&key) {
            total += 1;
        }
    }
    Ok(total)
}

fn enqueue_ai_changelog_reset_tombstones(conn: &rusqlite::Connection) -> Result<usize, String> {
    let mut stmt = conn
        .prepare("SELECT id FROM ai_changelog ORDER BY timestamp, id")
        .map_err(|e| format!("Failed to prepare reset ai_changelog tombstone scan: {e}"))?;
    let ids: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| format!("Failed to query ai_changelog for reset tombstones: {e}"))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| format!("Failed to read ai_changelog id for reset tombstone: {e}"))?;

    for id in &ids {
        let payload = serde_json::json!({
            "id": id,
            "reset_all_data": true,
        });
        crate::commands::enqueue_to_outbox_typed(
            conn,
            ENTITY_AI_CHANGELOG,
            id,
            OP_DELETE,
            &payload,
        )
        .map_err(|e| format!("Failed to enqueue reset ai_changelog tombstone '{id}': {e}"))?;
    }
    Ok(ids.len())
}
