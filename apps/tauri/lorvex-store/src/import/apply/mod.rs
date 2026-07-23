//! The apply pipeline — restoring blob files, parsing JSONL streams, and
//! upserting every entity/edge/child/audit/tombstone/payload-shadow row from
//! the import archive into the SQLite database.
//!
//! The entry points (`apply_entities`, `apply_edges`, `apply_children`,
//! `apply_audit`, `apply_tombstones`, `apply_payload_shadows`,
//! `apply_provider_links`, `restore_blob_files`) are called from
//! `import_from_zip_with_options` in `super::mod.rs`. Per-entity helpers
//! (`upsert_*`, `materialize_*`, payload validators, version-aware replace
//! checks) live in `helpers.rs` and the per-domain files under `upserts/`.

use rusqlite::{Connection, OptionalExtension};

use lorvex_domain::naming::{EntityKind, EDGE_TASK_PROVIDER_EVENT_LINK, ENTITY_AI_CHANGELOG};

use crate::cancellation::check_import_cancelled;
use crate::CancellationToken;

mod helpers;
mod tombstones;
mod upserts;

pub(super) use helpers::required_bool_as_i64_field;
use helpers::JsonlLine;
pub(super) use helpers::{
    enforce_max_field_length, normalize_import_sync_timestamp, optional_string_field,
    parse_versioned_jsonl_line, required_object_array_field, required_string_array_field,
    required_string_field, required_sync_timestamp_field,
};
pub(super) use tombstones::apply_tombstones;
use upserts::{dispatch_child, dispatch_edge, dispatch_entity, UpsertResult};

use super::{ImportError, ImportSummary};

/// Apply entities from `entities.jsonl` content.
pub(super) fn apply_entities(
    conn: &Connection,
    content: &str,
    summary: &mut ImportSummary,
    cancellation: &dyn CancellationToken,
) -> Result<(), ImportError> {
    check_import_cancelled(cancellation)?;
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        check_import_cancelled(cancellation)?;
        let entry = parse_versioned_jsonl_line(line, "entities.jsonl")?;
        let entity_kind = entry.entity_type;
        let result = dispatch_entity(conn, &entry)?;
        match result {
            UpsertResult::Created => summary.entities_created += 1,
            UpsertResult::Updated => summary.entities_updated += 1,
            UpsertResult::Skipped => summary.entities_skipped += 1,
        }
        tally_entity_breakdown(entity_kind, result, summary);
    }
    Ok(())
}

/// #2368: populate the dry-run preview breakdown counts. Called for every
/// row processed in `apply_entities`; the commit path tallies the same
/// per-type counts so the UI/MCP client can show a "would create" view
/// consistent with what actually persisted on commit.
///
/// dispatches via [`EntityKind`] so a future
/// breakdown bucket addition is a typed compile-time decision rather
/// than another silent fall-through arm in a string-keyed match.
const fn tally_entity_breakdown(
    kind: EntityKind,
    result: UpsertResult,
    summary: &mut ImportSummary,
) {
    match kind {
        EntityKind::Task => match result {
            UpsertResult::Created => summary.tasks_to_create += 1,
            UpsertResult::Updated => summary.tasks_to_update += 1,
            UpsertResult::Skipped => summary.tasks_to_skip += 1,
        },
        EntityKind::List => {
            if matches!(result, UpsertResult::Created) {
                summary.lists_to_create += 1;
            }
        }
        EntityKind::Habit => {
            if matches!(result, UpsertResult::Created) {
                summary.habits_to_create += 1;
            }
        }
        EntityKind::Preference => {
            if matches!(result, UpsertResult::Created | UpsertResult::Updated) {
                summary.preferences_to_change += 1;
            }
        }
        EntityKind::Memory | EntityKind::MemoryRevision => {
            if matches!(result, UpsertResult::Created | UpsertResult::Updated) {
                summary.memory_to_write += 1;
            }
        }
        // Other syncable kinds tracked through the generic
        // entities_created / _updated / _skipped totals only — no
        // type-specific breakdown bucket exists for them today.
        EntityKind::Tag
        | EntityKind::CalendarEvent
        | EntityKind::DailyReview
        | EntityKind::CurrentFocus
        | EntityKind::FocusSchedule
        | EntityKind::CalendarSubscription
        | EntityKind::TaskReminder
        | EntityKind::TaskChecklistItem
        | EntityKind::HabitReminderPolicy
        | EntityKind::AiChangelog
        | EntityKind::TaskTag
        | EntityKind::TaskDependency
        | EntityKind::TaskCalendarEventLink
        | EntityKind::HabitCompletion
        | EntityKind::TaskProviderEventLink
        | EntityKind::DeviceState
        | EntityKind::SavedQuery
        | EntityKind::ImportSession => {}
    }
}

