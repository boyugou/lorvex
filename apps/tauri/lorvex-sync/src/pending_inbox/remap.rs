use crate::composite_edge::{is_composite_edge_entity_type, remap_composite_edge_id};
use crate::envelope::SyncEnvelope;
use crate::error::SyncError;

pub(super) fn remap_missing_dependency(
    envelope: &SyncEnvelope,
    missing_entity_type: &str,
    missing_entity_id: &str,
    redirect_entity_type: &str,
    redirect_entity_id: &str,
) -> Result<Option<SyncEnvelope>, SyncError> {
    if redirect_entity_type != missing_entity_type {
        return Ok(None);
    }

    // route through the shared
    // `apply::remap_payload_identity_fields` helper so this surface
    // and the apply-pipeline redirect chase share a single source
    // of truth for which payload fields each entity_type carries.
    // Composite-edge entity_id rewrite stays here — pending_inbox
    // cares whether ANY of the composite parts matched the missing
    // dep id; the shared helper only mutates the payload-side
    // fields.
    let mut remapped = envelope.clone();

    let is_composite_edge = is_composite_edge_entity_type(envelope.entity_type.as_str());
    if is_composite_edge {
        let Ok(Some(entity_id)) =
            remap_composite_edge_id(&envelope.entity_id, missing_entity_id, redirect_entity_id)
        else {
            return Ok(None);
        };
        remapped.entity_id = entity_id;
    }

    // Parse via `From<serde_json::Error>` so the failure carries
    // the parse-class discriminant rather than a free-form string.
    let mut payload_value: serde_json::Value = serde_json::from_str(&envelope.payload)?;

    let payload_changed = crate::apply::remap_payload_identity_fields(
        envelope.entity_type.as_str(),
        &mut payload_value,
        missing_entity_id,
        redirect_entity_id,
    );

    // Composite edges: even if the payload didn't carry both fields
    // (older peers omit the typed fields and rely on entity_id alone),
    // the entity_id rewrite above is sufficient. For non-composite
    // entities, no payload change == no actionable redirect; we drop.
    if !is_composite_edge && !payload_changed {
        return Ok(None);
    }

    remapped.payload = serde_json::to_string(&payload_value)?;
    Ok(Some(remapped))
}
