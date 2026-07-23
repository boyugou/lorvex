//! [`Mutation`] descriptors for the `current_focus` aggregate.
//!
//! The four operations — set (replace), add (additive), remove
//! (single-task subtract), clear (delete) — share one parent row
//! plus its `current_focus_items` child sub-table. Each descriptor
//! captures already-validated, already-resolved inputs and on `apply`
//! stamps the canonical `(version, updated_at)` pair onto the header
//! and re-materializes the items child rows in a single transaction.
//!
//! Surfaces (MCP, Tauri, CLI, sync apply) construct the descriptor
//! and dispatch it through their own executor — finalizer / changelog
//! / sync enqueue plumbing stays on the surface side so the canonical
//! apply path can be shared without bringing the host's audit
//! conventions into the workflow crate.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_CURRENT_FOCUS, OP_DELETE};
use lorvex_store::current_focus_items::{
    delete_current_focus, materialize_focus_items_with_header_bump, query_focus_task_ids,
    touch_current_focus_header, upsert_current_focus_header,
};
use lorvex_store::StoreError;
use rusqlite::{Connection, OptionalExtension};
use serde_json::{json, Map, Value};

use crate::mutation::{Mutation, MutationOutput};

/// Defensive upper bound — prevents extreme payloads, not a product
/// limit. The AI naturally limits by available working hours.
pub const CURRENT_FOCUS_TASK_IDS_MAX: usize = 50;

/// Load the `current_focus` row for `date` and enrich it with the
/// derived `task_ids` array fetched from the `current_focus_items`
/// sub-table. Returns `Ok(None)` when no parent row exists.
///
/// Shared with surface adapters so the pre-snapshot capture and the
/// post-apply response carry the same canonical JSON shape.
pub fn load_current_focus_enriched(
    conn: &Connection,
    date: &str,
) -> Result<Option<Value>, StoreError> {
    struct Header {
        briefing: Option<String>,
        timezone: Option<String>,
        version: String,
        created_at: String,
        updated_at: String,
    }
    let header: Option<Header> = conn
        .query_row(
            "SELECT briefing, timezone, version, created_at, updated_at \
             FROM current_focus WHERE date = ?1",
            [date],
            |row| {
                Ok(Header {
                    briefing: row.get(0)?,
                    timezone: row.get(1)?,
                    version: row.get(2)?,
                    created_at: row.get(3)?,
                    updated_at: row.get(4)?,
                })
            },
        )
        .optional()?;
    let Some(Header {
        briefing,
        timezone,
        version,
        created_at,
        updated_at,
    }) = header
    else {
        return Ok(None);
    };
    let task_ids = query_focus_task_ids(conn, date)?;
    let mut object = Map::with_capacity(7);
    object.insert("date".to_string(), Value::String(date.to_string()));
    object.insert(
        "briefing".to_string(),
        briefing.map_or(Value::Null, Value::String),
    );
    object.insert(
        "timezone".to_string(),
        timezone.map_or(Value::Null, Value::String),
    );
    object.insert("version".to_string(), Value::String(version));
    object.insert("created_at".to_string(), Value::String(created_at));
    object.insert("updated_at".to_string(), Value::String(updated_at));
    object.insert(
        "task_ids".to_string(),
        Value::Array(task_ids.into_iter().map(Value::String).collect()),
    );
    Ok(Some(Value::Object(object)))
}

/// Replace the current focus plan for `date` with `task_ids`.
///
/// `before` is the pre-mutation enriched snapshot; the descriptor
/// records `operation == "update"` when it is `Some`, `"create"`
/// otherwise.
pub struct SetCurrentFocusMutation {
    pub date: String,
    pub task_ids: Vec<String>,
    pub briefing: Option<String>,
    pub timezone: String,
    pub now: String,
    pub before: Option<Value>,
    pub operation: &'static str,
}

impl Mutation for SetCurrentFocusMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CURRENT_FOCUS
    }

    fn operation(&self) -> &'static str {
        self.operation
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone().unwrap_or(Value::Null)))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        upsert_current_focus_header(
            conn,
            &self.date,
            self.briefing.as_deref(),
            &self.timezone,
            &version,
            &self.now,
        )?;

        materialize_focus_items_with_header_bump(
            conn,
            &self.date,
            &self.task_ids,
            &version,
            &self.now,
        )?;

        let plan = load_current_focus_enriched(conn, &self.date)?.ok_or_else(|| {
            StoreError::Invariant(format!("Failed to load current focus '{}'", self.date))
        })?;
        Ok(MutationOutput::new(
            plan,
            format!(
                "Set current focus for {} with {} tasks",
                self.date,
                self.task_ids.len()
            ),
        ))
    }
}

