use super::read::list_task_checklist_items;
use crate::error::StoreError;
use crate::transaction::with_immediate_transaction_breaker_exempt;
use lorvex_domain::checklist::extract_markdown_checklist;
use lorvex_domain::hlc::HlcSurface;
use lorvex_domain::hlc_state::{HlcState, MAX_COUNTER};
use lorvex_runtime::{device_id_to_hlc_suffix, get_or_create_device_id};
use rusqlite::{params, Connection};

/// Cap how many checklist items a single body promotion can create.
///
/// Each per-item INSERT mints a fresh HLC via `HlcState::generate`,
/// which auto-rolls the physical_ms forward when the per-ms counter
/// hits `MAX_COUNTER` (=9999). The roll-forward is correct, but a
/// pathological body with tens of thousands of `- [ ] item` lines
/// would (a) advance the local clock past anything reasonable for a
/// startup migration and (b) explode startup latency. The cap is
/// generous enough that no real-world note hits it, and acts as a
/// belt-and-suspenders bound against malformed input. Tasks that
/// genuinely need more than this should split into multiple tasks.
const MAX_CHECKLIST_ITEMS_PER_PROMOTION: usize = MAX_COUNTER as usize;

/// Promote markdown-style checklist lines in `tasks.body` into rows of
/// `task_checklist_items`. Idempotent: once a task's body has been
/// stripped of `- [ ] item` lines, the LIKE filter no longer matches
/// it, so subsequent boots are no-ops.
///
/// the migration now stamps the
/// produced `tasks.version` and per-item versions with this device's
/// **real** HLC suffix, derived from `sync_checkpoints.device_id` via
/// the canonical [`device_id_to_hlc_suffix`] helper. The previous
/// shape used a synthetic all-zero suffix (`"0000000000000000"`),
/// which sorts strictly below every real device's hex suffix — so a
/// future peer edit at the same physical_ms + counter would always
/// win the LWW comparison and silently clobber a freshly-promoted
/// row. Using the real suffix means LWW is decided by physical_ms +
/// counter, exactly as for any other write the device emits, and the
/// rare same-instant tie still resolves deterministically against a
/// concurrent peer's distinct hex suffix.
///
/// If the `sync_checkpoints` table or device-id row cannot be read
/// (very early boot, an externally-truncated DB), the promotion is
/// deferred: the function returns Ok without touching any tasks. The
/// next normal cold-open will run the promotion once the device id
/// has been seeded. Skipping is safer than stamping a synthetic
/// suffix that would lose every conflict.
///
/// the entire promotion runs inside a single
/// `BEGIN IMMEDIATE` transaction. A crash between the body rewrite
/// and the per-item INSERTs would otherwise permanently lose the
/// checklist items (the subsequent boot saw a body without the
/// checklist marker and never re-extracted them).
///
/// the wrapper is the breaker-exempt variant. This helper
/// runs on every cold DB open (`open_db_at_path`, `ConnectionPool::new`),
/// and the disk-full circuit breaker is a process-global static that
/// any concurrent caller can flip — including parallel tests that
/// exercise the breaker itself. Catching `SQLITE_FULL` from the
/// underlying `BEGIN IMMEDIATE` is the correct startup-path failure
/// mode; the breaker is meaningful only at the live-write surface.
pub(crate) fn promote_markdown_task_checklists(conn: &Connection) -> Result<(), StoreError> {
    with_immediate_transaction_breaker_exempt::<_, StoreError>(conn, promote_inner)
}

