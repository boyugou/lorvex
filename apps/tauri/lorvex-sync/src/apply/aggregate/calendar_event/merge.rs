use std::borrow::Cow;
use std::collections::BTreeMap;

use rusqlite::{named_params, params, Connection, OptionalExtension};
use serde_json::{json, Value};

use super::super::ApplyError;
use crate::apply::device_identity::read_local_device_hlc_suffix;
use crate::conflict_log::{log_conflict, ConflictLogEntry};

#[derive(Clone)]
struct OverrideSnapshot {
    title: String,
    description: Option<String>,
    start_date: String,
    start_time: Option<String>,
    end_date: Option<String>,
    end_time: Option<String>,
    all_day: i64,
    location: Option<String>,
    url: Option<String>,
    color: Option<String>,
    timezone: Option<String>,
    event_type: String,
    person_name: Option<String>,
}

/// Collapse calendar override rows sharing `(series_id,
/// recurrence_instance_date)`. `min(id)` wins, matching task
/// recurrence dedup and the Apple apply path. Returns false when the
/// just-upserted event became the loser, so the caller must not rebuild
/// child materializations for a deleted row.
pub(super) fn merge_duplicate_override_instances(
    conn: &Connection,
    just_upserted_id: &str,
    series_id: &str,
    recurrence_instance_date: &str,
    triggering_version: &str,
    apply_ts: &str,
) -> Result<bool, ApplyError> {
    let mut participants = BTreeMap::<String, String>::new();
    {
        let mut stmt = conn.prepare_cached(
            "SELECT id, version FROM calendar_events
             WHERE series_id = ?1 AND recurrence_instance_date = ?2",
        )?;
        let rows = stmt.query_map(params![series_id, recurrence_instance_date], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (id, version) = row?;
            participants.insert(id, version);
        }
    }
    if let Some(version) = conn
        .prepare_cached("SELECT version FROM calendar_events WHERE id = ?1")?
        .query_row(params![just_upserted_id], |row| row.get::<_, String>(0))
        .optional()?
    {
        participants.insert(just_upserted_id.to_string(), version);
    }

    if participants.len() <= 1 {
        return Ok(true);
    }

    let event_ids: Vec<String> = participants.keys().cloned().collect();
    let event_versions: Vec<String> = event_ids
        .iter()
        .map(|id| {
            participants
                .get(id)
                .expect("participant id/version map")
                .clone()
        })
        .collect();

    lorvex_store::transaction::with_savepoint_mapped(
        conn,
        "merge_calendar_override",
        ApplyError::InvalidPayload,
        |conn| {
            merge_override_inner(
                conn,
                &event_ids,
                &event_versions,
                just_upserted_id,
                series_id,
                recurrence_instance_date,
                triggering_version,
                apply_ts,
            )
        },
    )
}