/// Apply edges from `edges.jsonl` content.
pub(super) fn apply_edges(
    conn: &Connection,
    content: &str,
    summary: &mut ImportSummary,
    cancellation: &dyn CancellationToken,
) -> Result<(), ImportError> {
    check_import_cancelled(cancellation)?;
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        check_import_cancelled(cancellation)?;
        let entry = parse_versioned_jsonl_line(line, "edges.jsonl")?;
        let result = dispatch_edge(conn, &entry)?;
        match result {
            UpsertResult::Created => summary.entities_created += 1,
            UpsertResult::Updated => summary.entities_updated += 1,
            UpsertResult::Skipped => summary.entities_skipped += 1,
        }
    }
    Ok(())
}

/// Apply children from `children.jsonl` content.
pub(super) fn apply_children(
    conn: &Connection,
    content: &str,
    summary: &mut ImportSummary,
    cancellation: &dyn CancellationToken,
) -> Result<(), ImportError> {
    check_import_cancelled(cancellation)?;
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        check_import_cancelled(cancellation)?;
        let entry = parse_versioned_jsonl_line(line, "children.jsonl")?;
        let result = dispatch_child(conn, &entry)?;
        match result {
            UpsertResult::Created => summary.entities_created += 1,
            UpsertResult::Updated => summary.entities_updated += 1,
            UpsertResult::Skipped => summary.entities_skipped += 1,
        }
    }
    Ok(())
}

/// Apply audit entries from `audit.jsonl` content.
pub(super) fn apply_audit(
    conn: &Connection,
    content: &str,
    summary: &mut ImportSummary,
    cancellation: &dyn CancellationToken,
) -> Result<(), ImportError> {
    check_import_cancelled(cancellation)?;
    // Hoist the per-row INSERT prepare out of the line loop. A 10k-row
    // audit archive pay 10k SQL parses; with prepare_cached
    // each row reuses the same statement.
    let mut insert_stmt = conn.prepare_cached(
        "INSERT OR IGNORE INTO ai_changelog
         (id, timestamp, operation, entity_type, entity_id,
          summary, initiated_by, mcp_tool, source_device_id,
          before_json, after_json, undo_token, is_preview)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
    )?;
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        check_import_cancelled(cancellation)?;
        let entry: JsonlLine = serde_json::from_str(line)?;
        if entry.entity_type != ENTITY_AI_CHANGELOG {
            continue;
        }
        let p = &entry.payload;
        let initiated_by = required_string_field(p, "initiated_by", "ai_changelog payload")?;
        // Trust-boundary filter (audit): the export side at
        // `lorvex-store/src/export/mod.rs::write_audit_rows` strips
        // human / system / user / manual rows that may have leaked
        // into the table. Mirror that filter on the import side so a
        // tampered or hand-edited archive cannot inject forbidden
        // `initiated_by` values into the canonical audit log used for
        // compliance, undo, and diff.
        const FORBIDDEN_INITIATED_BY: &[&str] = &["human", "system", "user", "manual"];
        if FORBIDDEN_INITIATED_BY.contains(&initiated_by.as_str()) {
            continue;
        }
        let changelog_id = required_string_field(p, "id", "ai_changelog payload")?;
        let entity_ids_json = optional_string_field(p, "entity_ids", "ai_changelog payload")?;
        let changed = insert_stmt.execute(rusqlite::params![
            &changelog_id,
            required_sync_timestamp_field(p, "timestamp", "ai_changelog payload")?,
            required_string_field(p, "operation", "ai_changelog payload")?,
            required_string_field(p, "entity_type", "ai_changelog payload")?,
            optional_string_field(p, "entity_id", "ai_changelog payload")?,
            required_string_field(p, "summary", "ai_changelog payload")?,
            initiated_by,
            optional_string_field(p, "mcp_tool", "ai_changelog payload")?,
            optional_string_field(p, "source_device_id", "ai_changelog payload")?,
            // structured before/after snapshots. Absent on
            // legacy exports.
            optional_string_field(p, "before_json", "ai_changelog payload")?,
            optional_string_field(p, "after_json", "ai_changelog payload")?,
            optional_string_field(p, "undo_token", "ai_changelog payload")?,
            match p.get("is_preview") {
                None | Some(serde_json::Value::Null) => 0,
                Some(_) => required_bool_as_i64_field(p, "is_preview", "ai_changelog payload")?,
            },
        ])?;
        // Audit: only bump on actual insert. The previous
        // unconditional bump inflated the dry-run preview's
        // `entities_created` whenever a duplicate id appeared.
        if changed > 0 {
            // Rehydrate the `ai_changelog_entities` registry from
            // the wire-form JSON array. Duplicate/skipped inserts
            // leave the existing registry untouched.
            let ids =
                crate::changelog::entities::parse_entity_ids_json(entity_ids_json.as_deref())?;
            crate::changelog::replace_changelog_entities(conn, &changelog_id, &ids)?;
            summary.entities_created += 1;
        }
    }
    Ok(())
}

