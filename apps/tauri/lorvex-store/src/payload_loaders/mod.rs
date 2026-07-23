//! Per-entity sync payload builders for "simple" (non-aggregate-with-
//! embedded-children) entity types.
//!
//! This module is the single source of truth for the wire shape of each
//! entity's sync envelope payload across every surface that builds one
//! by hand:
//!
//! * The first-time-seed flow in
//!   `app/src-tauri/src/commands/sync_runtime/queue/seed.rs`
//!   (one full-table scan per entity_type, streaming each row into the
//!   outbox).
//! * The runtime per-id enqueue helpers in
//!   `app/src-tauri/src/commands/sync_runtime/queue/enqueue/`
//!   (`task_entities::load_tag_sync_payload`,
//!   `child_items::load_task_*_sync_payload`,
//!   `edge_snapshots::load_*_pre_delete_snapshot`, …).
//!
//! This module owns the canonical `SELECT … FROM <table>` literal +
//! `serde_json::json!({ … })` payload builder for each entity, so the
//! seed surface and the runtime per-id enqueue helpers share one
//! definition. Hand-rolling these per surface drifts on a
//! column-by-column basis (seed shipping `tag` rows without `version`
//! while the runtime helper shipped them with `version`, etc.) and
//! makes adding a column an N-site edit with no compile-time link
//! between them.
//!
//! The public surface is intentionally narrow:
//!
//! * Point-lookup / tombstone helpers for runtime enqueue paths.
//! * Payload constructor helpers for mutation paths that already hold
//!   typed row values.
//! * [`for_each_simple_sync_payload`] for first-time full-sync seed scans.
//!
//! SELECT column constants and row mappers stay private to `lorvex-store`.
//! Seed callers ask for a typed [`SimpleSyncSeedKind`] and receive
//! `(entity_id, payload)` callbacks; they do not own the SQL projection
//! or mapper internals.
//!
//! Aggregate roots whose envelope embeds materialized child rows
//! (`current_focus`, `focus_schedule`, `daily_review`, `calendar_event`)
//! are intentionally NOT covered here — they keep flowing through
//! [`lorvex_sync::payload_build::aggregate::build_aggregate_payload`], which is the
//! canonical builder for that family. See that module's header comment
//! for the rationale.

mod ai_changelog;
mod calendar_subscription;
mod cascade;
mod habit;
mod habit_completion;
mod habit_reminder_policy;
mod list;
mod memory;
mod memory_revision;
mod preference;
mod tag;
mod task_calendar_event_link;
mod task_checklist_item;
mod task_dependency;
mod task_reminder;
mod task_tag;

use std::fmt;

use rusqlite::{Connection, Row};
use serde_json::Value;

use crate::error::StoreError;

pub use calendar_subscription::{
    calendar_subscription_payload, load_calendar_subscription_sync_payload,
    CalendarSubscriptionPayload,
};
pub use cascade::{
    load_habit_completions_for_habit, load_habit_reminder_policies_for_habit,
    load_task_calendar_event_link_pre_delete_snapshots,
    load_task_calendar_event_links_for_calendar_event, load_task_calendar_event_links_for_task,
    load_task_checklist_item_pre_delete_snapshots, load_task_checklist_items_for_task,
    load_task_dependencies_for_task, load_task_reminder_pre_delete_snapshots,
    load_task_reminders_for_task, load_task_tag_pre_delete_snapshots, load_task_tags_for_task,
};
pub use habit::load_habit_sync_payload;
pub(crate) use habit::{habit_payload_from_row, HABIT_SELECT_COLUMNS};
pub use habit_completion::{habit_completion_payload, load_habit_completion_sync_payload};
pub use habit_reminder_policy::habit_reminder_policy_payload;
pub use list::list_payload;
pub use memory::{load_memory_delete_snapshot, memory_payload};
pub use memory_revision::load_memory_revision_sync_payload;
pub use preference::{
    load_preference_delete_snapshot, load_preference_sync_payload, preference_upsert_payload,
};
pub use tag::load_tag_sync_payload;
pub use task_calendar_event_link::{
    load_task_calendar_event_link_sync_payload, task_calendar_event_link_payload,
};
pub use task_checklist_item::load_task_checklist_item_sync_payload;
pub use task_dependency::task_dependency_payload;
pub use task_reminder::load_task_reminder_sync_payload;
pub use task_tag::{load_task_tag_sync_payload, task_tag_payload};

/// Simple sync entity families that can be streamed directly from one
/// table row into one sync payload. Aggregate roots stay on
/// `aggregate_payload`, and enriched entities such as tasks/lists keep
/// their Tauri-side enqueue helpers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SimpleSyncSeedKind {
    Preference,
    Memory,
    TaskCalendarEventLink,
    Habit,
    HabitCompletion,
    HabitReminderPolicy,
    Tag,
    TaskTag,
    TaskDependency,
    MemoryRevision,
    AiChangelog,
    CalendarSubscription,
}