fn merge_override_inner(
    conn: &Connection,
    event_ids: &[String],
    event_versions: &[String],
    just_upserted_id: &str,
    series_id: &str,
    recurrence_instance_date: &str,
    triggering_version: &str,
    apply_ts: &str,
) -> Result<bool, ApplyError> {
    let winner_id = &event_ids[0];
    let mut snapshots = read_snapshots(conn, event_ids)?;
    let winner_snapshot = snapshots.remove(winner_id).ok_or_else(|| {
        ApplyError::Store(lorvex_store::StoreError::Invariant(format!(
            "calendar override merge winner {winner_id} missing from batched snapshot read"
        )))
    })?;

    let mut max_hlc = lorvex_domain::hlc::Hlc::parse(triggering_version)?;
    for event_version in event_versions {
        match lorvex_domain::hlc::Hlc::parse(event_version) {
            Ok(hlc) if hlc > max_hlc => max_hlc = hlc,
            Ok(_) => {}
            Err(parse_err) => {
                let dedup_signature =
                    format!("calendar_override_merge|max_hlc_unparseable|{event_version}");
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "sync.apply.calendar_override_merge_unparseable_version",
                    &format!(
                        "calendar override merge: skipping unparseable event_version \
                         {event_version:?} during max-HLC computation (parse_err={parse_err})"
                    ),
                    Some(&dedup_signature),
                    Some("warn"),
                );
            }
        }
    }

    let merge_suffix =
        read_local_device_hlc_suffix(conn).unwrap_or_else(|| max_hlc.device_suffix().to_string());
    let merge_hlc = crate::apply::merge_hlc::mint_merge_hlc_after(
        &max_hlc,
        &merge_suffix,
        "calendar override merge",
    )?;
    let merge_version = merge_hlc.to_string();
    crate::hlc::observe_local_event(&merge_hlc);

    let mut repoint_links = conn.prepare_cached(
        "INSERT INTO task_calendar_event_links
             (task_id, calendar_event_id, created_at, updated_at, version)
         SELECT task_id, :winner_id, :now, :now, :merge_version
           FROM task_calendar_event_links
          WHERE calendar_event_id = :loser_id
         ON CONFLICT(task_id, calendar_event_id) DO UPDATE SET
             version = :merge_version,
             created_at = excluded.created_at,
             updated_at = excluded.updated_at",
    )?;
    let mut delete_links =
        conn.prepare_cached("DELETE FROM task_calendar_event_links WHERE calendar_event_id = ?1")?;
    let mut repoint_focus_blocks = conn.prepare_cached(
        "UPDATE focus_schedule_blocks SET event_id = :winner_id WHERE event_id = :loser_id",
    )?;
    let mut delete_loser = conn.prepare_cached("DELETE FROM calendar_events WHERE id = ?1")?;

    for (loser_idx, loser_id) in event_ids[1..].iter().enumerate() {
        let loser_version = event_versions[loser_idx + 1].clone();
        let loser_snapshot = snapshots.remove(loser_id).ok_or_else(|| {
            ApplyError::Store(lorvex_store::StoreError::Invariant(format!(
                "calendar override merge loser {loser_id} missing from batched snapshot read"
            )))
        })?;
        let loser_payload = divergent_loser_fields(&winner_snapshot, &loser_snapshot);
        let loser_device_id = match lorvex_domain::hlc::Hlc::parse(&loser_version) {
            Ok(hlc) => hlc.device_suffix().to_string(),
            Err(parse_err) => {
                let dedup_signature =
                    format!("calendar_override_merge|conflict_unparseable|{loser_version}");
                lorvex_store::error_log::append_error_log_best_effort(
                    conn,
                    "sync.apply.calendar_override_merge_unparseable_version",
                    &format!(
                        "calendar override merge: tainted loser_version {loser_version:?} \
                         for winner={winner_id:?}, loser={loser_id:?} (parse_err={parse_err})"
                    ),
                    Some(&dedup_signature),
                    Some("warn"),
                );
                loser_version.clone()
            }
        };
        log_conflict(
            conn,
            &ConflictLogEntry {
                id: 0,
                entity_type: Cow::Borrowed(lorvex_domain::naming::ENTITY_CALENDAR_EVENT),
                entity_id: winner_id.clone(),
                winner_version: merge_version.clone(),
                loser_version,
                loser_device_id,
                loser_payload,
                resolved_at: apply_ts.to_string(),
                resolution_type: Cow::Borrowed(lorvex_domain::naming::RESOLUTION_RECURRENCE_DEDUP),
            },
        )?;

        repoint_links.execute(named_params! {
            ":winner_id": winner_id,
            ":merge_version": &merge_version,
            ":now": apply_ts,
            ":loser_id": loser_id,
        })?;
        delete_links.execute(params![loser_id])?;
        repoint_focus_blocks.execute(named_params! {
            ":winner_id": winner_id,
            ":loser_id": loser_id,
        })?;
        delete_loser.execute(params![loser_id])?;
        crate::tombstone::create_tombstone(
            conn,
            lorvex_domain::naming::ENTITY_CALENDAR_EVENT,
            loser_id,
            &merge_version,
            apply_ts,
            Some(winner_id.as_str()),
            Some(lorvex_domain::naming::ENTITY_CALENDAR_EVENT),
        )
        .map_err(ApplyError::Store)?;
    }

    conn.prepare_cached(
        "UPDATE calendar_events
            SET series_id = ?1, recurrence_instance_date = ?2
          WHERE id = ?3",
    )?
    .execute(params![series_id, recurrence_instance_date, winner_id])?;
    crate::apply::stamp_merge_winner_version(
        conn,
        "calendar_events",
        "id",
        winner_id,
        &merge_version,
    )?;

    Ok(winner_id == just_upserted_id)
}

