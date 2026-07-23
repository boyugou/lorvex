//! Router microbenchmark for the MCP server.
//!
//! gives us a crate-local Criterion harness so a
//! regression in tool-name lookup, JSON-Schema validation, or
//! changelog assembly shows up as a number rather than a vague "feels
//! slower" report from the JS scale benchmark. The JS benchmark
//! (`npm run benchmark:mcp:scale`) still exists for end-to-end
//! coverage; this harness covers the cheap-to-iterate inner loop.
//!
//! Run with `cargo bench -p lorvex-mcp-server`.
//!
//! the perf audit landed `prepare_cached`, batched
//! snapshot reads, and a streaming canonicalizer. Each of those
//! gets a dedicated bench below so a future regression has a
//! concrete number to land against.

use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion};
use lorvex_mcp_server::bench_support::{
    read_current_entity_snapshot_for_bench, read_current_entity_snapshots_for_bench,
};
use lorvex_store::open_db_in_memory;
use lorvex_sync::canonicalize::canonicalize_json;
use rusqlite::{params, Connection};
use serde_json::{json, Value};
use std::hint::black_box;

fn bench_build_payload(c: &mut Criterion) {
    c.bench_function("router::build_payload (placeholder)", |b| {
        b.iter(|| {
            // Cheap allocation pattern that mimics how the router
            // assembles a tool-call JSON envelope. Replace with the
            // real router::dispatch path once we extract a callable
            // entry point that does not need a live DB connection.
            let value = serde_json::json!({
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {
                    "name": "create_task",
                    "arguments": {
                        "title": "bench title",
                        "priority": 1,
                    },
                },
            });
            black_box(
                serde_json::to_string(&value).expect("bench JSON serialization is infallible"),
            );
        });
    });
}

fn seed_tasks(conn: &Connection, n: usize) -> Vec<String> {
    let mut ids = Vec::with_capacity(n);
    for i in 0..n {
        let id = format!("01900000-0000-7000-8000-{i:012x}");
        let now = "2026-04-27T00:00:00.000Z";
        let version = format!("1745712000000_0000_a1b2c3d4a1b2c3d{:01x}", i % 16);
        conn.execute(
            "INSERT INTO tasks (id, title, status, version, created_at, updated_at) \
             VALUES (?1, ?2, 'open', ?3, ?4, ?4)",
            params![id, format!("bench-task-{i}"), version, now],
        )
        .expect("seed insert");
        ids.push(id);
    }
    ids
}

fn bench_query_one_as_json(c: &mut Criterion) {
    // covers the prepare_cached migration on the
    // shared json_row helpers — measures the common single-row read
    // path used by every MCP write surface's snapshot helpers.
    //
    // The `prepare_uncached_baseline` arm replays the pre-fix shape
    // (`conn.prepare(sql)` + manual JSON row build) so the regression
    // record carries an apples-to-apples before/after delta. Both
    // arms target the same single task row.
    let conn = open_db_in_memory().expect("bench DB open");
    let ids = seed_tasks(&conn, 100);
    let mut group = c.benchmark_group("json_row");
    group.bench_function("query_one_as_json (cached prepare)", |b| {
        let pick = &ids[42];
        b.iter(|| {
            let value = read_current_entity_snapshot_for_bench(
                black_box(&conn),
                black_box("task"),
                black_box(pick.as_str()),
            )
            .expect("bench snapshot read");
            black_box(value);
        });
    });
    group.bench_function("query_one_as_json (uncached baseline)", |b| {
        let pick = &ids[42];
        b.iter(|| {
            // Pre-fix shape: re-prepare on every call. The
            // post-fix `query_one_as_json` routes through
            // `prepare_cached`; the inner read here intentionally
            // does NOT, so the delta between the two arms is a
            // direct measure of the prepare-cache win.
            let mut stmt = conn
                .prepare("SELECT * FROM tasks WHERE id = ?1")
                .expect("prepare");
            let columns: Vec<String> = stmt
                .column_names()
                .iter()
                .map(ToString::to_string)
                .collect();
            let mut rows = stmt
                .query(params![black_box(pick.as_str())])
                .expect("query");
            if let Some(row) = rows.next().expect("row") {
                let mut obj = serde_json::Map::with_capacity(columns.len());
                for (idx, col) in columns.iter().enumerate() {
                    let v: Option<String> = row.get(idx).ok();
                    obj.insert(col.clone(), v.map_or(Value::Null, Value::String));
                }
                black_box(Value::Object(obj));
            }
        });
    });
    group.finish();
}