#[derive(Debug)]
pub enum SimpleSyncPayloadSeedError<E> {
    Store(StoreError),
    Callback(E),
}

impl<E: fmt::Display> fmt::Display for SimpleSyncPayloadSeedError<E> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Store(error) => write!(f, "{error}"),
            Self::Callback(error) => write!(f, "{error}"),
        }
    }
}

impl<E: std::error::Error + 'static> std::error::Error for SimpleSyncPayloadSeedError<E> {}

impl<E> From<StoreError> for SimpleSyncPayloadSeedError<E> {
    fn from(error: StoreError) -> Self {
        Self::Store(error)
    }
}

type SeedResult<T, E> = Result<T, SimpleSyncPayloadSeedError<E>>;

/// Stream canonical simple-entity sync payloads from store-owned SQL
/// projections and row mappers. The callback receives `(entity_id,
/// payload)` and decides what to do with the envelope, which keeps the
/// writer/outbox policy at the caller while keeping row internals in
/// `lorvex-store`.
pub fn for_each_simple_sync_payload<E, F>(
    conn: &Connection,
    kind: SimpleSyncSeedKind,
    callback: F,
) -> SeedResult<i64, E>
where
    F: FnMut(String, Value) -> Result<(), E>,
{
    match kind {
        SimpleSyncSeedKind::Preference => scan_preferences(conn, callback),
        SimpleSyncSeedKind::Memory => scan_payload_rows(
            conn,
            "memories",
            memory::MEMORY_SELECT_COLUMNS,
            "key",
            memory::memory_payload_from_row,
            id_from_str_field("key"),
            callback,
        ),
        SimpleSyncSeedKind::TaskCalendarEventLink => scan_payload_rows(
            conn,
            "task_calendar_event_links",
            task_calendar_event_link::TASK_CALENDAR_EVENT_LINK_SELECT_COLUMNS,
            "created_at",
            task_calendar_event_link::task_calendar_event_link_payload_from_row,
            id_from_two_str_fields("task_id", "calendar_event_id"),
            callback,
        ),
        SimpleSyncSeedKind::Habit => scan_payload_rows(
            conn,
            "habits",
            habit::HABIT_SELECT_COLUMNS,
            "created_at",
            habit::habit_payload_from_row,
            id_from_str_field("id"),
            callback,
        ),
        SimpleSyncSeedKind::HabitCompletion => scan_payload_rows(
            conn,
            "habit_completions",
            habit_completion::HABIT_COMPLETION_SELECT_COLUMNS,
            "completed_date DESC",
            habit_completion::habit_completion_payload_from_row,
            id_from_two_str_fields("habit_id", "completed_date"),
            callback,
        ),
        SimpleSyncSeedKind::HabitReminderPolicy => scan_payload_rows(
            conn,
            "habit_reminder_policies",
            habit_reminder_policy::HABIT_REMINDER_POLICY_SELECT_COLUMNS,
            "created_at",
            habit_reminder_policy::habit_reminder_policy_payload_from_row,
            id_from_str_field("id"),
            callback,
        ),
        SimpleSyncSeedKind::Tag => scan_payload_rows(
            conn,
            "tags",
            tag::TAG_SELECT_COLUMNS,
            "created_at",
            tag::tag_payload_from_row,
            id_from_str_field("id"),
            callback,
        ),
        SimpleSyncSeedKind::TaskTag => scan_payload_rows(
            conn,
            "task_tags",
            task_tag::TASK_TAG_SELECT_COLUMNS,
            "created_at",
            task_tag::task_tag_payload_from_row,
            id_from_two_str_fields("task_id", "tag_id"),
            callback,
        ),
        SimpleSyncSeedKind::TaskDependency => scan_payload_rows(
            conn,
            "task_dependencies",
            task_dependency::TASK_DEPENDENCY_SELECT_COLUMNS,
            "created_at",
            task_dependency::task_dependency_payload_from_row,
            id_from_two_str_fields("task_id", "depends_on_task_id"),
            callback,
        ),
        SimpleSyncSeedKind::MemoryRevision => scan_payload_rows(
            conn,
            "memory_revisions",
            memory_revision::MEMORY_REVISION_SELECT_COLUMNS,
            "created_at",
            memory_revision::memory_revision_payload_from_row,
            id_from_str_field("id"),
            callback,
        ),
        SimpleSyncSeedKind::AiChangelog => scan_ai_changelog(conn, callback),
        SimpleSyncSeedKind::CalendarSubscription => scan_payload_rows(
            conn,
            "calendar_subscriptions",
            calendar_subscription::CALENDAR_SUBSCRIPTION_SELECT_COLUMNS,
            "created_at",
            calendar_subscription::calendar_subscription_payload_from_row,
            id_from_str_field("id"),
            callback,
        ),
    }
}