fn promote_inner(conn: &Connection) -> Result<(), StoreError> {
    // Survey first — if no candidate body exists, skip every other
    // step. This keeps cold-open quiet on a fresh DB: no
    // `sync_checkpoints.device_id` row gets seeded just to derive an
    // HLC suffix the migration would never have stamped anyway.
    let mut stmt = conn.prepare(
        "SELECT id, body
         FROM tasks
         WHERE body IS NOT NULL
           AND archived_at IS NULL
           AND (body LIKE '%- [ ] %' OR body LIKE '%- [x] %' OR body LIKE '%- [X] %')
         ORDER BY created_at ASC, id ASC",
    )?;
    // Archived (trashed) tasks must NOT be touched by the cold-open
    // promotion. A trashed task whose body still carries markdown
    // checklist syntax retains the body verbatim — un-trashing
    // restores the row exactly as the user archived it. Rewriting
    // the body and INSERTing per-item rows on trashed tasks would
    // mean an un-trash surfaces a different body than the user
    // archived (the markdown checklist syntax replaced by structured
    // checklist_items). The forward-migration is a one-time cold-open
    // transform; trashed rows are out of scope until the user
    // actively un-trashes them.
    let rows = stmt
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    drop(stmt);
    if rows.is_empty() {
        return Ok(());
    }

    // derive the local device's real
    // HLC suffix. If the device id is unavailable (very early boot,
    // truncated DB) defer promotion — the next cold-open will retry
    // once `sync_checkpoints` is seeded. Stamping a synthetic suffix
    // here would lose every cross-device LWW comparison the row
    // later participates in.
    let Ok(device_id) = get_or_create_device_id(conn) else {
        return Ok(());
    };
    // The store-level promotion runs before any surface-level HLC
    // init; tag the suffix as `App` so the rare cross-process
    // tiebreak with this device's MCP / CLI surfaces still differs.
    // Promotion itself is idempotent (the LIKE filter no longer
    // matches once the body is rewritten), so the tag choice does
    // not affect correctness — it only matters for the LWW tiebreak
    // at the same physical_ms + counter.
    let device_suffix = device_id_to_hlc_suffix(&device_id, HlcSurface::App);

    // route every minted version through `HlcState::generate`
    // rather than the prior raw `format!("{physical_ms:013}_{counter:04}_{device_suffix}")`.
    // The state-managed path enforces:
    //   * the `MAX_HLC_PHYSICAL_MS` lex-sort ceiling (a wall-clock
    //     skew cannot produce a 14-digit physical that escapes the
    //     ordering invariant);
    //   * counter overflow recovery (>9999 items in the same ms
    //     auto-rolls physical_ms forward by 1 instead of widening the
    //     `:04` slot to 5 digits and breaking lex-sort);
    //   * suffix validation (rejects malformed device suffixes at
    //     construction rather than at the first generate call).
    // The `HlcState::new` call cannot fail in practice — the suffix
    // came straight from `device_id_to_hlc_suffix` which always emits
    // a canonical 16-hex form — but the `?` propagates rather than
    // panics if a future helper drift introduces an invalid suffix.
    let mut hlc_state = HlcState::new(&device_suffix).map_err(|e| {
        StoreError::Invariant(format!(
            "task_checklists: failed to construct HlcState for device suffix {device_suffix:?}: {e:?}"
        ))
    })?;

    // Use millisecond `Z` form to match `sync_timestamp_now()` (see
    // `lorvex-domain/src/time/sync_timestamp.rs`) — the markdown-checklist
    // promotion writes `tasks.updated_at` and
    // `task_checklist_items.created_at/updated_at`, and mixed
    // millisecond/microsecond precision in the same column breaks
    // lex comparison at the fractional-second boundary (see R11/R12).
    let now = lorvex_domain::sync_timestamp_now();

    for (task_id, body) in rows {
        let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
        let existing = list_task_checklist_items(conn, &task_id_typed)?;
        if !existing.is_empty() {
            continue;
        }

        let extracted = extract_markdown_checklist(&body);
        if extracted.items.is_empty() {
            continue;
        }

        // cap items per task before promotion so a
        // pathological body with tens of thousands of checklist
        // lines cannot run away with startup latency or push the
        // local HLC physical clock far into the future via the
        // counter-overflow roll-forward inside `HlcState::generate`.
        // We TRUNCATE rather than refuse so a 10001-item note still
        // gets the first 9999 items promoted; the remaining items
        // stay in `body` for a follow-up cleanup. Tasks that
        // genuinely need this many items should split into multiple
        // tasks (the cap matches `MAX_COUNTER`).
        let items_iter = extracted
            .items
            .iter()
            .take(MAX_CHECKLIST_ITEMS_PER_PROMOTION);

        let next_body = if extracted.remaining_body.trim().is_empty() {
            None
        } else {
            Some(extracted.remaining_body.clone())
        };
        let task_version = hlc_state.generate().to_string();
        // gate the UPDATE on `?4 > tasks.version`. The
        // promotion runs at every cold open. If a peer write or a
        // previous run produced a tasks.version with a higher HLC
        // (e.g. a sync envelope landed during the first cold-open
        // promotion and bumped the row to a strictly-newer HLC
        // before this batch's turn), promoting without an LWW guard
        // would silently roll the row's version backwards and
        // clobber that peer write on the next outbox push. The guard
        // makes the UPDATE a no-op in that case (rows.changed() == 0)
        // and we skip the per-item INSERTs to keep the body+items
        // pair consistent — the next cold-open will retry once the
        // clock catches up or emit no work if the body has already
        // been rewritten by the peer that won the race.
        let updated = conn
            .prepare_cached(
                "UPDATE tasks SET body = ?2, updated_at = ?3, version = ?4 \
                 WHERE id = ?1 AND ?4 > version",
            )?
            .execute(params![task_id, next_body, now, task_version])?;
        if updated == 0 {
            // The row's version is >= our migration_version. A peer or
            // a prior run won the race; skip per-item INSERTs to keep
            // the body and the checklist-item rowset consistent (we
            // didn't rewrite the body, so re-extracting items would
            // double them on the next pass).
            continue;
        }

        // Lift the per-item INSERT prepare out of the loop so a task
        // with N checklist items pays one parse instead of N. The SQL
        // is constant; only the bound params change per row.
        let mut item_stmt = conn.prepare_cached(
            "INSERT INTO task_checklist_items (
                id, task_id, position, text, completed_at, version, created_at, updated_at
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7) \
             ON CONFLICT(id) DO UPDATE SET \
                 task_id = excluded.task_id, \
                 position = excluded.position, \
                 text = excluded.text, \
                 completed_at = excluded.completed_at, \
                 version = excluded.version, \
                 updated_at = excluded.updated_at \
             WHERE excluded.version > task_checklist_items.version",
        )?;
        for item in items_iter {
            let completed_at = item.completed.then(|| now.clone());
            let version = hlc_state.generate().to_string();
            // Per-item LWW upsert (`ON CONFLICT(id) DO UPDATE …
            // WHERE excluded.version > task_checklist_items.version`)
            // — see #2945 for why a bare INSERT would silently
            // overwrite a peer envelope that lands on the same item
            // id during cold-open promotion.
            item_stmt.execute(params![
                lorvex_domain::new_entity_id_string(),
                task_id,
                item.position,
                item.text,
                completed_at,
                version,
                now,
            ])?;
        }
    }

    Ok(())
}
