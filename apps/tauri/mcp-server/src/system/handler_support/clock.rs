pub(crate) fn utc_now_iso() -> String {
    lorvex_domain::sync_timestamp_now()
}

/// Mint a new entity id (canonical UUIDv7 string).
///
/// Delegates to [`lorvex_domain::new_entity_id_string`] so every entity
/// id minted across the workspace shares one implementation.
/// this body inlined `uuid::Uuid::now_v7().to_string()` — same call,
/// but a future refactor that swapped the canonical mint (e.g. to a
/// k-sortable variant) would have had to walk every duplicate site
/// instead of patching one helper.
pub(crate) fn new_uuid() -> String {
    lorvex_domain::new_entity_id_string()
}

#[cfg(test)]
pub(crate) const fn reset_clock_state_for_tests() {}