/// Additive merge into the current focus plan for `date`.
///
/// `merged_ids` is the caller-deduped final list (existing ∪ new);
/// `added_count = merged_ids.len() - before.task_ids.len()` is
/// surfaced in the human summary.
pub struct AddToCurrentFocusMutation {
    pub date: String,
    pub merged_ids: Vec<String>,
    pub briefing: Option<String>,
    pub timezone: String,
    pub now: String,
    pub before: Option<Value>,
    pub added_count: usize,
}

impl Mutation for AddToCurrentFocusMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CURRENT_FOCUS
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone().unwrap_or(Value::Null)))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        if self.before.is_some() {
            if let Some(ref new_briefing) = self.briefing {
                upsert_current_focus_header(
                    conn,
                    &self.date,
                    Some(new_briefing),
                    &self.timezone,
                    &version,
                    &self.now,
                )?;
            } else {
                touch_current_focus_header(conn, &self.date, Some(&version), &self.now)?;
            }
        } else {
            upsert_current_focus_header(
                conn,
                &self.date,
                self.briefing.as_deref(),
                &self.timezone,
                &version,
                &self.now,
            )?;
        }

        materialize_focus_items_with_header_bump(
            conn,
            &self.date,
            &self.merged_ids,
            &version,
            &self.now,
        )?;

        let plan = load_current_focus_enriched(conn, &self.date)?.ok_or_else(|| {
            StoreError::Invariant(format!("Failed to load current focus '{}'", self.date))
        })?;
        Ok(MutationOutput::new(
            plan,
            format!(
                "Added {} task(s) to current focus for {} (total: {})",
                self.added_count,
                self.date,
                self.merged_ids.len()
            ),
        ))
    }
}

/// Clear the current focus plan for `date` (delete parent + items).
///
/// `before` is the pre-clear enriched snapshot threaded into both
/// the changelog `before_json` and the tombstone payload by the
/// surface-side finalizer.
pub struct ClearCurrentFocusMutation {
    pub date: String,
    pub before: Value,
}

impl Mutation for ClearCurrentFocusMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CURRENT_FOCUS
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(
        &self,
        conn: &Connection,
        _hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let cleared = delete_current_focus(conn, &self.date)?;
        Ok(MutationOutput::new(
            json!({
                "cleared": cleared,
                "date": self.date.as_str(),
                "current": Value::Null,
                "previous": self.before.clone(),
            }),
            format!("Cleared current focus for {}", self.date),
        ))
    }
}

/// Remove a single task from the current focus plan for `date`.
///
/// `remaining_task_ids` is the caller-computed post-remove list; when
/// it is empty the descriptor falls back to `delete_current_focus`
/// so the parent row tombstones in lockstep with the empty child set.
pub struct RemoveFromCurrentFocusMutation {
    pub date: String,
    pub task_id: String,
    pub remaining_task_ids: Vec<String>,
    pub now: String,
    pub before: Value,
}

impl Mutation for RemoveFromCurrentFocusMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_CURRENT_FOCUS
    }

    fn operation(&self) -> &'static str {
        if self.remaining_task_ids.is_empty() {
            OP_DELETE
        } else {
            "update"
        }
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        if self.remaining_task_ids.is_empty() {
            delete_current_focus(conn, &self.date)?;
            return Ok(MutationOutput::new(
                json!({
                    "removed": true,
                    "task_id": self.task_id.as_str(),
                    "date": self.date.as_str(),
                    "plan_cleared": true,
                    "remaining_tasks": 0,
                }),
                format!(
                    "Removed last task {} from current focus for {}, plan cleared",
                    self.task_id, self.date
                ),
            ));
        }

        let version = hlc.next_version_string();
        materialize_focus_items_with_header_bump(
            conn,
            &self.date,
            &self.remaining_task_ids,
            &version,
            &self.now,
        )?;

        let plan = load_current_focus_enriched(conn, &self.date)?.ok_or_else(|| {
            StoreError::Invariant(format!("Failed to load current focus '{}'", self.date))
        })?;

        Ok(MutationOutput::new(
            plan,
            format!(
                "Removed task {} from current focus for {} (remaining: {})",
                self.task_id,
                self.date,
                self.remaining_task_ids.len()
            ),
        ))
    }
}
