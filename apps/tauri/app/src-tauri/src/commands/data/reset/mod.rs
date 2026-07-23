use crate::db::get_conn;
use crate::event_bus;

use serde::Serialize;

mod executor;
mod manifest;
pub(crate) mod preferences;
mod tombstones;

#[cfg(test)]
mod tests;

use executor::reset_all_data_db;

#[derive(Debug, Serialize)]
pub struct ResetAllDataResult {
    pub tables_cleared: usize,
    /// number of `OP_DELETE` envelopes (and matching
    /// tombstones) emitted to the outbox before the bulk wipe so peers
    /// honor the reset on the next sync cycle. Sums across every
    /// syncable aggregate-root table (`tasks`, `lists`, `tags`,
    /// `calendar_events`, `habits`, `memories`, `daily_reviews`,
    /// `focus_schedule`, `current_focus`,
    /// `calendar_subscriptions`); the receiver cascade-tombstones edges
    /// and collection children (matching the contract of every normal
    /// aggregate-root delete in the app).
    pub entities_tombstoned: usize,
}

/// Localized confirmation tokens accepted by `reset_all_data`. The
/// renderer sends whichever token matches the user's locale
/// (`settings.dangerResetAllConfirmToken`); accepting only the English
/// literal would force non-Latin-script users to IME-toggle just to
/// wipe their device. The list is intentionally small — only the
/// canonical word for "delete" (or "DELETE") in the locales we ship
/// translations for — so a fat-finger keystroke can't satisfy the
/// gate by accident.
const RESET_ALL_DATA_TOKENS: &[&str] = &[
    "DELETE",    // English / fallback
    "删除",      // Simplified Chinese
    "刪除",      // Traditional Chinese
    "削除",      // Japanese
    "삭제",      // Korean
    "ELIMINAR",  // Spanish
    "SUPPRIMER", // French
    "LÖSCHEN",   // German
    "ELIMINA",   // Italian
    "EXCLUIR",   // Portuguese
    "УДАЛИТЬ",   // Russian
    "حذف",       // Arabic
    "מחק",       // Hebrew
];

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn reset_all_data(confirmation: String) -> Result<ResetAllDataResult, String> {
    if !RESET_ALL_DATA_TOKENS.iter().any(|tok| *tok == confirmation) {
        // #3033-M11: route through the typed `AppError::Validation`
        // envelope so the renderer can programmatically distinguish
        // "user typo on the confirmation prompt" from a downstream
        // DB I/O failure (which lands as `AppError::Sql` →
        // `kind: internal`). Returning a plain `String` here would
        // force the toast layer to substring-match the message text
        // to decide whether to keep the prompt open vs. surface a
        // hard error banner.
        return Err(crate::error::AppError::Validation(
            "Confirmation text must match the localized delete token".to_string(),
        )
        .into());
    }

    let conn = get_conn()?;
    // When the DB-side reset fails (rollback or catch_unwind body
    // panic) the user's data stays intact. Emit a typed failure event
    // before bubbling the error so the UI shows an actionable toast
    // instead of a generic dialog; the success-path `data-changed`
    // events only fire after the happy path completes.
    let (cleared, entities_tombstoned) = match reset_all_data_db(&conn) {
        Ok(pair) => pair,
        Err(e) => {
            event_bus::emit_data_reset_failed(event_bus::DataResetFailedPayload {
                reason: e.clone(),
                rolled_back: true,
            });
            return Err(e);
        }
    };

    // Reclaim disk space. Non-fatal — VACUUM can fail in WAL mode.
    let _ = conn.execute_batch("VACUUM;");

    // Clear Spotlight index — all tasks have been deleted.
    crate::platform::spotlight::remove_all_tasks();

    // Full wipe — drop the process-wide best-streak cache (#2291).
    crate::commands::habits::queries::clear_best_streak_cache();

    // Notify all windows that data has been wiped.
    event_bus::emit_data_changed(event_bus::Entity::Task);
    event_bus::emit_data_changed(event_bus::Entity::List);
    event_bus::emit_data_changed(event_bus::Entity::CalendarEvent);
    event_bus::emit_data_changed(event_bus::Entity::Habit);
    event_bus::emit_data_changed(event_bus::Entity::DailyReview);
    event_bus::emit_data_changed(event_bus::Entity::Preference);
    event_bus::emit_data_changed(event_bus::Entity::Changelog);
    event_bus::emit_data_changed(event_bus::Entity::AiMemory);
    event_bus::emit_data_changed(event_bus::Entity::Planning);

    Ok(ResetAllDataResult {
        tables_cleared: cleared,
        entities_tombstoned,
    })
}