fn bench_read_entity_snapshot(c: &mut Criterion) {
    // covers the schema-pragma + SELECT cache for the
    // outbox enqueue snapshot reader. The harness exercises the
    // public per-entity reader; the cached pragma only pays for the
    // first call per process so we keep the bench inside a single
    // group and rely on the `prepare_cached` SELECT amortization to
    // dominate steady-state cost.
    //
    // The `pragma_per_call_baseline` arm reproduces the pre-fix
    // shape exactly: pragma_table_info + uncached SELECT prepare on
    // every iteration. The delta between the two arms is the win
    // attributable to the schema-pragma cache + cached SELECT.
    let conn = open_db_in_memory().expect("bench DB open");
    let ids = seed_tasks(&conn, 100);
    let mut group = c.benchmark_group("outbox_enqueue::read_entity_snapshot");
    group.bench_function("task (cached pragma + cached prepare)", |b| {
        let pick = &ids[7];
        b.iter(|| {
            let value = read_current_entity_snapshot_for_bench(
                black_box(&conn),
                black_box("task"),
                black_box(pick.as_str()),
            )
            .expect("snapshot");
            black_box(value);
        });
    });
    group.bench_function("task (pragma + uncached prepare baseline)", |b| {
        let pick = &ids[7];
        b.iter(|| {
            // Pre-fix shape: discover columns via pragma every call,
            // build a per-call SELECT, prepare it uncached.
            let mut col_stmt = conn
                .prepare("SELECT name FROM pragma_table_info('tasks') ORDER BY cid")
                .expect("pragma prepare");
            let columns: Vec<String> = col_stmt
                .query_map([], |row| row.get::<_, String>(0))
                .expect("pragma query")
                .collect::<Result<Vec<_>, _>>()
                .expect("pragma collect");
            drop(col_stmt);
            let col_list = columns.join(", ");
            let sql = format!("SELECT {col_list} FROM tasks WHERE id = ?1");
            let mut stmt = conn.prepare(&sql).expect("prepare");
            let mut rows = stmt
                .query(params![black_box(pick.as_str())])
                .expect("query");
            if let Some(row) = rows.next().expect("row") {
                let mut obj = serde_json::Map::with_capacity(columns.len());
                for (idx, col) in columns.iter().enumerate() {
                    let v: Option<String> = row.get(idx).ok();
                    obj.insert(col.clone(), v.map_or(Value::Null, Value::String));
                }
                black_box(Value::Object(obj));
            }
        });
    });
    group.finish();
}

fn bench_read_entity_snapshots_batched(c: &mut Criterion) {
    // per-entity SELECT-in-loop vs. one IN-list
    // SELECT for the funnel's batch-write path. Compare both shapes
    // at N=20 (typical batch_create_tasks payload).
    let conn = open_db_in_memory().expect("bench DB open");
    let ids = seed_tasks(&conn, 100);
    let batch: Vec<String> = ids[10..30].to_vec();
    let mut group = c.benchmark_group("snapshot_batch");
    group.bench_with_input(BenchmarkId::new("loop", batch.len()), &batch, |b, batch| {
        b.iter(|| {
            for id in batch {
                let _ = read_current_entity_snapshot_for_bench(
                    black_box(&conn),
                    black_box("task"),
                    black_box(id.as_str()),
                )
                .expect("loop snapshot");
            }
        });
    });
    group.bench_with_input(
        BenchmarkId::new("batched", batch.len()),
        &batch,
        |b, batch| {
            b.iter(|| {
                let map = read_current_entity_snapshots_for_bench(
                    black_box(&conn),
                    black_box("task"),
                    black_box(batch),
                )
                .expect("batched snapshot");
                black_box(map);
            });
        },
    );
    group.finish();
}

fn bench_canonicalize(c: &mut Criterion) {
    // streaming canonicalizer vs. clone-heavy
    // sort-keys pre-fix. The harness only exercises the post-fix
    // path; the regression hook is the steady-state ns/op number
    // recorded here.
    let payload: Value = json!({
        "id": "01900000-0000-7000-8000-aaaaaaaaaaaa",
        "title": "perf bench task",
        "body": "lorem ipsum dolor sit amet ".repeat(20),
        "status": "open",
        "priority": 1,
        "tags": ["alpha", "beta", "gamma", "delta", "epsilon"],
        "checklist_items": [
            {"id": "ci-1", "text": "first", "checked": false},
            {"id": "ci-2", "text": "second", "checked": true},
            {"id": "ci-3", "text": "third", "checked": false},
        ],
        "ai_notes": "synthetic note about scheduling",
        "created_at": "2026-04-27T00:00:00.000Z",
        "updated_at": "2026-04-27T00:00:00.000Z",
        "version": "1745712000000_0000_a1b2c3d4a1b2c3d4",
    });

    let mut group = c.benchmark_group("canonicalize_json");
    group.bench_function("typical task payload (streaming)", |b| {
        b.iter(|| {
            let s = canonicalize_json(black_box(&payload)).expect("canonicalize");
            black_box(s);
        });
    });
    // Pre-fix baseline: build a sorted Value tree (cloning every
    // scalar via `other.clone()`) then serialize through
    // `serde_json::to_string`. The two arms read the same input.
    group.bench_function("typical task payload (sort-keys-clone baseline)", |b| {
        b.iter(|| {
            let sorted = sort_keys_clone(black_box(&payload));
            let s = serde_json::to_string(&sorted).expect("serialize");
            black_box(s);
        });
    });
    group.finish();
}

/// Pre-fix `sort_keys_inner` shape: clone every scalar through the
/// recursion. Lives in the bench harness only so the criterion
/// regression record carries an apples-to-apples baseline number.
fn sort_keys_clone(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut entries: Vec<(&String, &Value)> = map.iter().collect();
            entries.sort_by_key(|(k, _)| *k);
            let mut sorted_map: serde_json::Map<String, Value> =
                serde_json::Map::with_capacity(entries.len());
            for (k, v) in entries {
                sorted_map.insert(k.clone(), sort_keys_clone(v));
            }
            Value::Object(sorted_map)
        }
        Value::Array(arr) => {
            let mut out: Vec<Value> = Vec::with_capacity(arr.len());
            for v in arr.iter() {
                out.push(sort_keys_clone(v));
            }
            Value::Array(out)
        }
        other => other.clone(),
    }
}

criterion_group!(
    benches,
    bench_build_payload,
    bench_query_one_as_json,
    bench_read_entity_snapshot,
    bench_read_entity_snapshots_batched,
    bench_canonicalize,
);
criterion_main!(benches);