fn scan_payload_rows<E, F, R, I>(
    conn: &Connection,
    table: &str,
    select_columns: &str,
    order_by: &str,
    row_mapper: R,
    entity_id_from_payload: I,
    mut callback: F,
) -> SeedResult<i64, E>
where
    F: FnMut(String, Value) -> Result<(), E>,
    R: Fn(&Row<'_>) -> rusqlite::Result<Value>,
    I: Fn(&Value) -> String,
{
    let sql = format!("SELECT {select_columns} FROM {table} ORDER BY {order_by}");
    scan_sql(
        conn,
        table,
        &sql,
        |row| {
            let payload = row_mapper(row)?;
            let entity_id = entity_id_from_payload(&payload);
            Ok((entity_id, payload))
        },
        &mut callback,
    )
}

fn scan_sql<E, F, R>(
    conn: &Connection,
    label: &str,
    sql: &str,
    row_mapper: R,
    callback: &mut F,
) -> SeedResult<i64, E>
where
    F: FnMut(String, Value) -> Result<(), E>,
    R: Fn(&Row<'_>) -> rusqlite::Result<(String, Value)>,
{
    let mut stmt = conn.prepare_cached(sql).map_err(StoreError::from)?;
    let mut rows = stmt.query([]).map_err(StoreError::from)?;
    let mut count = 0;
    while let Some(row) = rows.next().map_err(StoreError::from)? {
        let (entity_id, payload) = row_mapper(row).map_err(|error| {
            StoreError::Invariant(format!("failed to read {label} seed row: {error}"))
        })?;
        callback(entity_id, payload).map_err(SimpleSyncPayloadSeedError::Callback)?;
        count += 1;
    }
    Ok(count)
}

fn scan_preferences<E, F>(conn: &Connection, mut callback: F) -> SeedResult<i64, E>
where
    F: FnMut(String, Value) -> Result<(), E>,
{
    let sql = format!(
        "SELECT {cols} FROM preferences WHERE updated_at IS NOT NULL ORDER BY key",
        cols = preference::PREFERENCE_UPSERT_SELECT_COLUMNS,
    );
    let mut stmt = conn.prepare_cached(&sql).map_err(StoreError::from)?;
    let mut rows = stmt.query([]).map_err(StoreError::from)?;
    let mut count = 0;
    while let Some(row) = rows.next().map_err(StoreError::from)? {
        let key: String = row.get(0).map_err(StoreError::from)?;
        let value_raw: String = row.get(1).map_err(StoreError::from)?;
        let updated_at: String = row.get(2).map_err(StoreError::from)?;
        if lorvex_domain::preference_keys::is_local_only_preference(&key) {
            continue;
        }
        let payload = preference::preference_upsert_payload(&key, &value_raw, &updated_at)
            .map_err(SimpleSyncPayloadSeedError::Store)?;
        callback(key, payload).map_err(SimpleSyncPayloadSeedError::Callback)?;
        count += 1;
    }
    Ok(count)
}

fn scan_ai_changelog<E, F>(conn: &Connection, mut callback: F) -> SeedResult<i64, E>
where
    F: FnMut(String, Value) -> Result<(), E>,
{
    let sql = format!(
        "SELECT {cols} FROM ai_changelog WHERE is_preview = 0 ORDER BY timestamp",
        cols = ai_changelog::AI_CHANGELOG_SELECT_COLUMNS,
    );
    scan_sql(
        conn,
        "ai_changelog",
        &sql,
        |row| {
            let payload = ai_changelog::ai_changelog_payload_from_row(row)?;
            let id = payload
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or_else(|| {
                    panic!(
                        "seed: ai_changelog payload missing required string `id` field: {payload}"
                    )
                })
                .to_string();
            Ok((id, payload))
        },
        &mut callback,
    )
}

fn id_from_str_field(field: &'static str) -> impl Fn(&Value) -> String {
    move |payload| {
        payload
            .get(field)
            .and_then(Value::as_str)
            .unwrap_or_else(|| {
                panic!("seed payload missing required string field `{field}`: {payload}")
            })
            .to_string()
    }
}

fn id_from_two_str_fields(first: &'static str, second: &'static str) -> impl Fn(&Value) -> String {
    move |payload| {
        let a = payload
            .get(first)
            .and_then(Value::as_str)
            .unwrap_or_else(|| {
                panic!("seed payload missing required string field `{first}`: {payload}")
            });
        let b = payload
            .get(second)
            .and_then(Value::as_str)
            .unwrap_or_else(|| {
                panic!("seed payload missing required string field `{second}`: {payload}")
            });
        format!("{a}:{b}")
    }
}

#[cfg(test)]
mod tests;
