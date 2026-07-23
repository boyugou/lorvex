//! Task-tag edge add/remove for a single-row task update.
//!
//! [`replace_task_tags`] diffs the prepared tag set against the row's
//! current tags, emitting per-edge upserts (with `tags` row creation
//! when the tag is new) and per-edge deletes (with the pre-delete
//! snapshot every surface needs to enqueue an outbox tombstone).
//!
//! [`apply_tag_patch`] is the pure resolver that merges
//! `tags_set` / `tags_add` / `tags_remove` against the current row tag
//! list — invoked from [`super::preparation`] so the final tag count can
//! be validated before any SQL runs.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::{TagId, TaskId, TaskTagEdgeId};
use lorvex_store::repositories::tag_repo;
use lorvex_store::StoreError;
use rusqlite::{params, Connection};

use super::super::mutation::{TaskTagEdgeDelete, TaskUpdateSyncEffects};

pub(in crate::task_update) fn replace_task_tags(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_id: &TaskId,
    new_tags: &[String],
    effects: &mut TaskUpdateSyncEffects,
) -> Result<(), StoreError> {
    let old_tags = find_task_tags(conn, task_id)?;
    let old_tag_ids = find_task_tag_ids(conn, task_id)?;
    let old_set = old_tags
        .iter()
        .map(String::as_str)
        .collect::<std::collections::HashSet<_>>();
    let new_set = new_tags
        .iter()
        .map(String::as_str)
        .collect::<std::collections::HashSet<_>>();

    let mut delete_stmt =
        conn.prepare_cached("DELETE FROM task_tags WHERE task_id = ?1 AND tag_id = ?2")?;
    for removed in old_set.difference(&new_set) {
        if let Some((_, tag_id, version, created_at)) = old_tag_ids
            .iter()
            .find(|(name, _, _, _)| name.as_str() == *removed)
        {
            delete_stmt.execute(params![task_id.as_str(), tag_id])?;
            effects
                .task_tag_edge_delete_ids
                .push(TaskTagEdgeId::new(task_id, &TagId::from_trusted_str(tag_id)).into_string());
            effects.deleted_task_tag_edges.push(TaskTagEdgeDelete {
                task_id: task_id.as_str().to_string(),
                tag_id: tag_id.clone(),
                version: version.clone(),
                created_at: created_at.clone(),
            });
        }
    }
    drop(delete_stmt);

    let now = lorvex_domain::sync_timestamp_now();
    let mut insert_stmt = conn.prepare_cached(
        "INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at) \
         VALUES (?1, ?2, ?3, ?4)",
    )?;
    for added in new_set.difference(&old_set) {
        let tag_version = hlc.next_version_string();
        let (tag_id, created) = tag_repo::resolve_or_create_tag(conn, added, &tag_version, &now)?;
        if created {
            effects.tag_upsert_ids.push(tag_id.clone());
        }
        let edge_version = hlc.next_version_string();
        insert_stmt.execute(params![task_id.as_str(), tag_id, edge_version, now])?;
        effects
            .task_tag_edge_upsert_ids
            .push(TaskTagEdgeId::new(task_id, &TagId::from_trusted_str(&tag_id)).into_string());
    }
    Ok(())
}

pub(in crate::task_update) fn find_task_tags(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT t.display_name FROM task_tags tt \
         JOIN tags t ON t.id = tt.tag_id \
         WHERE tt.task_id = ?1 ORDER BY tt.created_at ASC, tt.tag_id ASC",
    )?;
    let tags = stmt
        .query_map([task_id.as_str()], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(tags)
}

fn find_task_tag_ids(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<(String, String, String, String)>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT t.display_name, t.id, tt.version, tt.created_at FROM task_tags tt \
         JOIN tags t ON t.id = tt.tag_id \
         WHERE tt.task_id = ?1 ORDER BY tt.created_at ASC, tt.tag_id ASC",
    )?;
    let rows = stmt
        .query_map([task_id.as_str()], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

pub(in crate::task_update) fn apply_tag_patch(
    current_tags: &[String],
    tags_set: Option<Vec<String>>,
    tags_add: Option<Vec<String>>,
    tags_remove: Option<Vec<String>>,
) -> Vec<String> {
    if let Some(tags) = tags_set {
        return normalize_tags(tags);
    }
    let mut tags = normalize_tags(current_tags.to_vec());
    let remove_keys = normalize_tags(tags_remove.unwrap_or_default())
        .into_iter()
        .map(|tag| lorvex_domain::tag::normalize_lookup_key(&tag))
        .collect::<std::collections::HashSet<_>>();
    if !remove_keys.is_empty() {
        tags.retain(|tag| !remove_keys.contains(&lorvex_domain::tag::normalize_lookup_key(tag)));
    }
    if let Some(to_add) = tags_add {
        tags.extend(to_add);
    }
    normalize_tags(tags)
}

fn normalize_tags(tags: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    tags.into_iter()
        .map(|tag| tag.trim().to_string())
        .filter(|tag| !tag.is_empty() && seen.insert(lorvex_domain::tag::normalize_lookup_key(tag)))
        .collect()
}
