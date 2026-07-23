use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};

use rusqlite::{params, types::ValueRef, Connection};
use serde_json::{Map, Number, Value};

use lorvex_domain::naming;

use super::EnqueueError;

// ---------------------------------------------------------------------------
// Table/PK mapping
// ---------------------------------------------------------------------------

/// Resolve an entity type string to its `(table, pk_column)` pair.
///
/// this function held its own
/// 19-arm match on `entity_type` literals. The single source of
/// truth now lives in [`naming::EntityKind::table_pk`]; this helper
/// is a thin parse-then-lookup wrapper that keeps the legacy
/// `&str -> Result` shape the enqueue caller expects.
pub(super) fn entity_type_to_table(
    entity_type: &str,
) -> Result<(&'static str, &'static str), EnqueueError> {
    naming::EntityKind::parse(entity_type)
        .and_then(|k| k.table_pk())
        .ok_or_else(|| EnqueueError::UnknownEntityType(entity_type.to_string()))
}

// ---------------------------------------------------------------------------
// Snapshot reading
// ---------------------------------------------------------------------------

/// Read the current snapshot of an entity from DB as a JSON Value.
///
/// routing here is keyed on
/// [`crate::payload_build::aggregate::AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN`].
/// For every type listed there
/// (`current_focus`, `focus_schedule`, `daily_review`, `calendar_event`),
/// the canonical
/// [`crate::payload_build::aggregate::build_aggregate_payload`] builder is
/// the SOLE source of payload truth — the envelope always carries
/// `task_ids` / `blocks` / `linked_task_ids+linked_list_ids` / `attendees`
/// and the receiving peer can rebuild its child rows. There is no
/// fall-through to the bare-columns reader for these types: a missing
/// parent row resolves to [`EnqueueError::EntityNotFound`], and a missing
/// builder arm resolves to [`StoreError::Invariant`] inside the builder.
///
/// Preferences have a dedicated store-owned payload builder because
/// `preferences.value` is JSON encoded in a TEXT column; the generic
/// column copier would turn the stored JSON text into a JSON string.
/// Calendar subscriptions also use a dedicated store-owned builder:
/// their definition fields sync, while retry/backoff columns remain
/// device-local despite sharing the same table. Habits use one too: the
/// `weekly` weekday set lives in the `habit_weekdays` child, which the
/// generic column copier cannot materialize into the payload's `weekdays`
/// array.
///
/// For all other entity types this falls back to a `pragma_table_info`-driven
/// generic reader that copies every parent column 1:1. This is correct for
/// entities whose children are independent sync entities (`task`,
/// `list`) and for simple parents
/// (`tag`, `memory`, `memory_revision`,
/// `task_reminder`, `task_checklist_item`, `habit_reminder_policy`).
pub(super) fn read_entity_snapshot(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Value, EnqueueError> {
    // the aggregate builder is the SOLE enqueue entry-point
    // for every entity_type registered in
    // `AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN`. We dispatch on the
    // registry rather than on the builder's `Some/None` return so a
    // missing parent header row resolves to `EntityNotFound` (the
    // standard enqueue failure for "row vanished") instead of silently
    // falling through to the bare-columns reader and shipping an
    // envelope without children. The registry, the builder, and this
    // dispatch are the three load-bearing surfaces; any future
    // aggregate-with-children type only needs to land in those three
    // places to be wired correctly end-to-end.
    if naming::EntityKind::parse(entity_type)
        .is_some_and(crate::payload_build::aggregate::kind_is_aggregate_root_with_embedded_children)
    {
        return crate::payload_build::aggregate::build_aggregate_payload(
            conn,
            entity_type,
            entity_id,
        )?
        .map_or_else(
            || {
                Err(EnqueueError::EntityNotFound {
                    entity_type: entity_type.to_string(),
                    entity_id: entity_id.to_string(),
                })
            },
            Ok,
        );
    }

    if entity_type == naming::ENTITY_PREFERENCE {
        return read_preference_payload_snapshot(conn, entity_id);
    }

    if entity_type == naming::ENTITY_CALENDAR_SUBSCRIPTION {
        return read_calendar_subscription_payload_snapshot(conn, entity_id);
    }

    // Habits use a dedicated store-owned builder: the `weekly` weekday set
    // lives in the `habit_weekdays` child, which the generic column copier
    // below cannot materialize into the payload's `weekdays` array. Routing
    // through the store loader keeps every enqueue path carrying weekdays.
    if entity_type == naming::ENTITY_HABIT {
        return read_habit_payload_snapshot(conn, entity_id);
    }

    let (table, pk_col) = entity_type_to_table(entity_type)?;
    lorvex_domain::assert_safe_sql_identifier(table);
    lorvex_domain::assert_safe_sql_identifier(pk_col);

    // cache the (columns, SELECT SQL) pair per
    // table on first use so the per-envelope `pragma_table_info`
    // round-trip + uncached SELECT prepare disappears from the
    // hot path. Every entity_type registered in
    // `entity_type_to_table` resolves to a stable (table, pk_col)
    // pair for the lifetime of the process; the cache is keyed by
    // table name and the inner String for the SELECT SQL is fed
    // back to `prepare_cached` so the connection's statement cache
    // amortizes preparation across calls inside a single
    // `with_conn` write tx and across separate writes.
    let cached = lookup_or_init_snapshot_cache(conn, table, pk_col)?;

    let mut stmt = conn.prepare_cached(&cached.select_sql)?;
    let mut rows = stmt.query(params![entity_id])?;
    match rows.next()? {
        Some(row) => {
            let mut obj = Map::with_capacity(cached.columns.len());
            for (idx, col_name) in cached.columns.iter().enumerate() {
                let val = sqlite_column_value_to_json(table, col_name, row.get_ref(idx)?)?;
                obj.insert(col_name.clone(), val);
            }
            Ok(Value::Object(obj))
        }
        None => Err(EnqueueError::EntityNotFound {
            entity_type: entity_type.to_string(),
            entity_id: entity_id.to_string(),
        }),
    }
}

/// per-table snapshot read plan, populated lazily
/// on first hit and shared for the life of the process. Storing
/// the SELECT SQL as an owned `String` keeps the cache lookup
/// branch-free of any per-call allocation; `prepare_cached` then
/// re-uses the prepared statement against the connection's own
/// statement cache.
struct SnapshotPlan {
    columns: Vec<String>,
    select_sql: String,
}

fn snapshot_cache() -> &'static RwLock<HashMap<&'static str, &'static SnapshotPlan>> {
    static CACHE: OnceLock<RwLock<HashMap<&'static str, &'static SnapshotPlan>>> = OnceLock::new();
    CACHE.get_or_init(|| RwLock::new(HashMap::new()))
}

