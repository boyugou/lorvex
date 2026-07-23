use super::ParsedEvent;

/// Sort and dedup VEVENTs by composite (UID, RECURRENCE-ID) key per
/// RFC 5545 §3.8.7.4 — see the call-site comment in [`super::parse_ics_events`].
pub(super) fn merge_duplicate_events(events: Vec<ParsedEvent>) -> Vec<ParsedEvent> {
    use std::collections::HashMap;

    // pre-size the HashMap and the survivors Vec so the
    // common path (no duplicate composite keys) avoids the rehash
    // cascade on a feed that's already ordered by the publisher.
    // `events.len()` is a tight upper bound — we can't accumulate
    // more entries than we started with.
    let mut by_key: HashMap<(String, Option<String>), (usize, ParsedEvent)> =
        HashMap::with_capacity(events.len());
    for (position, event) in events.into_iter().enumerate() {
        let key = (event.uid.clone(), event.recurrence_id.clone());
        match by_key.entry(key) {
            std::collections::hash_map::Entry::Vacant(slot) => {
                slot.insert((position, event));
            }
            std::collections::hash_map::Entry::Occupied(mut slot) => {
                let (existing_pos, existing) = slot.get_mut();
                if event_supersedes(&event, existing, position, *existing_pos) {
                    *existing_pos = position;
                    *existing = event;
                }
            }
        }
    }

    // Return in original document order (using each survivor's
    // recorded position) so downstream consumers see a deterministic
    // sequence. HashMap iteration order is non-deterministic.
    let mut survivors: Vec<(usize, ParsedEvent)> = Vec::with_capacity(by_key.len());
    survivors.extend(by_key.into_values());
    survivors.sort_by_key(|(pos, _)| *pos);
    survivors.into_iter().map(|(_, e)| e).collect()
}

/// `(SEQUENCE, DTSTAMP, position)` lexicographic comparison: higher
/// SEQUENCE wins; tie → later DTSTAMP wins; tie → later document
/// position wins. DTSTAMP is compared as a string because RFC 5545
/// emits it in `YYYYMMDDTHHMMSSZ` form which collates chronologically.
fn event_supersedes(
    candidate: &ParsedEvent,
    incumbent: &ParsedEvent,
    candidate_pos: usize,
    incumbent_pos: usize,
) -> bool {
    if candidate.sequence != incumbent.sequence {
        return candidate.sequence > incumbent.sequence;
    }
    match (candidate.dtstamp.as_deref(), incumbent.dtstamp.as_deref()) {
        (Some(c), Some(i)) if c != i => return c > i,
        (Some(_), None) => return true,
        (None, Some(_)) => return false,
        _ => {}
    }
    candidate_pos > incumbent_pos
}
