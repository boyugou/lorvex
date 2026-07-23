//! Payload-shadow finalization for inbound envelopes.

use rusqlite::Connection;

use lorvex_domain::capability::EnvelopeAcceptance;

use super::super::ApplyError;
use crate::envelope::SyncEnvelope;

pub(super) fn finalize_payload_shadow(
    conn: &Connection,
    acceptance: EnvelopeAcceptance,
    envelope: &SyncEnvelope,
) -> Result<(), ApplyError> {
    match acceptance {
        EnvelopeAcceptance::ParseForwardCompat => {
            // persist the originating peer's device_id
            // so `promote_payload_shadows` can replay the envelope
            // with real attribution. The previous shape lost this
            // information and forced promote to synthesize a fake
            // `"shadow-promotion"` device_id that corrupted any
            // conflict_log row written during promotion.
            lorvex_sync_payload::payload_shadow::upsert_shadow(
                conn,
                envelope.entity_type.as_str(),
                &envelope.entity_id,
                &envelope.version.to_string(),
                envelope.payload_schema_version,
                &envelope.payload,
                &envelope.device_id,
            )?;
        }
        EnvelopeAcceptance::ParseFully => {
            lorvex_sync_payload::payload_shadow::remove_shadow_if_superseded(
                conn,
                envelope.entity_type.as_str(),
                &envelope.entity_id,
                &envelope.version.to_string(),
            )?;
        }
        EnvelopeAcceptance::DeferToPendingInbox => {}
    }
    Ok(())
}
