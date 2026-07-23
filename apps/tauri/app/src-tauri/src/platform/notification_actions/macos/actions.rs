//! Action handlers fired by the macOS notification delegate's
//! `did_receive_notification_response` callback. Lifted out of the
//! delegate class so the Obj-C dispatch body stays focused on
//! parsing the action identifier and the handler bodies stay
//! focused on the per-action SQLite + sync-outbox writes.
//!
//! Every error path routes through `record_notification_action_error`
//! (the durable error_logs writer + Tauri event emit) instead of
//! `eprintln!`. Release builds suppress stderr on macOS, so a
//! print-only handler would leave a "Complete" tap silently failing
//! with no diagnostic for the user.

use super::delegate::get_app_handle;

/// Complete the task by delegating to the canonical command-layer helper.
pub(super) fn handle_complete_action(task_id: &str) {
    let result = (|| -> Result<(), String> {
        let conn = crate::db::get_conn()?;

        let r = crate::commands::with_immediate_transaction(&conn, |conn| {
            // Trust-boundary: task_id arrived from the macOS notification
            // user-info dict. Lift to typed for downstream helpers.
            crate::commands::complete_task_internal(conn, task_id)
        })
        .map_err(String::from)?;

        crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);

        // Spotlight reindex after transaction commits.
        crate::platform::spotlight::apply_actions(
            &conn,
            &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
                r.spotlight_reindex_ids,
            )],
        );

        Ok(())
    })();

    if let Err(e) = result {
        // Route through `record_notification_action_error` rather
        // than `eprintln!`: release builds have no console (macOS) or
        // run under `windows_subsystem=windows`, so `eprintln!` would
        // be invisible and a failing Complete tap (notification
        // re-fires forever) would leave no trace.
        super::super::record_notification_action_error("complete", task_id, &e);
    }
}

/// Snooze: create a NEW reminder on the same task, scheduled for
/// `now + DEFAULT_REMINDER_SNOOZE_MINUTES`. This matches the TypeScript
/// path (`actions.ts`) exactly — a reminder action must not mutate the
/// whole task's `planned_date`.
pub(super) fn handle_snooze_action(task_id: &str) {
    let result = (|| -> Result<(), String> {
        let conn = crate::db::get_conn()?;

        let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.to_string());
        crate::commands::snooze_reminder_for_task_internal(&conn, &task_id_typed)
            .map_err(String::from)?;

        crate::event_bus::emit_data_changed(crate::event_bus::Entity::Task);
        Ok(())
    })();

    if let Err(e) = result {
        super::super::record_notification_action_error("snooze", task_id, &e);
    }
}

/// Open the task detail in the frontend by emitting a deep-link event.
pub(super) fn handle_open_task(task_id: &str) {
    use tauri::Emitter;

    let Some(app) = get_app_handle() else {
        // Route through the durable record so a missing-AppHandle
        // race (delegate fired before install completed) shows up in
        // Settings → Diagnostics. An `eprintln!` here would be
        // invisible on packaged builds.
        super::super::record_notification_action_error(
            "open",
            task_id,
            "delegate fired before AppHandle was registered; cannot open task deep link",
        );
        return;
    };

    let target = crate::deep_link::DeepLinkTarget::Task {
        task_id: task_id.to_string(),
    };
    crate::deep_link::enqueue_pending(target.clone());

    if let Err(e) = app.emit(crate::deep_link::DEEP_LINK_OPEN_EVENT, target.to_payload()) {
        super::super::record_notification_action_error("open", task_id, &e.to_string());
    }

    // Attempt to bring the main window to focus
    #[cfg(desktop)]
    {
        crate::window_restore::focus_main_window(app, "notification_tap");
    }
}
