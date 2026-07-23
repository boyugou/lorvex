//! `daily_review` aggregate payload builder.
//!
//! Header columns from `daily_reviews` plus the materialized
//! `linked_task_ids` / `linked_list_ids` collections rebuilt from
//! the per-review link tables.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};

use lorvex_store::StoreError;

pub(super) fn build_daily_review_payload(
    conn: &Connection,
    date: &str,
) -> Result<Option<Value>, StoreError> {
    // load the full set of header columns the apply pipeline
    // expects (see lorvex_sync::apply::day_scoped::apply_daily_review_upsert).
    // Mirroring the column shape of the apply path keeps both sides in sync
    // without a typed DTO; if a new column appears it must land here AND in
    // the apply handler.
    type Row = (
        String,         // date
        String,         // summary
        Option<i64>,    // mood
        Option<i64>,    // energy_level
        Option<String>, // wins
        Option<String>, // blockers
        Option<String>, // learnings
        Option<String>, // ai_synthesis
        Option<String>, // timezone
        String,         // created_at
        String,         // updated_at
    );
    let header: Option<Row> = conn
        .query_row(
            "SELECT date, summary, mood, energy_level, wins, blockers, learnings,
                    ai_synthesis, timezone, created_at, updated_at
             FROM daily_reviews WHERE date = ?1",
            params![date],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                    row.get(8)?,
                    row.get(9)?,
                    row.get(10)?,
                ))
            },
        )
        .optional()?;

    let Some((
        date,
        summary,
        mood,
        energy_level,
        wins,
        blockers,
        learnings,
        ai_synthesis,
        timezone,
        created_at,
        updated_at,
    )) = header
    else {
        return Ok(None);
    };

    let task_ids = query_review_task_links(conn, &date)?;
    let list_ids = query_review_list_links(conn, &date)?;

    Ok(Some(json!({
        "date": date,
        "summary": summary,
        "mood": mood,
        "energy_level": energy_level,
        "wins": wins,
        "blockers": blockers,
        "learnings": learnings,
        "ai_synthesis": ai_synthesis,
        "timezone": timezone,
        "created_at": created_at,
        "updated_at": updated_at,
        "linked_task_ids": task_ids,
        "linked_list_ids": list_ids,
    })))
}

fn query_review_task_links(conn: &Connection, date: &str) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT task_id FROM daily_review_task_links WHERE review_date = ?1 ORDER BY created_at ASC",
    )?;
    let ids = stmt
        .query_map(params![date], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(ids)
}

fn query_review_list_links(conn: &Connection, date: &str) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT list_id FROM daily_review_list_links WHERE review_date = ?1 ORDER BY created_at ASC",
    )?;
    let ids = stmt
        .query_map(params![date], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(ids)
}
