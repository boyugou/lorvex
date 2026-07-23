use rusqlite::{types::ValueRef, Connection, Row};
use serde_json::{Map, Number, Value};

/// route every JSON-row helper through `prepare_cached`
/// so the connection's statement cache amortizes preparation across the
/// 157 call sites that share these two helpers. Both helpers receive
/// `&'static str` SQL at every call site (overview, snapshot, query
/// support, list aggregates), so caching is safe — cache keys are SQL
/// bytes and identical static literals collide on the hot path.
pub fn query_all_as_json(
    conn: &Connection,
    sql: &str,
    params: impl rusqlite::Params,
) -> Result<Vec<Value>, rusqlite::Error> {
    let mut stmt = conn.prepare_cached(sql)?;
    let columns: Vec<String> = stmt
        .column_names()
        .iter()
        .map(ToString::to_string)
        .collect();

    let rows = stmt.query_map(params, |row| row_to_json(row, &columns))?;
    rows.collect()
}

pub fn query_one_as_json(
    conn: &Connection,
    sql: &str,
    params: impl rusqlite::Params,
) -> Result<Option<Value>, rusqlite::Error> {
    let mut stmt = conn.prepare_cached(sql)?;
    let columns: Vec<String> = stmt
        .column_names()
        .iter()
        .map(ToString::to_string)
        .collect();

    let mut rows = stmt.query(params)?;
    if let Some(row) = rows.next()? {
        return row_to_json(row, &columns).map(Some);
    }
    Ok(None)
}

fn row_to_json(row: &Row<'_>, columns: &[String]) -> Result<Value, rusqlite::Error> {
    let mut object = Map::with_capacity(columns.len());
    for (index, key) in columns.iter().enumerate() {
        let value = match row.get_ref(index)? {
            ValueRef::Null => Value::Null,
            ValueRef::Integer(v) => Value::Number(Number::from(v)),
            ValueRef::Real(v) => Number::from_f64(v).map_or(Value::Null, Value::Number),
            // #3053 M1: refuse invalid UTF-8 in TEXT columns instead of
            // silently substituting U+FFFD via `from_utf8_lossy`. The
            // outbox enqueuer already enforces this for sync (see
            // `lorvex_sync::outbox_enqueue`), so the read-side MCP
            // helpers here have to mirror the policy or a row that's
            // unsyncable will still appear in `get_overview`,
            // `list_tasks`, etc., spreading the corruption to the
            // assistant prompt before the writer ever notices.
            ValueRef::Text(v) => match std::str::from_utf8(v) {
                Ok(s) => Value::String(s.to_string()),
                Err(error) => {
                    return Err(rusqlite::Error::FromSqlConversionFailure(
                        index,
                        rusqlite::types::Type::Text,
                        Box::new(InvalidUtf8RowText {
                            column: key.clone(),
                            error: error.to_string(),
                        }),
                    ));
                }
            },
            ValueRef::Blob(v) => Value::String(bytes_to_hex(v)),
        };
        object.insert(key.clone(), value);
    }
    Ok(Value::Object(object))
}

/// Error wrapper that carries the offending column name + UTF-8
/// decode error message through `rusqlite::Error::FromSqlConversionFailure`.
/// Same shape as the policy applied in `lorvex_sync::outbox_enqueue`.
#[derive(Debug)]
struct InvalidUtf8RowText {
    column: String,
    error: String,
}

impl std::fmt::Display for InvalidUtf8RowText {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "column `{}` contains invalid UTF-8 ({}); refusing to surface a corrupted row to MCP",
            self.column, self.error
        )
    }
}

impl std::error::Error for InvalidUtf8RowText {}

fn bytes_to_hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write as _;
        let _ = write!(&mut out, "{byte:02x}");
    }
    out
}