fn lookup_or_init_snapshot_cache(
    conn: &Connection,
    table: &'static str,
    pk_col: &'static str,
) -> Result<&'static SnapshotPlan, EnqueueError> {
    // the cache
    // only ever holds immutable `&'static SnapshotPlan` pointers
    // (the `Box::leak` happens once per table, then the pointer is
    // copied). A poisoning panic between the two operations cannot
    // leave the map in a partially-mutated state, so recovering
    // with `into_inner` is safe and avoids tearing down the apply
    // / GC worker on the next read after a panic in any caller.
    // The race-audit follow-up specifically called out that the
    // prior `.expect()` on the `RwLock` was cosmetic-but-real
    // collateral damage from any panic in a sibling caller; the
    // shared recovery path here is the canonical fix.
    if let Some(existing) = snapshot_cache()
        .read()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .get(table)
    {
        return Ok(*existing);
    }

    // Cold path: build the plan, then upgrade to a write lock and
    // insert. Another thread may have inserted concurrently — fall
    // back to that entry rather than overwrite (the value is
    // semantically identical for the same table either way).
    //
    // Defense-in-depth: `table` is guarded inside `pragma_table_columns`
    // before its `format!` interpolation, but `pk_col` only appears in
    // the cold-path SELECT below — assert it here once per table-
    // initialization so a future caller passing a runtime-derived
    // pk_col trips on test runs.
    lorvex_domain::assert_safe_sql_identifier(pk_col);
    let columns = pragma_table_columns(conn, table)?;
    if columns.is_empty() {
        return Err(EnqueueError::UnknownEntityType(format!(
            "(table {table} has no columns)"
        )));
    }
    for col in &columns {
        lorvex_domain::assert_safe_sql_identifier(col);
    }

    // acquire the write lock BEFORE
    // calling `Box::leak`, then re-check the map. The previous
    // ordering allocated and leaked the `SnapshotPlan` unconditionally
    // and then fell back to whatever was already in the map — so two
    // threads racing on the same cold table both leaked a plan even
    // though only one ever became reachable through the map. The
    // surplus allocation was bounded (worst case: every entity table
    // leaked once per losing thread) but it is wasted memory we do
    // not need to spend. Doing the existence check inside the write
    // lock means at most one allocation per table for the lifetime
    // of the process, regardless of how many threads race the cold
    // path.
    //
    // same recovery contract as the
    // `read()` lock above — the cache stores `&'static
    // SnapshotPlan` pointers only, so a prior panic could not have
    // left the map in an inconsistent state.
    let mut writer = snapshot_cache()
        .write()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if let Some(existing) = writer.get(table) {
        return Ok(*existing);
    }
    let col_list = columns.join(", ");
    let select_sql = format!("SELECT {col_list} FROM {table} WHERE {pk_col} = ?1");
    let plan: &'static SnapshotPlan = Box::leak(Box::new(SnapshotPlan {
        columns,
        select_sql,
    }));
    writer.insert(table, plan);
    Ok(plan)
}

