//! Post-filter predicates run against the closure of selected records:
//! shadow rows match by full `(entity_type, entity_id)` key; tombstone rows
//! match by `entity_type` only (a tombstone deletes a row whose id is no
//! longer in the dataset, so we cannot demand the id be in the closure).

use std::collections::{HashMap, HashSet};

/// Closure of `(entity_type, entity_id)` pairs the export scope owns.
/// Indexed as `entity_type -> set<entity_id>` so the per-row shadow
/// match is two `&str`-keyed `HashMap::get` / `HashSet::contains` calls
/// — zero allocations on the hot path. The previous shape was a flat
/// `HashSet<(String, String)>`, which forced
/// `set.contains(&(et.to_string(), eid.to_string()))` per call: two
/// fresh heap `String`s on every shadow row visited (#3368).
pub(super) type SelectedRecordKeys = HashMap<String, HashSet<String>>;

pub(super) fn build_selected_record_keys<I>(keys: I) -> SelectedRecordKeys
where
    I: IntoIterator<Item = (String, String)>,
{
    let mut out: SelectedRecordKeys = HashMap::new();
    for (entity_type, entity_id) in keys {
        out.entry(entity_type).or_default().insert(entity_id);
    }
    out
}

pub(super) fn shadow_matches_selected(
    value: &serde_json::Value,
    selected_record_keys: &SelectedRecordKeys,
) -> bool {
    let Some(entity_type) = value.get("entity_type").and_then(|value| value.as_str()) else {
        return false;
    };
    let Some(entity_id) = value.get("entity_id").and_then(|value| value.as_str()) else {
        return false;
    };
    // Two stable-API `&str` lookups, zero allocation. `HashMap<String,
    // _>::get(&str)` works via `String: Borrow<str>`, same for the
    // inner `HashSet<String>::contains(&str)`.
    selected_record_keys
        .get(entity_type)
        .is_some_and(|ids| ids.contains(entity_id))
}

pub(super) fn tombstone_matches_selected_type(
    value: &serde_json::Value,
    selected_entity_types: &HashSet<String>,
) -> bool {
    value
        .get("entity_type")
        .and_then(|value| value.as_str())
        .is_some_and(|entity_type| selected_entity_types.contains(entity_type))
}
