//! Shared sync-layer startup maintenance.
//!
//! This module owns sync hygiene that must not be stranded in one process
//! surface. Store-open invariants stay in `lorvex-store`; these passes cover
//! sync queues that are safe to run from app, MCP, and CLI cold starts.

use std::borrow::Cow;

use rusqlite::Connection;

use crate::{conflict_log, error::SyncError, pending_inbox};

#[derive(Debug, Default, PartialEq, Eq)]
pub struct StartupSyncMaintenanceReport {
    pub payload_shadows_promoted: usize,
    pub pending_queue_retention_error: Option<String>,
    pub pending_inbox_drain: pending_inbox::PendingDrainSummary,
    pub warnings: Vec<StartupMaintenanceWarning>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StartupMaintenanceWarning {
    pub source: &'static str,
    pub message: String,
    pub details: Option<String>,
    pub level: &'static str,
}

impl StartupMaintenanceWarning {
    fn warn(source: &'static str, message: impl Into<String>, details: impl Into<String>) -> Self {
        Self {
            source,
            message: message.into(),
            details: Some(details.into()),
            level: "warn",
        }
    }
}

pub fn persist_startup_maintenance_warnings(
    conn: &Connection,
    warnings: &[StartupMaintenanceWarning],
) {
    for warning in warnings {
        lorvex_store::error_log::append_error_log_best_effort(
            conn,
            warning.source,
            &warning.message,
            warning.details.as_deref(),
            Some(warning.level),
        );
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StartupSyncMaintenanceOptions {
    pub promote_payload_shadows: bool,
}

impl Default for StartupSyncMaintenanceOptions {
    fn default() -> Self {
        Self {
            promote_payload_shadows: true,
        }
    }
}

pub fn promote_startup_payload_shadows(conn: &Connection) -> Result<usize, SyncError> {
    crate::apply::promote_payload_shadows(conn)
        .map_err(|err| SyncError::Envelope(format!("payload shadow promotion failed: {err}")))
}

pub fn flag_reseed_required_due_to_pending_horizon_in_transaction(
    conn: &Connection,
) -> Result<(), SyncError> {
    let expired =
        pending_inbox::has_expired_entries(conn, lorvex_domain::naming::FULL_RESYNC_HORIZON_DAYS)?;
    if !expired {
        return Ok(());
    }

    flag_reseed_required_in_transaction(conn, "sync_pending_inbox", "horizon_check")
}

pub fn flag_reseed_required_in_transaction(
    conn: &Connection,
    entity_type: &'static str,
    entity_id: impl Into<String>,
) -> Result<(), SyncError> {
    let entity_id = entity_id.into();
    if entity_type.trim().is_empty() || entity_id.trim().is_empty() {
        return Err(SyncError::Envelope(
            "reseed_required marker source must not be empty".to_string(),
        ));
    }

    conflict_log::log_conflict(
        conn,
        &conflict_log::ConflictLogEntry {
            id: 0,
            entity_type: Cow::Borrowed(entity_type),
            entity_id,
            winner_version: String::new(),
            loser_version: String::new(),
            loser_device_id: String::new(),
            loser_payload: None,
            resolved_at: lorvex_domain::sync_timestamp_now(),
            resolution_type: Cow::Borrowed(lorvex_domain::naming::RESOLUTION_RESEED_REQUIRED),
        },
    )?;
    lorvex_runtime::sync_checkpoint_set(conn, lorvex_runtime::KEY_RESEED_REQUIRED, "true")
        .map_err(lorvex_store::StoreError::from)?;

    Ok(())
}

fn flag_reseed_required_due_to_pending_horizon(conn: &Connection) -> Result<(), SyncError> {
    lorvex_store::with_immediate_transaction(conn, |conn| {
        flag_reseed_required_due_to_pending_horizon_in_transaction(conn)
    })
}

pub fn gc_expired_pending_queues(conn: &Connection) -> Result<usize, SyncError> {
    let expired_pending_inbox_deleted =
        pending_inbox::gc_expired_entries(conn, lorvex_domain::naming::FULL_RESYNC_HORIZON_DAYS)?;
    Ok(expired_pending_inbox_deleted)
}

pub fn gc_expired_pending_queues_best_effort(conn: &Connection) -> Vec<StartupMaintenanceWarning> {
    let mut warnings = Vec::new();
    if let Err(err) =
        pending_inbox::gc_expired_entries(conn, lorvex_domain::naming::FULL_RESYNC_HORIZON_DAYS)
    {
        warnings.push(StartupMaintenanceWarning::warn(
            "sync.startup.pending_inbox_gc_failed",
            "pending inbox startup GC failed",
            err.to_string(),
        ));
    }
    warnings
}

pub fn run_pending_queue_retention_maintenance(
    conn: &Connection,
) -> Result<Vec<StartupMaintenanceWarning>, SyncError> {
    flag_reseed_required_due_to_pending_horizon(conn)?;
    Ok(gc_expired_pending_queues_best_effort(conn))
}

fn run_startup_pending_queue_retention_maintenance(conn: &Connection) -> Result<(), SyncError> {
    flag_reseed_required_due_to_pending_horizon(conn)?;
    gc_expired_pending_queues(conn)?;
    Ok(())
}

pub fn run_startup_sync_maintenance(
    conn: &Connection,
) -> Result<StartupSyncMaintenanceReport, SyncError> {
    run_startup_sync_maintenance_with_options(conn, StartupSyncMaintenanceOptions::default())
}

pub fn run_startup_sync_maintenance_with_options(
    conn: &Connection,
    options: StartupSyncMaintenanceOptions,
) -> Result<StartupSyncMaintenanceReport, SyncError> {
    let payload_shadows_promoted = if options.promote_payload_shadows {
        promote_startup_payload_shadows(conn)?
    } else {
        0
    };
    let mut warnings = Vec::new();
    let pending_queue_retention_error = match run_startup_pending_queue_retention_maintenance(conn)
    {
        Ok(()) => None,
        Err(err) => {
            let details = err.to_string();
            warnings.push(StartupMaintenanceWarning::warn(
                "sync.startup.pending_queue_retention_failed",
                "startup pending queue retention maintenance failed",
                details.clone(),
            ));
            Some(details)
        }
    };
    let pending_inbox_drain = pending_inbox::drain_pending_inbox(conn)?;

    Ok(StartupSyncMaintenanceReport {
        payload_shadows_promoted,
        pending_queue_retention_error,
        pending_inbox_drain,
        warnings,
    })
}

#[cfg(test)]
mod tests;