fn read_preference_payload_snapshot(conn: &Connection, key: &str) -> Result<Value, EnqueueError> {
    lorvex_store::payload_loaders::load_preference_sync_payload(conn, key)?.ok_or_else(|| {
        EnqueueError::EntityNotFound {
            entity_type: naming::ENTITY_PREFERENCE.to_string(),
            entity_id: key.to_string(),
        }
    })
}

fn read_calendar_subscription_payload_snapshot(
    conn: &Connection,
    id: &str,
) -> Result<Value, EnqueueError> {
    lorvex_store::payload_loaders::load_calendar_subscription_sync_payload(conn, id)?.ok_or_else(
        || EnqueueError::EntityNotFound {
            entity_type: naming::ENTITY_CALENDAR_SUBSCRIPTION.to_string(),
            entity_id: id.to_string(),
        },
    )
}

fn read_habit_payload_snapshot(conn: &Connection, id: &str) -> Result<Value, EnqueueError> {
    let habit_id = lorvex_domain::HabitId::from_trusted(id.to_string());
    lorvex_store::payload_loaders::load_habit_sync_payload(conn, &habit_id)?.ok_or_else(|| {
        EnqueueError::EntityNotFound {
            entity_type: naming::ENTITY_HABIT.to_string(),
            entity_id: id.to_string(),
        }
    })
}

