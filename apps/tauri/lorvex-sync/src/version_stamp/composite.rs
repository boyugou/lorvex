//! Composite-PK (`a:b`) edge stamping for `task_tag`, `task_dependency`,
//! `task_calendar_event_link`, and `habit_completion`.

use lorvex_domain::naming::*;
use rusqlite::Connection;

use super::error::VersionStampError;
use super::predicates::classify_post_update_existing;
use super::SYNCABLE_ENTITY_VERSION_IS_NOT_NULL;

pub(super) fn stamp_composite_entity_version(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    version: &str,
) -> Result<(), VersionStampError> {
    if entity_type == ENTITY_AI_CHANGELOG {
        return Ok(());
    }

    // reject ids with extra colons or empty halves so a
    // malformed peer envelope can't inject ghost edges. Matches the
    // strict split in `lorvex-sync::composite_edge::split_composite_edge_id`.
    let colon_count = entity_id.bytes().filter(|b| *b == b':').count();
    if colon_count != 1 {
        return Err(VersionStampError::InvalidCompositeEntityId {
            entity_type: entity_type.to_string(),
            entity_id: entity_id.to_string(),
        });
    }
    let (a, b) =
        entity_id
            .split_once(':')
            .ok_or_else(|| VersionStampError::InvalidCompositeEntityId {
                entity_type: entity_type.to_string(),
                entity_id: entity_id.to_string(),
            })?;
    if a.is_empty() || b.is_empty() {
        return Err(VersionStampError::InvalidCompositeEntityId {
            entity_type: entity_type.to_string(),
            entity_id: entity_id.to_string(),
        });
    }

    // same LWW guard on composite-PK edge tables.
    // literal SQL per arm — no `format!` interpolation
    // means the previous `assert_safe_sql_identifier` panic guard is
    // no longer needed at call time.
    // each arm now also pre-bakes a `read_version`
    // SELECT so a superseded composite stamp surfaces as a typed
    // `VersionStampError::Superseded { existing_version }` populated
    // from a real read of the row.
    // dispatch on `EntityKind` so
    // unrecognized strings funnel through the same
    // `UnsupportedEntityType` typed error as before, while a future
    // edge variant must be classified explicitly to compile.
    let kind = EntityKind::parse(entity_type)
        .ok_or_else(|| VersionStampError::UnsupportedEntityType(entity_type.to_string()))?;
    // composite-PK arms also have `version NOT NULL`. Drop the
    // dead `OR version IS NULL` branch from each LWW guard.
    const {
        assert!(
            SYNCABLE_ENTITY_VERSION_IS_NOT_NULL,
            "every syncable entity table must declare `version NOT NULL`; \
             a `false` here means a new table was added without the constraint",
        );
    }
    let (update_sql, read_version_sql) = match kind {
        EntityKind::TaskCalendarEventLink => (
            "UPDATE task_calendar_event_links SET version = ?1 \
             WHERE task_id = ?2 AND calendar_event_id = ?3 \
               AND ?1 > version",
            "SELECT version FROM task_calendar_event_links \
             WHERE task_id = ?1 AND calendar_event_id = ?2",
        ),
        EntityKind::HabitCompletion => (
            "UPDATE habit_completions SET version = ?1 \
             WHERE habit_id = ?2 AND completed_date = ?3 \
               AND ?1 > version",
            "SELECT version FROM habit_completions \
             WHERE habit_id = ?1 AND completed_date = ?2",
        ),
        EntityKind::TaskTag => (
            "UPDATE task_tags SET version = ?1 \
             WHERE task_id = ?2 AND tag_id = ?3 \
               AND ?1 > version",
            "SELECT version FROM task_tags \
             WHERE task_id = ?1 AND tag_id = ?2",
        ),
        EntityKind::TaskDependency => (
            "UPDATE task_dependencies SET version = ?1 \
             WHERE task_id = ?2 AND depends_on_task_id = ?3 \
               AND ?1 > version",
            "SELECT version FROM task_dependencies \
             WHERE task_id = ?1 AND depends_on_task_id = ?2",
        ),
        // Simple-PK / audit / local-only kinds reach this branch via
        // a programmer error — `stamp_entity_version` routes simple
        // PKs through `simple_pk_sql` and exempts ai_changelog. We
        // still surface the typed `UnsupportedEntityType` rather
        // than panic so the caller's recovery path stays unchanged.
        _ => {
            return Err(VersionStampError::UnsupportedEntityType(
                entity_type.to_string(),
            ));
        }
    };

    // Both UPDATE and the fallback SELECT come from a fixed
    // (entity_kind → SQL) dispatch table just above (`composite_pk_sql`),
    // so `prepare_cached` caches each branch's plan across the apply
    // pipeline's lifetime. Composite-PK stamps run once per child/edge
    let rows = conn
        .prepare_cached(update_sql)?
        .execute(rusqlite::params![version, a, b])?;
    if rows == 0 {
        // read the existing version to distinguish
        // "row missing" from "concurrent writer set a newer version".
        let existing: Option<Option<String>> = match conn
            .prepare_cached(read_version_sql)?
            .query_row(rusqlite::params![a, b], |row| {
                row.get::<_, Option<String>>(0)
            }) {
            Ok(v) => Some(v),
            Err(rusqlite::Error::QueryReturnedNoRows) => None,
            Err(other) => return Err(other.into()),
        };
        // Same three-arm classifier the simple-PK path uses
        // (`Some(Some)` → Superseded-or-Ok, `Some(None)` → benign,
        // `None` → EntityNotFound). Both arms now share the
        // post-zero-rows bookkeeping in `classify_post_update_existing`.
        return classify_post_update_existing(existing, entity_type, entity_id, version);
    }
    Ok(())
}