pub(super) fn apply_payload_shadows(
    conn: &Connection,
    content: &str,
    cancellation: &dyn CancellationToken,
) -> Result<(), ImportError> {
    check_import_cancelled(cancellation)?;
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        check_import_cancelled(cancellation)?;
        let row: lorvex_sync_payload::payload_shadow::PayloadShadowRow =
            serde_json::from_str(line)?;
        lorvex_sync_payload::payload_shadow::restore_shadow(conn, &row)?;
    }
    Ok(())
}

/// per-field byte caps for the
/// `task_provider_event_links` import path.
///
/// `apply_provider_links` unwrapped each required string
/// without bounding its length. The schema (`task_provider_event_links`)
/// declares `provider_kind`/`provider_scope`/`provider_event_key` as
/// `TEXT NOT NULL` with no SQL-side length constraint, so a hostile
/// archive could land a megabyte-scale `provider_event_key` and
/// either inflate the row beyond practical sync limits or — because
/// the four columns form the table's PRIMARY KEY — bloat the
/// covering B-tree page count and degrade every read against the
/// task-event linker.
///
/// The caps below are sized to legitimate provider keys with
/// generous headroom: EventKit identifiers cap at ~150 chars, Google
/// Calendar event ids at 256, and our `ical_subscription` /
/// `linux_ics` synthetic keys typically stay under 1 KB. The `task_id`
/// is a UUIDv7 string at 36 bytes; `created_at`/`updated_at` are RFC
/// 3339 timestamps at ≤30 bytes — capped together at the same
/// `MAX_TIMESTAMP_LENGTH` because both flow to identical sync paths.
const MAX_PROVIDER_LINK_TASK_ID_LENGTH: usize = 64;
const MAX_PROVIDER_KIND_LENGTH: usize = 32;
const MAX_PROVIDER_SCOPE_LENGTH: usize = 256;
const MAX_PROVIDER_EVENT_KEY_LENGTH: usize = 1_024;
const MAX_PROVIDER_LINK_TIMESTAMP_LENGTH: usize = 64;