fn pragma_table_columns(
    conn: &Connection,
    table: &'static str,
) -> Result<Vec<String>, EnqueueError> {
    // pragma_table_info is a static SELECT once `table` is interpolated;
    // route through `prepare_cached` so the cold-path query also lands
    // in the connection's statement cache (the cache key includes the
    // table-name interpolation, so first access for each table is the
    // only uncached preparation).
    //
    // assert the table identifier is a safe SQL
    // identifier before the `format!` interpolation. Today every
    // caller passes a `&'static str` from `naming::ENTITY_*` so this
    // is a no-op tripwire — it exists so a future refactor that
    // accepts a runtime-derived `table` name still cannot reach a
    // SQLi sink. Co-locating the guard with the `format!` call (vs.
    // relying on caller hygiene) is the property the audit asked for.
    lorvex_domain::assert_safe_sql_identifier(table);
    let col_sql = format!("SELECT name FROM pragma_table_info('{table}') ORDER BY cid");
    let mut col_stmt = conn.prepare_cached(&col_sql)?;
    let columns: Vec<String> = col_stmt
        .query_map([], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(columns)
}

fn sqlite_column_value_to_json(
    table: &str,
    column: &str,
    val: ValueRef<'_>,
) -> Result<Value, EnqueueError> {
    if lorvex_domain::storage_schema::is_sqlite_bool_column(table, column) {
        return match val {
            ValueRef::Integer(0) => Ok(Value::Bool(false)),
            ValueRef::Integer(1) => Ok(Value::Bool(true)),
            ValueRef::Integer(other) => Err(EnqueueError::Store(
                lorvex_store::StoreError::Serialization(format!(
                    "{table}.{column} must be 0 or 1 before sync enqueue, got {other}"
                )),
            )),
            ValueRef::Null => Ok(Value::Null),
            _ => Err(EnqueueError::Store(
                lorvex_store::StoreError::Serialization(format!(
                    "{table}.{column} must be a SQLite integer boolean before sync enqueue"
                )),
            )),
        };
    }

    Ok(match val {
        ValueRef::Null => Value::Null,
        ValueRef::Integer(v) => Value::Number(Number::from(v)),
        ValueRef::Real(v) => lorvex_domain::serde_support::sqlite_real_to_json(v),
        ValueRef::Text(v) => {
            // surface invalid UTF-8 as a typed error
            // instead of substituting U+FFFD via `from_utf8_lossy`.
            // SQLite's UTF-8 enforcement is a best-effort encoding
            // hint, not a hard constraint — a process writing raw
            // bytes through the BLOB path (legacy migration, manual
            // `sqlite3` insertion, a custom CLI) can store invalid
            // UTF-8 in a TEXT column. Lossy decode silently
            // propagated the corruption into peer envelopes; refuse
            // the enqueue instead so the writer can re-write the row
            // with valid UTF-8 (or surface the corruption to the
            // user) before another peer ever sees the U+FFFD.
            let s = std::str::from_utf8(v).map_err(|err| {
                EnqueueError::Store(lorvex_store::StoreError::Serialization(format!(
                    "{table}.{column} contains invalid UTF-8 ({err}); refusing to enqueue \
                     a corrupt envelope. Re-write the row with a valid UTF-8 value."
                )))
            })?;
            Value::String(s.to_string())
        }
        ValueRef::Blob(v) => {
            // Encode blobs as hex strings for JSON transport. Stream
            // the digits via `write!` into a single pre-sized buffer
            // instead of `format!`-per-byte + `collect()`, which would
            // allocate a fresh 2-byte `String` for every input byte.
            use std::fmt::Write as _;
            let mut hex = String::with_capacity(v.len() * 2);
            for b in v {
                let _ = write!(hex, "{b:02x}");
            }
            Value::String(hex)
        }
    })
}

// ---------------------------------------------------------------------------
// Public snapshot read
// ---------------------------------------------------------------------------

/// Read the current snapshot of an entity from the DB as a JSON
/// `Value`. Thin public wrapper around the internal `read_entity_snapshot`
/// reader so callers outside `outbox_enqueue` (e.g.
/// `startup_trash_purge`) have a stable surface that does not pull
/// the whole table-mapping helper into their visibility scope.
pub fn read_entity_payload_snapshot(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
) -> Result<Value, EnqueueError> {
    read_entity_snapshot(conn, entity_type, entity_id)
}
