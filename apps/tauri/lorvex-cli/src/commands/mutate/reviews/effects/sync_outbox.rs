//! Daily review outbox enqueue helper.
//!
//! Routes through the canonical aggregate payload builder so the CLI
//! emits byte-identical envelopes to the Tauri app and MCP server. The
//! `review` argument is intentionally not the source of truth for the
//! payload — we re-read from the DB so embedded child arrays come
//! from the same `daily_review_*_links` snapshot the apply pipeline
//! consumes.

use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::ENTITY_DAILY_REVIEW;
use lorvex_sync::outbox_enqueue::enqueue_payload_upsert;
use rusqlite::Connection;

use crate::models::DailyReviewView;

pub(super) fn enqueue_daily_review_payload_upsert(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    review: &DailyReviewView,
) -> Result<(), crate::error::CliError> {
    let Some(payload) = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
        conn,
        ENTITY_DAILY_REVIEW,
        &review.date,
    )?
    else {
        return Err(crate::error::CliError::Internal(format!(
            "daily_review '{}' enqueue: row vanished between persist and enqueue",
            review.date
        )));
    };
    let version = hlc_state.generate().to_string();
    enqueue_payload_upsert(
        conn,
        ENTITY_DAILY_REVIEW,
        &review.date,
        &payload,
        crate::commands::shared::bare_outbox_ctx(&version, device_id),
    )?;
    Ok(())
}
