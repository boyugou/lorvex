//! Top-level seed orchestration: the Tauri command (`seed_full_sync`),
//! the per-entity-class transaction wrapper (`seed_entity_in_tx`)
//! that releases the writer lock between phases, and the master
//! `seed_all_entities` driver that enumerates every entity class and
//! aggregates their counts into [`SeedFullSyncResult`].

use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG,
    ENTITY_AI_CHANGELOG, ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY,
    ENTITY_MEMORY, ENTITY_MEMORY_REVISION, ENTITY_TAG, ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_TASK_REMINDER,
};
use lorvex_store::payload_loaders::SimpleSyncSeedKind;

use super::enqueue::{enqueue_task_checklist_item_upsert, enqueue_task_reminder_upsert};
use super::seed_entities::{
    seed_calendar_events, seed_current_focus, seed_daily_reviews, seed_focus_schedules, seed_lists,
    seed_preferences, seed_tasks,
};
use super::seed_helpers::{seed_ids_and_delegate, seed_simple_sync_payloads};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};

#[derive(Debug, serde::Serialize)]
pub struct SeedFullSyncResult {
    pub tasks_enqueued: i64,
    pub lists_enqueued: i64,
    pub preferences_enqueued: i64,
    pub task_calendar_event_links_enqueued: i64,
    pub current_focus_enqueued: i64,
    pub daily_reviews_enqueued: i64,
    pub memories_enqueued: i64,
    pub calendar_events_enqueued: i64,
    pub habits_enqueued: i64,
    pub habit_completions_enqueued: i64,
    pub task_reminders_enqueued: i64,
    pub task_checklist_items_enqueued: i64,
    pub habit_reminder_policies_enqueued: i64,
    pub focus_schedules_enqueued: i64,
    pub tags_enqueued: i64,
    pub task_tags_enqueued: i64,
    pub task_dependencies_enqueued: i64,
    pub memory_revisions_enqueued: i64,
    pub ai_changelog_enqueued: i64,
    pub calendar_subscriptions_enqueued: i64,
}

/// Generates sync events for ALL existing entities in the local database.
/// This is a one-time operation for first-time sync setup — it ensures that the
/// full local state is available for push to filesystem bridge or a future cloud provider.
#[tauri::command]
pub fn seed_full_sync() -> Result<SeedFullSyncResult, String> {
    let conn = get_conn()?;
    seed_full_sync_internal(&conn).map_err(String::from)
}