fn read_snapshots(
    conn: &Connection,
    event_ids: &[String],
) -> Result<BTreeMap<String, OverrideSnapshot>, ApplyError> {
    let placeholders = lorvex_domain::sql_in_placeholders(event_ids.len(), 0);
    let sql = format!(
        "SELECT id, title, description, start_date, start_time, end_date, end_time,
                all_day, location, url, color, timezone, event_type, person_name
           FROM calendar_events
          WHERE id IN ({placeholders})"
    );
    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map(
        rusqlite::params_from_iter(event_ids.iter().map(String::as_str)),
        |row| {
            Ok((
                row.get::<_, String>(0)?,
                OverrideSnapshot {
                    title: row.get(1)?,
                    description: row.get(2)?,
                    start_date: row.get(3)?,
                    start_time: row.get(4)?,
                    end_date: row.get(5)?,
                    end_time: row.get(6)?,
                    all_day: row.get(7)?,
                    location: row.get(8)?,
                    url: row.get(9)?,
                    color: row.get(10)?,
                    timezone: row.get(11)?,
                    event_type: row.get(12)?,
                    person_name: row.get(13)?,
                },
            ))
        },
    )?;
    let mut out = BTreeMap::new();
    for row in rows {
        let (id, snapshot) = row?;
        out.insert(id, snapshot);
    }
    Ok(out)
}

fn divergent_loser_fields(winner: &OverrideSnapshot, loser: &OverrideSnapshot) -> Option<String> {
    let mut divergent = serde_json::Map::new();
    record(
        &mut divergent,
        "title",
        Some(&winner.title),
        Some(&loser.title),
    );
    record(
        &mut divergent,
        "description",
        winner.description.as_ref(),
        loser.description.as_ref(),
    );
    record(
        &mut divergent,
        "start_date",
        Some(&winner.start_date),
        Some(&loser.start_date),
    );
    record(
        &mut divergent,
        "start_time",
        winner.start_time.as_ref(),
        loser.start_time.as_ref(),
    );
    record(
        &mut divergent,
        "end_date",
        winner.end_date.as_ref(),
        loser.end_date.as_ref(),
    );
    record(
        &mut divergent,
        "end_time",
        winner.end_time.as_ref(),
        loser.end_time.as_ref(),
    );
    if winner.all_day != loser.all_day {
        divergent.insert("all_day".to_string(), json!(loser.all_day));
    }
    record(
        &mut divergent,
        "location",
        winner.location.as_ref(),
        loser.location.as_ref(),
    );
    record(
        &mut divergent,
        "url",
        winner.url.as_ref(),
        loser.url.as_ref(),
    );
    record(
        &mut divergent,
        "color",
        winner.color.as_ref(),
        loser.color.as_ref(),
    );
    record(
        &mut divergent,
        "timezone",
        winner.timezone.as_ref(),
        loser.timezone.as_ref(),
    );
    record(
        &mut divergent,
        "event_type",
        Some(&winner.event_type),
        Some(&loser.event_type),
    );
    record(
        &mut divergent,
        "person_name",
        winner.person_name.as_ref(),
        loser.person_name.as_ref(),
    );
    if divergent.is_empty() {
        return None;
    }
    Some(
        serde_json::to_string(&Value::Object(divergent))
            .expect("calendar-override divergence map must serialize"),
    )
}

fn record(
    out: &mut serde_json::Map<String, Value>,
    key: &'static str,
    winner: Option<&String>,
    loser: Option<&String>,
) {
    if winner != loser {
        out.insert(
            key.to_string(),
            loser.map_or(Value::Null, |value| json!(value)),
        );
    }
}