/// Apply local-only task↔provider event link rows from `provider_links.jsonl`.
///
/// These rows have no HLC version column. Conflict resolution uses
/// `updated_at` comparison: the newer `updated_at` wins.
pub(super) fn apply_provider_links(
    conn: &Connection,
    content: &str,
    summary: &mut ImportSummary,
    cancellation: &dyn CancellationToken,
) -> Result<(), ImportError> {
    check_import_cancelled(cancellation)?;
    let context = "task_provider_event_link payload";
    let mut insert_stmt = conn.prepare_cached(
        "INSERT OR IGNORE INTO task_provider_event_links
         (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
    )?;
    let mut select_existing_updated_at_stmt = conn.prepare_cached(
        "SELECT updated_at
         FROM task_provider_event_links
         WHERE task_id = ?1
           AND provider_kind = ?2
           AND provider_scope = ?3
           AND provider_event_key = ?4
         LIMIT 1",
    )?;
    let mut update_stmt = conn.prepare_cached(
        "UPDATE task_provider_event_links
         SET created_at = ?5,
             updated_at = ?6
         WHERE task_id = ?1
           AND provider_kind = ?2
           AND provider_scope = ?3
           AND provider_event_key = ?4",
    )?;
    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        check_import_cancelled(cancellation)?;
        let entry: JsonlLine = serde_json::from_str(line)?;
        if entry.entity_type != EDGE_TASK_PROVIDER_EVENT_LINK {
            return Err(helpers::invalid_payload(format!(
                "provider_links.jsonl entry has entity_type `{}`; expected `{EDGE_TASK_PROVIDER_EVENT_LINK}`",
                entry.entity_type
            )));
        }
        let p = &entry.payload;
        let task_id = enforce_max_field_length(
            required_string_field(p, "task_id", context)?,
            MAX_PROVIDER_LINK_TASK_ID_LENGTH,
            "task_id",
            context,
        )?;
        let provider_kind = enforce_max_field_length(
            required_string_field(p, "provider_kind", context)?,
            MAX_PROVIDER_KIND_LENGTH,
            "provider_kind",
            context,
        )?;
        let provider_scope = enforce_max_field_length(
            required_string_field(p, "provider_scope", context)?,
            MAX_PROVIDER_SCOPE_LENGTH,
            "provider_scope",
            context,
        )?;
        let provider_event_key = enforce_max_field_length(
            required_string_field(p, "provider_event_key", context)?,
            MAX_PROVIDER_EVENT_KEY_LENGTH,
            "provider_event_key",
            context,
        )?;
        let created_at = normalize_import_sync_timestamp(
            enforce_max_field_length(
                required_string_field(p, "created_at", context)?,
                MAX_PROVIDER_LINK_TIMESTAMP_LENGTH,
                "created_at",
                context,
            )?,
            "created_at",
            context,
        )?;
        let updated_at = normalize_import_sync_timestamp(
            enforce_max_field_length(
                required_string_field(p, "updated_at", context)?,
                MAX_PROVIDER_LINK_TIMESTAMP_LENGTH,
                "updated_at",
                context,
            )?,
            "updated_at",
            context,
        )?;

        let changes = insert_stmt.execute(rusqlite::params![
            task_id,
            provider_kind,
            provider_scope,
            provider_event_key,
            created_at,
            updated_at,
        ])?;
        if changes > 0 {
            summary.entities_created += 1;
        } else {
            let existing_updated_at: Option<String> = select_existing_updated_at_stmt
                .query_row(
                    rusqlite::params![task_id, provider_kind, provider_scope, provider_event_key,],
                    |row| row.get(0),
                )
                .optional()?;
            let Some(existing_updated_at) = existing_updated_at else {
                summary.entities_skipped += 1;
                continue;
            };
            let existing_updated_at = normalize_import_sync_timestamp(
                existing_updated_at,
                "updated_at",
                "existing task_provider_event_link row",
            )?;
            if updated_at > existing_updated_at {
                update_stmt.execute(rusqlite::params![
                    task_id,
                    provider_kind,
                    provider_scope,
                    provider_event_key,
                    created_at,
                    updated_at,
                ])?;
                summary.entities_updated += 1;
            } else {
                summary.entities_skipped += 1;
            }
        }
    }
    Ok(())
}