pub(crate) fn seed_full_sync_internal(
    conn: &rusqlite::Connection,
) -> AppResult<SeedFullSyncResult> {
    // split the "is this run a duplicate?" check, the
    // per-entity seeders, and the "mark seeded" step into their own
    // SQLite transactions instead of a single multi-minute IMMEDIATE
    // transaction that locked out every other writer for the lifetime
    // of a 100k-row seed. The original outer-tx pattern was the
    // root cause of the hang reported by the audit:
    //   * UI clicks "Sync" → `seed_full_sync` opens IMMEDIATE
    //   * Notification reminder fires → `cron_send_reminders` blocks
    //     on the lock for the full seed duration
    //   * Calendar fetch task → blocks
    //   * User cancel button → blocks (cancellation flag write)
    // Per-entity transactions release the writer between phases so
    // every other backend task can interleave. The trade-off is that
    // a crash mid-seed leaves a partially-staged outbox; the outbox
    // is idempotent (coalesce-on-key) so a re-seed after clearing
    // `KEY_FULL_SYNC_SEEDED` lands on the same final state.
    crate::commands::with_immediate_transaction(conn, |conn| {
        let already_seeded =
            lorvex_runtime::sync_checkpoint_get(conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
                .map_err(AppError::from)?
                .is_some();
        if already_seeded {
            return Err(AppError::Validation(
                "Full sync has already been seeded. To re-seed, clear the 'full_sync_seeded' flag in sync_checkpoints.".to_string(),
            ));
        }
        Ok(())
    })?;

    let result = seed_all_entities(conn)?;

    crate::commands::with_immediate_transaction(conn, |conn| {
        lorvex_runtime::sync_checkpoint_set(conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED, "1")
            .map_err(AppError::from)
    })?;

    Ok(result)
}

/// per-entity seed unit. Wraps a single `seed_*` call
/// in its own IMMEDIATE transaction and emits a `Push`-phase progress
/// heartbeat after the entity completes so the UI's progress bar moves
/// during a multi-minute initial seed instead of sitting at 0% until
/// every row is staged.
fn seed_entity_in_tx<F>(conn: &rusqlite::Connection, seeder: F) -> AppResult<i64>
where
    F: FnOnce(&rusqlite::Connection) -> AppResult<i64>,
{
    let count = crate::commands::with_immediate_transaction(conn, seeder)?;
    // Heartbeat: signal that one more entity class finished. We pass
    // `total = -1` because the apply-side seeder doesn't know the
    // final entity count up front (it accumulates across a fixed list
    // of classes). The UI clamps `current` for any negative `total`
    // and treats the event as a "still alive" tick — see #2252.
    crate::event_bus::emit_sync_progress(
        crate::event_bus::SyncProgressPhase::Push,
        count.max(0),
        -1,
    );
    Ok(count)
}

fn seed_all_entities(conn: &rusqlite::Connection) -> AppResult<SeedFullSyncResult> {
    // each entity class runs in its own IMMEDIATE
    // transaction via `seed_entity_in_tx` so the writer lock is
    // released between phases (sub-second waits for any concurrent
    // backend task instead of the multi-minute hold of the prior
    // single-tx form). Each phase also fires a `Push` heartbeat so
    // the progress bar reflects forward motion during the seed.
    let lists_enqueued = seed_entity_in_tx(conn, seed_lists)?;
    let tasks_enqueued = seed_entity_in_tx(conn, seed_tasks)?;
    let preferences_enqueued = seed_entity_in_tx(conn, seed_preferences)?;
    let current_focus_enqueued = seed_entity_in_tx(conn, seed_current_focus)?;
    let daily_reviews_enqueued = seed_entity_in_tx(conn, seed_daily_reviews)?;
    let memories_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(c, ENTITY_MEMORY, SimpleSyncSeedKind::Memory)
    })?;
    let calendar_events_enqueued = seed_entity_in_tx(conn, seed_calendar_events)?;
    let task_calendar_event_links_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(
            c,
            EDGE_TASK_CALENDAR_EVENT_LINK,
            SimpleSyncSeedKind::TaskCalendarEventLink,
        )
    })?;
    let habits_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(c, ENTITY_HABIT, SimpleSyncSeedKind::Habit)
    })?;
    let habit_completions_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(
            c,
            EDGE_HABIT_COMPLETION,
            SimpleSyncSeedKind::HabitCompletion,
        )
    })?;
    let focus_schedules_enqueued = seed_entity_in_tx(conn, seed_focus_schedules)?;
    let task_reminders_enqueued = seed_entity_in_tx(conn, |c| {
        seed_ids_and_delegate(
            c,
            ENTITY_TASK_REMINDER,
            "SELECT id FROM task_reminders ORDER BY created_at",
            enqueue_task_reminder_upsert,
        )
    })?;
    let task_checklist_items_enqueued = seed_entity_in_tx(conn, |c| {
        seed_ids_and_delegate(
            c,
            ENTITY_TASK_CHECKLIST_ITEM,
            "SELECT id FROM task_checklist_items ORDER BY created_at, id",
            enqueue_task_checklist_item_upsert,
        )
    })?;
    let habit_reminder_policies_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(
            c,
            ENTITY_HABIT_REMINDER_POLICY,
            SimpleSyncSeedKind::HabitReminderPolicy,
        )
    })?;
    let tags_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(c, ENTITY_TAG, SimpleSyncSeedKind::Tag)
    })?;
    let task_tags_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(c, EDGE_TASK_TAG, SimpleSyncSeedKind::TaskTag)
    })?;
    let task_dependencies_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(c, EDGE_TASK_DEPENDENCY, SimpleSyncSeedKind::TaskDependency)
    })?;
    let memory_revisions_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(
            c,
            ENTITY_MEMORY_REVISION,
            SimpleSyncSeedKind::MemoryRevision,
        )
    })?;
    let ai_changelog_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(c, ENTITY_AI_CHANGELOG, SimpleSyncSeedKind::AiChangelog)
    })?;
    let calendar_subscriptions_enqueued = seed_entity_in_tx(conn, |c| {
        seed_simple_sync_payloads(
            c,
            ENTITY_CALENDAR_SUBSCRIPTION,
            SimpleSyncSeedKind::CalendarSubscription,
        )
    })?;

    Ok(SeedFullSyncResult {
        tasks_enqueued,
        lists_enqueued,
        preferences_enqueued,
        task_calendar_event_links_enqueued,
        current_focus_enqueued,
        daily_reviews_enqueued,
        memories_enqueued,
        calendar_events_enqueued,
        habits_enqueued,
        habit_completions_enqueued,
        task_reminders_enqueued,
        task_checklist_items_enqueued,
        habit_reminder_policies_enqueued,
        focus_schedules_enqueued,
        tags_enqueued,
        task_tags_enqueued,
        task_dependencies_enqueued,
        memory_revisions_enqueued,
        ai_changelog_enqueued,
        calendar_subscriptions_enqueued,
    })
}
