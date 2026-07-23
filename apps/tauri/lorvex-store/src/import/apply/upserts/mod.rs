//! Per-entity upsert dispatch.
//!
//! `apply_entities` / `apply_edges` / `apply_children` in the parent `apply`
//! module call into the dispatch functions below, which fan out to the
//! per-domain upsert helpers in this module's submodules. The per-entity
//! helpers are version-aware: each compares the incoming HLC version against
//! the local row's version and keeps the newer one.

use rusqlite::{Connection, OptionalExtension};

use lorvex_domain::hlc::Hlc;
use lorvex_domain::naming::EntityKind;

use super::helpers::{invalid_payload, VersionedJsonlLine};
use crate::import::ImportError;

mod calendar;
mod focus;
mod habits;
mod lists;
mod memory;
mod preference;
mod tasks;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::import::apply) enum UpsertResult {
    Created,
    Updated,
    Skipped,
}

/// per-entity LWW upsert spec consumed by
/// [`import_lww_upsert`]. Carries the table + PK + version locator
/// (matched against [`should_replace_versioned`]) plus the two
/// prepared SQL strings for the INSERT and UPDATE branches. Several
/// per-domain `upsert_<entity>` functions spell out the same
/// `match should_replace_versioned { … }` skeleton inline; they now
/// call this dispatcher with a builder spec.
pub(in crate::import::apply::upserts) struct LwwUpsertSpec<'a> {
    pub(in crate::import::apply::upserts) table: &'static str,
    pub(in crate::import::apply::upserts) id_col: &'static str,
    pub(in crate::import::apply::upserts) id_val: &'a str,
    pub(in crate::import::apply::upserts) version: &'a str,
    pub(in crate::import::apply::upserts) insert_sql: &'static str,
    pub(in crate::import::apply::upserts) update_sql: &'static str,
}

/// Generic LWW-gated INSERT/UPDATE dispatcher for the simple-PK
/// import upserts. Returns `Created` / `Updated` / `Skipped` based on
/// whether the local row's version is older / missing / newer than
/// `spec.version`, matching the pre-collapse per-entity behavior.
///
/// The same `params` slice feeds both the INSERT and UPDATE bind
/// lists — every collapsed call site uses positional `?N` placeholders
/// that hold the same column order in both branches.
pub(in crate::import::apply::upserts) fn import_lww_upsert<P>(
    conn: &Connection,
    spec: &LwwUpsertSpec<'_>,
    params: P,
) -> Result<UpsertResult, ImportError>
where
    P: rusqlite::Params + Copy,
{
    match should_replace_versioned(conn, spec.table, spec.id_col, spec.id_val, spec.version)? {
        None => {
            conn.execute(spec.insert_sql, params)?;
            Ok(UpsertResult::Created)
        }
        Some(true) => {
            conn.execute(spec.update_sql, params)?;
            Ok(UpsertResult::Updated)
        }
        Some(false) => Ok(UpsertResult::Skipped),
    }
}

/// Compare two HLC version strings, mapping parse failures to typed
/// `ImportError::InvalidPayload` with the locator string the caller
/// already built so the diagnostic identifies the offending row.
///
/// Both callers below paid the same four-line `Hlc::parse` ×2 →
/// strict-greater compare; centralizing here keeps the error wording
/// (and any future "log + continue" decision) single-source.
fn incoming_dominates(existing: &str, incoming: &str, locator: &str) -> Result<bool, ImportError> {
    let existing_hlc = Hlc::parse(existing).map_err(|error| {
        invalid_payload(format!("local {locator} has invalid HLC version: {error}"))
    })?;
    let incoming_hlc = Hlc::parse(incoming).map_err(|error| {
        invalid_payload(format!(
            "incoming {locator} must use a valid HLC version: {error}"
        ))
    })?;
    Ok(incoming_hlc > existing_hlc)
}

/// Version-aware check: should we replace the existing row?
/// Compares the incoming version against the existing version.
pub(in crate::import::apply::upserts) fn should_replace_versioned(
    conn: &Connection,
    table: &str,
    id_col: &str,
    id_val: &str,
    incoming_version: &str,
) -> Result<Option<bool>, ImportError> {
    lorvex_domain::assert_safe_sql_identifier(table);
    lorvex_domain::assert_safe_sql_identifier(id_col);
    let sql = format!("SELECT version FROM {table} WHERE {id_col} = ?1");
    let existing: Option<String> = conn
        .query_row(&sql, [id_val], |row| row.get(0))
        .optional()?;

    match existing {
        None => Ok(None), // No existing row — should create.
        Some(existing_version) => Ok(Some(incoming_dominates(
            &existing_version,
            incoming_version,
            &format!("{table}.{id_col} `{id_val}`"),
        )?)),
    }
}

/// Like `should_replace_versioned`, but for tables with a two-column composite PK.
pub(in crate::import::apply::upserts) fn should_replace_versioned_composite(
    conn: &Connection,
    table: &str,
    pk_col_a: &str,
    pk_val_a: &str,
    pk_col_b: &str,
    pk_val_b: &str,
    incoming_version: &str,
) -> Result<Option<bool>, ImportError> {
    lorvex_domain::assert_safe_sql_identifier(table);
    lorvex_domain::assert_safe_sql_identifier(pk_col_a);
    lorvex_domain::assert_safe_sql_identifier(pk_col_b);
    let sql = format!("SELECT version FROM {table} WHERE {pk_col_a} = ?1 AND {pk_col_b} = ?2");
    let existing: Option<String> = conn
        .query_row(&sql, rusqlite::params![pk_val_a, pk_val_b], |row| {
            row.get(0)
        })
        .optional()?;

    match existing {
        None => Ok(None),
        Some(existing_version) => Ok(Some(incoming_dominates(
            &existing_version,
            incoming_version,
            &format!("{table} ({pk_col_a}=`{pk_val_a}`, {pk_col_b}=`{pk_val_b}`)"),
        )?)),
    }
}

