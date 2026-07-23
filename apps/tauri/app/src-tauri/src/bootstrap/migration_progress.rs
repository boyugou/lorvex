//! Structured startup-migration progress events.
//!
//! Slow successful launches flush the events into `error_logs`; fatal
//! DB-open failures embed the same timeline in the user-facing
//! startup-failure marker. The event struct + helpers live here so the
//! orchestrator and the failure path both consume the same recorder
//! API instead of formatting strings independently.

use crate::db;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct MigrationProgressEvent {
    source: &'static str,
    message: &'static str,
    details: Option<String>,
}

impl MigrationProgressEvent {
    pub(super) const fn new(
        source: &'static str,
        message: &'static str,
        details: Option<String>,
    ) -> Self {
        Self {
            source,
            message,
            details,
        }
    }
}

pub(super) fn record_migration_progress_event(
    events: &mut Vec<MigrationProgressEvent>,
    source: &'static str,
    message: &'static str,
    details: Option<String>,
) {
    events.push(MigrationProgressEvent::new(source, message, details));
}

pub(super) fn persist_migration_progress_events(
    conn: &rusqlite::Connection,
    events: &[MigrationProgressEvent],
) {
    for event in events {
        let _ = crate::commands::diagnostics::append_error_log_internal(
            conn,
            event.source,
            event.message,
            event.details.clone(),
            Some("info".to_string()),
        );
    }
}

pub(super) fn persist_migration_progress_events_best_effort(events: &[MigrationProgressEvent]) {
    let Ok(conn) = db::get_conn() else {
        return;
    };
    persist_migration_progress_events(&conn, events);
}

pub(super) const fn should_persist_migration_progress_events(
    gate: &super::migration_gate::MigrationGate,
) -> bool {
    matches!(gate, super::migration_gate::MigrationGate::ThresholdCrossed)
}

pub(super) fn format_migration_progress_timeline(events: &[MigrationProgressEvent]) -> String {
    if events.is_empty() {
        return "  - no migration progress events were recorded\n".to_string();
    }

    // pre-size the timeline string so the loop doesn't grow through
    // doubling for every event. ~64 chars per event is a good upper
    // bound for the source/message/details triple.
    let mut timeline = String::with_capacity(events.len() * 64);
    for event in events {
        timeline.push_str("  - ");
        timeline.push_str(event.source);
        timeline.push_str(": ");
        timeline.push_str(event.message);
        if let Some(details) = &event.details {
            timeline.push_str(" (");
            timeline.push_str(details);
            timeline.push(')');
        }
        timeline.push('\n');
    }
    timeline
}
