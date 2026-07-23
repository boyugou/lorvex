use super::IncomingSyncRecord;

#[cfg(test)]
fn sync_payloads_match_for_file_idempotency(existing: &str, outgoing: &str) -> bool {
    match (
        serde_json::from_str::<serde_json::Value>(existing),
        serde_json::from_str::<serde_json::Value>(outgoing),
    ) {
        (Ok(existing_json), Ok(outgoing_json)) => existing_json == outgoing_json,
        _ => existing == outgoing,
    }
}

#[cfg(test)]
pub(crate) fn incoming_records_match_for_file_idempotency(
    existing: &IncomingSyncRecord,
    outgoing: &IncomingSyncRecord,
) -> bool {
    existing.id == outgoing.id
        && existing.envelope.entity_type == outgoing.envelope.entity_type
        && existing.envelope.entity_id == outgoing.envelope.entity_id
        && existing.envelope.operation == outgoing.envelope.operation
        && sync_payloads_match_for_file_idempotency(
            &existing.envelope.payload,
            &outgoing.envelope.payload,
        )
        && existing.envelope.version == outgoing.envelope.version
        && existing.envelope.device_id == outgoing.envelope.device_id
}

pub(crate) fn is_supported_incoming_record(record: &IncomingSyncRecord) -> bool {
    // `entity_type` is a typed `EntityKind` so an empty value is
    // structurally unrepresentable — no trim/is_empty check needed.
    //
    // Do not filter by operation here. Upsert/Delete apply normally;
    // unknown operation strings are rejected by the transport parser
    // before an `IncomingSyncRecord` exists.
    !record.id.trim().is_empty()
        && !record.envelope.entity_id.trim().is_empty()
        && !record.envelope.device_id.trim().is_empty()
        && crate::commands::is_syncable_entity_type(record.envelope.entity_type.as_str())
}