fn wrong_stream(stream_name: &str, kind: EntityKind) -> ImportError {
    invalid_payload(format!(
        "{stream_name} cannot contain `{}` rows; this entity type belongs in a different import stream",
        kind.as_str()
    ))
}

/// Dispatch a parsed `entities.jsonl` row to the matching per-entity upsert.
///
/// Matches on the typed [`EntityKind`] enum parsed once at
/// `parse_versioned_jsonl_line` rather than re-comparing strings at
/// every dispatch site. Wrong-stream kinds are hard errors so snapshot
/// restore cannot silently drop archive rows.
pub(in crate::import::apply) fn dispatch_entity(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    match entry.entity_type {
        EntityKind::List => lists::upsert_list(conn, entry),
        EntityKind::Task => tasks::upsert_task(conn, entry),
        EntityKind::Tag => lists::upsert_tag(conn, entry),
        EntityKind::Habit => habits::upsert_habit(conn, entry),
        EntityKind::CalendarEvent => calendar::upsert_calendar_event(conn, entry),
        EntityKind::CalendarSubscription => calendar::upsert_calendar_subscription(conn, entry),
        EntityKind::Preference => preference::upsert_preference(conn, entry),
        EntityKind::Memory => memory::upsert_memory(conn, entry),
        EntityKind::MemoryRevision => memory::upsert_memory_revision(conn, entry),
        EntityKind::DailyReview => focus::upsert_daily_review(conn, entry),
        EntityKind::CurrentFocus => focus::upsert_current_focus(conn, entry),
        EntityKind::FocusSchedule => focus::upsert_focus_schedule(conn, entry),
        EntityKind::TaskTag
        | EntityKind::TaskDependency
        | EntityKind::TaskCalendarEventLink
        | EntityKind::HabitCompletion
        | EntityKind::TaskProviderEventLink
        | EntityKind::TaskReminder
        | EntityKind::TaskChecklistItem
        | EntityKind::HabitReminderPolicy
        | EntityKind::AiChangelog
        | EntityKind::DeviceState
        | EntityKind::SavedQuery
        | EntityKind::ImportSession => Err(wrong_stream("entities.jsonl", entry.entity_type)),
    }
}

/// Dispatch a parsed `edges.jsonl` row.
///
/// Typed [`EntityKind`] dispatch — same shape as `dispatch_entity`.
pub(in crate::import::apply) fn dispatch_edge(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    match entry.entity_type {
        EntityKind::TaskTag => tasks::upsert_task_tag(conn, entry),
        EntityKind::TaskDependency => tasks::upsert_task_dependency(conn, entry),
        EntityKind::TaskCalendarEventLink => tasks::upsert_task_calendar_event_link(conn, entry),
        EntityKind::HabitCompletion => habits::upsert_habit_completion(conn, entry),
        EntityKind::Task
        | EntityKind::List
        | EntityKind::Tag
        | EntityKind::Habit
        | EntityKind::CalendarEvent
        | EntityKind::Preference
        | EntityKind::Memory
        | EntityKind::MemoryRevision
        | EntityKind::DailyReview
        | EntityKind::CurrentFocus
        | EntityKind::FocusSchedule
        | EntityKind::CalendarSubscription
        | EntityKind::TaskReminder
        | EntityKind::TaskChecklistItem
        | EntityKind::HabitReminderPolicy
        | EntityKind::AiChangelog
        | EntityKind::TaskProviderEventLink
        | EntityKind::DeviceState
        | EntityKind::SavedQuery
        | EntityKind::ImportSession => Err(wrong_stream("edges.jsonl", entry.entity_type)),
    }
}

/// Dispatch a parsed `children.jsonl` row.
///
/// typed [`EntityKind`] dispatch.
pub(in crate::import::apply) fn dispatch_child(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    match entry.entity_type {
        EntityKind::TaskReminder => tasks::upsert_task_reminder(conn, entry),
        EntityKind::TaskChecklistItem => tasks::upsert_task_checklist_item(conn, entry),
        EntityKind::HabitReminderPolicy => habits::upsert_habit_reminder_policy(conn, entry),
        EntityKind::Task
        | EntityKind::List
        | EntityKind::Tag
        | EntityKind::Habit
        | EntityKind::CalendarEvent
        | EntityKind::Preference
        | EntityKind::Memory
        | EntityKind::MemoryRevision
        | EntityKind::DailyReview
        | EntityKind::CurrentFocus
        | EntityKind::FocusSchedule
        | EntityKind::CalendarSubscription
        | EntityKind::TaskTag
        | EntityKind::TaskDependency
        | EntityKind::TaskCalendarEventLink
        | EntityKind::HabitCompletion
        | EntityKind::TaskProviderEventLink
        | EntityKind::AiChangelog
        | EntityKind::DeviceState
        | EntityKind::SavedQuery
        | EntityKind::ImportSession => Err(wrong_stream("children.jsonl", entry.entity_type)),
    }
}
