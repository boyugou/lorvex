//! `apply_calendar_event_upsert` — RFC-5545-shaped payload validator
//! and SQL upsert for the `calendar_event` aggregate root.
//!
//! After upserting the canonical row, this rebuilds the
//! `calendar_event_attendees` materialization from the embedded
//! `attendees` array. Surplus per-attendee keys (forward-compat
//! fields from a newer peer like `role`, `rsvp_deadline`) are
//! preserved in `calendar_event_attendee_shadow` so they round-trip
//! verbatim on the next outbound enqueue (issue #2317).

use rusqlite::{named_params, params, Connection, OptionalExtension};

use lorvex_domain::ids::EventId;

use super::super::super::LwwTieBreak;
use super::super::helpers::{
    nullable_str_or_clear, optional_bool_as_i64, optional_object_array, optional_str,
    optional_str_preserving_empty, required_str, scrub, scrub_opt,
};
use super::super::ApplyError;
use super::attendee::{normalize_attendee, NormalizedAttendee};
use super::merge::merge_duplicate_override_instances;
use crate::conflict_log::{log_conflict, ConflictLogEntry};

pub(crate) fn apply_calendar_event_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    apply_ts: &str,
) -> Result<(), ApplyError> {
    // every aggregate-upsert signature carries
    // `apply_ts` for uniform dispatch. Issue #2878 made this handler
    // a real consumer — it stamps the `resolved_at` column of any
    // attendee-email-collision row written below.
    //
    // Issue #3285 phase 3: thread the typed `EventId` through the
    // apply body. The dispatch table holds fn-pointer types shared
    // across every aggregate handler so the public signature stays
    // `&str`, but the function body operates on the typed id from
    // the very first line — SQL bind sites, error formatting, and
    // helper calls all flow through the typed id (zero-copy via
    // the rusqlite ToSql impl on the newtype) so a future
    // mismatched-kind id can never silently slip into a calendar-
    // event-shaped SQL statement. Envelope ids are dispatcher-
    // validated upstream; `from_trusted` skips a redundant parse.
    let event_id = EventId::from_trusted(entity_id.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    // Unicode hygiene (#2427): scrub free-text calendar-event fields.
    let title_owned = scrub(required_str(&val, "title", "calendar_event")?);
    let title: &str = &title_owned;
    // `description`, `location`, and `url` are nullable
    // calendar-event columns where an explicit empty write means "clear".
    // The empty-preserving helper keeps the clear intent distinguishable
    // from an absent key so it fans out as a real SQL NULL.
    let description_owned = scrub_opt(nullable_str_or_clear(&optional_str_preserving_empty(
        &val,
        "description",
        "calendar_event",
    )?));
    let description: Option<&str> = description_owned.as_deref();
    let start_date = required_str(&val, "start_date", "calendar_event")?;
    let start_time = optional_str(&val, "start_time", "calendar_event")?;
    let end_date = optional_str(&val, "end_date", "calendar_event")?;
    let end_time = optional_str(&val, "end_time", "calendar_event")?;
    // validate the YYYY-MM-DD / HH:MM shape at the
    // trust boundary so a peer pushing `start_date: "tomorrow"`
    // surfaces as a clean InvalidPayload instead of tripping the
    // schema CHECK at INSERT time and aborting the whole apply
    // batch. Sibling pattern landed for tasks at task.rs:137.
    lorvex_domain::validation::validate_date_format(start_date).map_err(|e| {
        ApplyError::InvalidPayload(format!(
            "calendar_event {} start_date failed validation: {e}",
            event_id.as_str()
        ))
    })?;
    if let Some(value) = end_date {
        lorvex_domain::validation::validate_date_format(value).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "calendar_event {} end_date failed validation: {e}",
                event_id.as_str()
            ))
        })?;
    }
    if let Some(value) = start_time {
        lorvex_domain::validation::validate_time_format(value).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "calendar_event {} start_time failed validation: {e}",
                event_id.as_str()
            ))
        })?;
    }
    if let Some(value) = end_time {
        lorvex_domain::validation::validate_time_format(value).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "calendar_event {} end_time failed validation: {e}",
                event_id.as_str()
            ))
        })?;
    }
    // older peers may omit `all_day`; SQL default is 0
    // (timed event), which is the safer assumption than treating the
    // event as rejected outright.
    let all_day = optional_bool_as_i64(&val, "all_day", "calendar_event")?.unwrap_or(0);
    let location_owned = scrub_opt(nullable_str_or_clear(&optional_str_preserving_empty(
        &val,
        "location",
        "calendar_event",
    )?));
    let location: Option<&str> = location_owned.as_deref();
    // color/recurrence/timezone/recurrence_exceptions/event_type are
    // structured/token fields — not scrubbed here.
    let url_raw = nullable_str_or_clear(&optional_str_preserving_empty(
        &val,
        "url",
        "calendar_event",
    )?);
    // scheme allowlist on the apply trust boundary
    // for the optional `url` field. Only enforce when the field is
    // actually populated (the column is nullable). Reject
    // `javascript:`, `data:`, `file:`, etc. — calendar event URLs
    // from real integrations only ever use http/https/webcal.
    //
    // bind the validator's canonical (sanitized +
    // trimmed) form to the INSERT instead of the raw envelope value,
    // so a peer URL with leading bidi-override / zero-width
    // codepoints stops smuggling those bytes into
    // `calendar_events.url`.
    let url_canonical: Option<String> = match url_raw {
        Some(value) => Some(
            lorvex_domain::validation::validate_calendar_url(value).map_err(|e| {
                ApplyError::InvalidPayload(format!("calendar_event payload.url: {e}"))
            })?,
        ),
        None => None,
    };
    let url: Option<&str> = url_canonical.as_deref();
    let color = optional_str(&val, "color", "calendar_event")?;
    // `recurrence`, `timezone`, and
    // `recurrence_exceptions` now use `optional_str_preserving_empty`
    // + `nullable_str_or_clear` like `description` / `location` /
    // `url`. The legacy `optional_str` collapsed an explicit
    // empty-string clear to None, silently reinterpreting "user
    // cleared the recurrence" as "no change" on the receiving peer.
    let recurrence_raw = nullable_str_or_clear(&optional_str_preserving_empty(
        &val,
        "recurrence",
        "calendar_event",
    )?);
    // Route the peer's recurrence through the canonical calendar
    // normalizer at the apply trust boundary. Storing whatever the
    // peer sends verbatim would let a peer who wrote the rule via
    // `set_recurrence` (the task surface, with looser BYDAY policy
    // on MONTHLY/YEARLY) or a forked client ship a calendar event
    // whose recurrence violates the calendar contract — the
    // receiving device's expansion code would then produce output
    // the local boundary would have refused, observable as ghost
    // occurrences in the timeline. Routing through the same gate
    // the MCP/Tauri write surfaces
    // use makes the apply pipeline reject contract-violating
    // peer payloads as `InvalidPayload` instead of laundering them.
    let recurrence_owned = lorvex_domain::validation::normalize_calendar_recurrence(recurrence_raw)
        .map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "calendar_event {} recurrence: {e}",
                event_id.as_str()
            ))
        })?;
    let recurrence: Option<&str> = recurrence_owned.as_deref();
    let timezone = nullable_str_or_clear(&optional_str_preserving_empty(
        &val,
        "timezone",
        "calendar_event",
    )?);
    let recurrence_exceptions_patch =
        optional_str_preserving_empty(&val, "recurrence_exceptions", "calendar_event")?;
    let event_type = required_str(&val, "event_type", "calendar_event")?;
    // Audit: schema CHECK at `001_schema.sql:156` constrains
    // `event_type` to a closed set. A peer with a forked serializer
    // could send `"meeting"` or `"appointment"` and trip the CHECK
    // at INSERT time, aborting the entire apply batch with no
    // pending-inbox deferral path. Validate at the trust boundary so
    // we fail with a clean `InvalidPayload` instead.
    // route through the domain validator so this gate,
    // the store repository validator, and the MCP/Tauri entry-point
    // validators all share one source of truth for the canonical
    // set and produce identical error wording.
    if let Err(err) = lorvex_domain::CanonicalCalendarEventType::validate(event_type) {
        return Err(ApplyError::InvalidPayload(format!(
            "calendar_event payload: {err}"
        )));
    }
    // Schema CHECK at `001_schema.sql:157` enforces the
    // all_day/start_time/end_time mutual exclusion: an all-day event
    // MUST have NULL start_time and end_time. Validate the payload
    // against this invariant before INSERT.
    if all_day != 0 && (start_time.is_some() || end_time.is_some()) {
        return Err(ApplyError::InvalidPayload(
            "calendar_event payload: all_day=1 requires start_time and end_time to be null"
                .to_string(),
        ));
    }
    let person_name_owned = scrub_opt(optional_str(&val, "person_name", "calendar_event")?);
    let person_name: Option<&str> = person_name_owned.as_deref();
    let series_id = optional_str(&val, "series_id", "calendar_event")?;
    let recurrence_instance_date =
        optional_str(&val, "recurrence_instance_date", "calendar_event")?;
    if let Some(value) = recurrence_instance_date {
        lorvex_domain::validation::validate_date_format(value).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "calendar_event {} recurrence_instance_date failed validation: {e}",
                event_id.as_str()
            ))
        })?;
    }
    if series_id.is_some() != recurrence_instance_date.is_some() {
        return Err(ApplyError::InvalidPayload(
            "calendar_event payload: series_id and recurrence_instance_date must be set or cleared together"
                .to_string(),
        ));
    }
    let created_at = required_str(&val, "created_at", "calendar_event")?;
    let updated_at = required_str(&val, "updated_at", "calendar_event")?;

    // lifted to shared `LwwUpsertSpec` (provider
    // fields embedded inline have been removed).
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let override_collision_exists = if let (Some(series_id), Some(recurrence_instance_date)) =
        (series_id, recurrence_instance_date)
    {
        conn.prepare_cached(
            "SELECT 1 FROM calendar_events
                  WHERE series_id = ?1
                    AND recurrence_instance_date = ?2
                    AND id != ?3
                  LIMIT 1",
        )?
        .query_row(
            params![series_id, recurrence_instance_date, event_id.as_str()],
            |_| Ok(()),
        )
        .optional()?
        .is_some()
    } else {
        false
    };
    let staged_series_id = if override_collision_exists {
        None
    } else {
        series_id
    };
    let staged_recurrence_instance_date = if override_collision_exists {
        None
    } else {
        recurrence_instance_date
    };
    let sql = crate::apply::LwwUpsertSpec {
        table: "calendar_events",
        columns: &[
            "id",
            "title",
            "description",
            "start_date",
            "start_time",
            "end_date",
            "end_time",
            "all_day",
            "location",
            "url",
            "color",
            "recurrence",
            "timezone",
            "event_type",
            "person_name",
            "series_id",
            "recurrence_instance_date",
            "created_at",
            "updated_at",
            "version",
        ],
        conflict: &["id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        // bind the typed `EventId` directly via the rusqlite ToSql
        // impl on the newtype — no `.as_str()` allocation, and the
        // typed id is the only path that reaches the SQL layer.
        ":id": &event_id,
        ":title": title,
        ":description": description,
        ":start_date": start_date,
        ":start_time": start_time,
        ":end_date": end_date,
        ":end_time": end_time,
        ":all_day": all_day,
        ":location": location,
        ":url": url,
        ":color": color,
        ":recurrence": recurrence,
        ":timezone": timezone,
        ":event_type": event_type,
        ":person_name": person_name,
        ":series_id": staged_series_id,
        ":recurrence_instance_date": staged_recurrence_instance_date,
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":version": version,
    })?;

    // Only rebuild attendees if the parent row was actually inserted/updated.
    // If the version check rejected the upsert, the parent INSERT
    // affected zero rows and we must NOT overwrite the current
    // (newer) attendees with stale data.
    //
    // capture conn.changes() into a local
    // immediately after the parent statement. The previous shape
    // re-read it inline; any future intervening write between the
    // INSERT and the check would silently break the gate. By
    // pinning into `parent_wrote` here we preserve correctness
    // against future code that adds an interleaved statement.
    let parent_wrote = conn.changes();
    if parent_wrote == 0 {
        return Ok(());
    }

    if let (Some(series_id), Some(recurrence_instance_date)) = (series_id, recurrence_instance_date)
    {
        if !merge_duplicate_override_instances(
            conn,
            event_id.as_str(),
            series_id,
            recurrence_instance_date,
            version,
            apply_ts,
        )? {
            return Ok(());
        }
    }

    // Rewrite the per-event EXDATE registry from the wire-form
    // JSON. The registry lives in `calendar_event_recurrence_exceptions`
    // since #4585 instead of a JSON blob on the parent row, so the
    // replace happens after the LWW gate accepted the parent
    // upsert. Empty / NULL incoming JSON clears the registry.
    // Only touch the registry when the envelope carried an
    // explicit value (Set or Clear). `Unset` means the peer did
    // not mention exceptions on this update; preserve the local
    // registry as-is so a partial update from a peer that knows
    // nothing about EXDATE history doesn't wipe it.
    if recurrence_exceptions_patch.is_set_or_clear() {
        let bind: Option<&str> = recurrence_exceptions_patch.as_bind_value().copied();
        lorvex_store::recurrence_exceptions::replace_event_exceptions_from_json(
            conn,
            event_id.as_str(),
            bind,
        )
        .map_err(ApplyError::Store)?;
    }

    // Rebuild attendees materialization from embedded array.
    //
    // the primary `calendar_event_attendees` table stores only the
    // known fields `email/name/status`. Any other per-attendee keys (e.g.
    // `role`, `rsvp_deadline` from a newer peer) would be silently discarded
    // on re-echo — the next outbound enqueue rebuilds the `attendees` array
    // purely from the known-columns table. Preserve the surplus keys per
    // attendee in `calendar_event_attendee_shadow`, mirroring the
    // aggregate-level `sync_payload_shadow` pattern scoped to this one
    // forward-compat surface. `calendar_event_attendees.email` is stored
    // lowercased (see MCP `materialize_attendees`), so we normalize here
    // too — the shadow PK must agree with the primary table so the
    // LEFT JOIN in `load_attendees_with_extras` lines up.
    conn.prepare_cached("DELETE FROM calendar_event_attendees WHERE event_id = ?1")?
        .execute([&event_id])?;
    // When an attendee is removed from the envelope, its shadow row is
    // removed too — purge-on-absence is the only way to avoid stale
    // extras re-attaching to a future attendee that happens to reuse
    // the same email.
    let mut attendee_shadow_rows: Vec<(String, serde_json::Map<String, serde_json::Value>)> =
        Vec::new();

    // deterministic email-collision resolution.
    //
    // Two attendee entries that collapse to the same normalized email
    // (`trim().to_lowercase()`) cannot both occupy a row in
    // `calendar_event_attendees` — the (event_id, email) pair is the
    // logical primary key (the schema enforces it via UNIQUE INDEX
    // and the per-attendee shadow keys against the same pair).
    //
    // The deterministic-winner discipline is required because a
    // bare `INSERT OR IGNORE` to drop the second entry at SQL level
    // while still pushing its surplus extras into
    // `attendee_shadow_rows` would let the LEFT JOIN inside
    // `replace_attendee_shadows` pair the LATER extras with the
    // EARLIER attendee, silently fusing two peers' metadata under
    // one row with no diagnostic — a delegate's `rsvp_deadline`
    // would overwrite the delegator's, etc.
    //
    // Resolution policy: pick exactly one winner per normalized email
    // and log every dropped peer to `sync_conflict_log` so the user
    // can audit what was lost.
    //
    // Why "lexicographically smallest canonical-JSON of the entry"
    // and not the alternatives?
    //
    //   * Array-order ("first wins") is NOT stable across peers — a
    //     provider redelivery may reorder, the MCP and outbox paths
    //     don't share a sort, and the wire envelope's array order is
    //     not part of the canonicalization contract for attendee
    //     entries (see `canonicalize.rs`). Two peers receiving the
    //     same logical envelope from different routes could pick
    //     different winners under "first wins" — the precise opposite
    //     of "deterministic."
    //
    //   * Semantic priority on `participant_status` (e.g.
    //     accepted > tentative > declined) was tempting but biases
    //     the outcome on a field whose meaning depends on the
    //     scenario. A delegator who declined on behalf of a delegate
    //     would lose to the delegate's "accepted," silently dropping
    //     the delegator's role/notes — which is the very corruption
    //     this fix is meant to prevent. Worse, status is optional;
    //     when absent on both sides the policy degenerates to
    //     undefined order.
    //
    //   * Lexicographically-smallest canonical-JSON is content-
    //     addressed: it depends only on the entries themselves, never
    //     on array order, peer identity, or wall-clock timing. Two
    //     peers that observe the same set of colliding entries pick
    //     the same winner, every time. Canonical JSON (sorted keys,
    //     compact format) gives byte-exact reproducibility across
    //     platforms and serde versions. The audit row carries the
    //     scrubbed loser payload, so any data the policy "got wrong"
    //     for a specific user is recoverable from the diagnostics
    //     panel — far better than losing it silently.
    //
    // Validation runs eagerly per entry so an unrecognized PARTSTAT
    // / malformed type / empty email still produces a clean
    // `InvalidPayload` for the whole envelope (the existing contract
    // those checks established) — collision dedupe happens AFTER
    // each entry is structurally well-formed.
    let mut entries_by_id: std::collections::BTreeMap<String, Vec<NormalizedAttendee>> =
        std::collections::BTreeMap::new();
    if let Some(attendees) = optional_object_array(&val, "attendees", "calendar_event")? {
        for (index, att) in attendees.iter().enumerate() {
            let normalized = normalize_attendee(att, index)?;
            entries_by_id
                .entry(normalized.attendee_id.clone())
                .or_default()
                .push(normalized);
        }
    }

    // Hoist the per-attendee INSERT prepare out of the loop. A
    // multi-attendee envelope (a recurring meeting with N invitees)
    // would otherwise re-parse the same INSERT N times. The cached
    // statement also amortizes across distinct envelopes within the
    // same apply transaction.
    let mut insert_attendee = conn.prepare_cached(
        "INSERT INTO calendar_event_attendees (event_id, attendee_id, email, name, status)
         VALUES (?1, ?2, ?3, ?4, ?5)",
    )?;
    for (attendee_id, mut group) in entries_by_id {
        // Choose the winner deterministically. Single-entry groups
        // (the common case) skip the canonical-JSON sort entirely.
        if group.len() > 1 {
            // Stable sort on the canonical-JSON of the entry. Stable
            // is belt-and-suspenders — canonical JSON is unique per
            // distinct entry, so two ties would mean genuinely
            // identical entries, and either copy is interchangeable.
            group.sort_by(|a, b| a.canonical.cmp(&b.canonical));

            // Emit one conflict-log row per dropped entry. We use
            // `entity_id` (the calendar event) as the audit key
            // because attendees are not independently synced — the
            // collision is observed against a specific aggregate
            // version, and that version is what a future
            // forensic-debug session needs to look up.
            //
            // `winner_version` is the envelope's HLC; `loser_version`
            // is the same value (the loser arrived in the same
            // envelope). `loser_device_id` is empty — same envelope,
            // same author. The `loser_payload` carries the dropped
            // entry verbatim so the user can see exactly what was
            // discarded; `log_conflict` runs it through the PII
            // scrubber so attendee names land redacted.
            for loser in group.iter().skip(1) {
                log_conflict(
                    conn,
                    &ConflictLogEntry {
                        id: 0,
                        entity_type: std::borrow::Cow::Borrowed(
                            lorvex_domain::naming::ENTITY_CALENDAR_EVENT,
                        ),
                        entity_id: event_id.as_str().to_string(),
                        winner_version: version.to_string(),
                        loser_version: version.to_string(),
                        loser_device_id: String::new(),
                        loser_payload: Some(loser.raw_json.clone()),
                        resolved_at: apply_ts.to_string(),
                        resolution_type: std::borrow::Cow::Borrowed(
                            lorvex_domain::naming::RESOLUTION_ATTENDEE_EMAIL_COLLISION,
                        ),
                    },
                )?;
            }
        }

        // Insert the winner keyed by the synthesized `attendee_id` (the
        // BTreeMap key). `attendee_id` is device-local — never emitted on the
        // wire — and is the shadow join key, so the shadow row pushed below
        // uses the same value.
        //
        // A non-empty `group` is the local-author contract — every
        // entry that reaches this loop came out of
        // `attendee_id -> Vec<NormalizedAttendee>` with at least one
        // push, otherwise the outer key would not exist in the map.
        // Route a contract breach through `ApplyError::InvalidPayload`
        // (rather than `.expect("group is non-empty")`) so the bad
        // envelope surfaces through the same conflict-log / sync-
        // error path every other malformed-attendees signal already
        // uses, without poisoning the apply transaction.
        let winner = group
            .into_iter()
            .next()
            .ok_or_else(|| ApplyError::InvalidPayload(format!(
                "calendar_event payload: attendee group for identity '{attendee_id}' was unexpectedly empty during merge"
            )))?;
        insert_attendee.execute(params![
            &event_id,
            &winner.attendee_id,
            &winner.email,
            winner.name.as_deref(),
            winner.status.as_deref(),
        ])?;
        if let Some(extras) = winner.extras {
            attendee_shadow_rows.push((winner.attendee_id, extras));
        }
    }
    lorvex_sync_payload::attendee_shadow::replace_attendee_shadows(
        conn,
        &event_id,
        &attendee_shadow_rows,
    )?;

    Ok(())
}
