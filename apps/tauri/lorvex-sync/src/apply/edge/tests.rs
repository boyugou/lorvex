use super::*;
use crate::test_db;
use rusqlite::{params, Connection};

/// HLC versions used across tests. Lexicographic ordering matches temporal ordering.
const V_OLD: &str = "1711234567000_0000_dec0000100000001";
const V_MID: &str = "1711234568000_0000_dec0000100000001";
const V_NEW: &str = "1711234569000_0000_dec0000100000001";

const ZERO_VERSION: &str = "0000000000000_0000_0000000000000000";

/// Insert a minimal task row so FK constraints on task_tags / task_dependencies are satisfied.
fn insert_task(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at) \
         VALUES (?1, 'T', 'open', ?2, '', '')",
        params![id, ZERO_VERSION],
    )
    .unwrap();
}

/// Insert a minimal tag row so FK constraints on task_tags are satisfied.
fn insert_tag(conn: &Connection, id: &str) {
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, color, version, created_at, updated_at) \
         VALUES (?1, 'Tag', ?1, NULL, ?2, '', '')",
        params![id, ZERO_VERSION],
    )
    .unwrap();
}

fn task_tag_payload(created_at: &str) -> String {
    serde_json::json!({ "created_at": created_at }).to_string()
}

fn task_dependency_payload(created_at: &str) -> String {
    serde_json::json!({ "created_at": created_at }).to_string()
}

fn count_task_tags(conn: &Connection) -> i64 {
    conn.query_row("SELECT COUNT(*) FROM task_tags", [], |r| r.get(0))
        .unwrap()
}

fn count_task_dependencies(conn: &Connection) -> i64 {
    conn.query_row("SELECT COUNT(*) FROM task_dependencies", [], |r| r.get(0))
        .unwrap()
}

fn get_task_tag_version(conn: &Connection, task_id: &str, tag_id: &str) -> Option<String> {
    conn.query_row(
        "SELECT version FROM task_tags WHERE task_id = ?1 AND tag_id = ?2",
        params![task_id, tag_id],
        |r| r.get(0),
    )
    .ok()
}

// -----------------------------------------------------------------------
// apply_task_tag_upsert: insert
// -----------------------------------------------------------------------

#[test]
fn task_tag_upsert_inserts_new_edge() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_tag(&conn, "tag-1");

    let payload = task_tag_payload("2026-01-01T00:00:00Z");
    apply_task_tag_upsert(&conn, "task-1:tag-1", &payload, V_MID, false.into(), "").unwrap();

    assert_eq!(count_task_tags(&conn), 1);
    assert_eq!(
        get_task_tag_version(&conn, "task-1", "tag-1").unwrap(),
        V_MID
    );
}

// -----------------------------------------------------------------------
// apply_task_tag_upsert: LWW — older version is skipped
// -----------------------------------------------------------------------

#[test]
fn task_tag_upsert_skips_older_version() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_tag(&conn, "tag-1");

    let payload = task_tag_payload("2026-01-01T00:00:00Z");
    apply_task_tag_upsert(&conn, "task-1:tag-1", &payload, V_NEW, false.into(), "").unwrap();

    // Attempt with an older version — should be silently skipped.
    let stale = task_tag_payload("2025-12-01T00:00:00Z");
    apply_task_tag_upsert(&conn, "task-1:tag-1", &stale, V_OLD, false.into(), "").unwrap();

    assert_eq!(count_task_tags(&conn), 1);
    assert_eq!(
        get_task_tag_version(&conn, "task-1", "tag-1").unwrap(),
        V_NEW
    );
}

// -----------------------------------------------------------------------
// apply_task_tag_delete
// -----------------------------------------------------------------------

#[test]
fn task_tag_delete_removes_edge() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_tag(&conn, "tag-1");

    let payload = task_tag_payload("2026-01-01T00:00:00Z");
    apply_task_tag_upsert(&conn, "task-1:tag-1", &payload, V_MID, false.into(), "").unwrap();
    assert_eq!(count_task_tags(&conn), 1);

    // edge deletes now carry the envelope's
    // version. V_NEW > V_MID so the in-row LWW gate accepts.
    apply_task_tag_delete(&conn, "task-1:tag-1", V_NEW, "").unwrap();
    assert_eq!(count_task_tags(&conn), 0);
}

// -----------------------------------------------------------------------
// apply_task_dependency_upsert: insert
// -----------------------------------------------------------------------

#[test]
fn task_dependency_upsert_inserts_edge() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_task(&conn, "task-2");

    let payload = task_dependency_payload("2026-01-01T00:00:00Z");
    apply_task_dependency_upsert(&conn, "task-1:task-2", &payload, V_MID, false.into(), "")
        .unwrap();

    assert_eq!(count_task_dependencies(&conn), 1);
}

// -----------------------------------------------------------------------
// apply_task_dependency_delete
// -----------------------------------------------------------------------

#[test]
fn task_dependency_delete_removes_edge() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_task(&conn, "task-2");

    let payload = task_dependency_payload("2026-01-01T00:00:00Z");
    apply_task_dependency_upsert(&conn, "task-1:task-2", &payload, V_MID, false.into(), "")
        .unwrap();
    assert_eq!(count_task_dependencies(&conn), 1);

    apply_task_dependency_delete(&conn, "task-1:task-2", V_NEW, "").unwrap();
    assert_eq!(count_task_dependencies(&conn), 0);
}

/// Regression: after the audit-#2142 deterministic-tiebreak fix,
/// a cycle-closing remote edge with a STRICTLY GREATER HLC than
/// the local conflicting edge deletes the local edge (with a
/// tombstone) and lands the incoming edge. Prior to the fix, the
/// apply layer rejected the incoming and the two devices kept
/// opposite edges forever (silent graph fork). The cluster-
/// deterministic HLC compare guarantees every device reaches the
/// same verdict: newer HLC wins.
#[test]
fn task_dependency_upsert_breaks_cycle_when_incoming_has_higher_hlc() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_task(&conn, "task-2");

    // Local: task-1 → task-2 at V_MID.
    let forward = task_dependency_payload("2026-01-01T00:00:00Z");
    apply_task_dependency_upsert(&conn, "task-1:task-2", &forward, V_MID, false.into(), "")
        .unwrap();
    assert_eq!(count_task_dependencies(&conn), 1);

    // Incoming: task-2 → task-1 at V_NEW. Cycle would close, but
    // the incoming HLC is newer, so it wins: local forward edge
    // is deleted and tombstoned, reverse edge inserted.
    let reverse = task_dependency_payload("2026-01-02T00:00:00Z");
    apply_task_dependency_upsert(&conn, "task-2:task-1", &reverse, V_NEW, false.into(), "")
        .expect("incoming edge with newer HLC must break the cycle");

    let edges: Vec<(String, String)> = conn
        .prepare("SELECT task_id, depends_on_task_id FROM task_dependencies ORDER BY task_id")
        .unwrap()
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(edges, vec![("task-2".to_string(), "task-1".to_string())]);

    // Tombstone must exist for the loser so peers drop it too.
    let tombstone_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ?1 AND entity_id = ?2",
            params!["task_dependency", "task-1:task-2"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        tombstone_count, 1,
        "loser edge must be tombstoned for cluster convergence"
    );
}

/// Companion to the above: when the INCOMING edge has the oldest
/// HLC on the cycle path, the incoming loses. The local state is
/// preserved and the envelope fails with Circular dependency — the
/// caller records the rejection to sync_conflict_log as normal.
#[test]
fn task_dependency_upsert_rejects_incoming_when_its_hlc_is_oldest_on_cycle() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_task(&conn, "task-2");

    // Local: task-1 → task-2 at V_NEW (newer).
    let forward = task_dependency_payload("2026-01-01T00:00:00Z");
    apply_task_dependency_upsert(&conn, "task-1:task-2", &forward, V_NEW, false.into(), "")
        .unwrap();

    // Incoming: task-2 → task-1 at V_OLD (older). Incoming loses.
    let reverse = task_dependency_payload("2026-01-02T00:00:00Z");
    let result =
        apply_task_dependency_upsert(&conn, "task-2:task-1", &reverse, V_OLD, false.into(), "");
    assert!(
        result.is_err(),
        "older incoming edge must lose the tiebreak"
    );

    // Local state preserved: only task-1 → task-2 remains, no
    // tombstone emitted for it.
    assert_eq!(count_task_dependencies(&conn), 1);
    let edges: (String, String) = conn
        .query_row(
            "SELECT task_id, depends_on_task_id FROM task_dependencies",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(edges, ("task-1".to_string(), "task-2".to_string()));
}

/// Transitive cycle (A→B, B→C already present locally, remote emits
/// C→A with a newer HLC). Post-#2142 the oldest edge on the cycle
/// path is evicted and the incoming lands — deterministic
/// convergence across the cluster.
#[test]
fn task_dependency_upsert_breaks_transitive_cycle_by_evicting_oldest() {
    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_task(&conn, "task-2");
    insert_task(&conn, "task-3");

    apply_task_dependency_upsert(
        &conn,
        "task-1:task-2",
        &task_dependency_payload("2026-01-01T00:00:00Z"),
        V_OLD,
        false.into(),
        "",
    )
    .unwrap();
    apply_task_dependency_upsert(
        &conn,
        "task-2:task-3",
        &task_dependency_payload("2026-01-02T00:00:00Z"),
        V_MID,
        false.into(),
        "",
    )
    .unwrap();

    // Incoming task-3 → task-1 at V_NEW would close a transitive
    // cycle. Post-audit-#2142 the apply layer breaks the cycle
    // deterministically by deleting the oldest edge on the path
    // (task-1 → task-2 at V_OLD) and landing the incoming. Every
    // device computes the same verdict, so the graph converges.
    apply_task_dependency_upsert(
        &conn,
        "task-3:task-1",
        &task_dependency_payload("2026-01-03T00:00:00Z"),
        V_NEW,
        false.into(),
        "",
    )
    .expect("newer incoming edge must succeed after the oldest cycle edge is evicted");

    // Net result: 2 edges remain (task-2 → task-3, task-3 → task-1).
    // The originally-oldest edge (task-1 → task-2 at V_OLD) is gone
    // and a tombstone propagates the decision to peers.
    let edges: Vec<(String, String)> = conn
        .prepare(
            "SELECT task_id, depends_on_task_id FROM task_dependencies \
             ORDER BY task_id, depends_on_task_id",
        )
        .unwrap()
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(
        edges,
        vec![
            ("task-2".to_string(), "task-3".to_string()),
            ("task-3".to_string(), "task-1".to_string()),
        ]
    );
    let tombstone_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ?1 AND entity_id = ?2",
            params!["task_dependency", "task-1:task-2"],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(tombstone_count, 1);
}

/// Regression: self-dependency edge from a malformed remote
/// envelope is also rejected at the apply layer (defense in
/// depth — the schema CHECK would catch it later but the apply
/// error is clearer for diagnostics).
#[test]
fn task_dependency_upsert_rejects_self_dependency() {
    let conn = test_db();
    insert_task(&conn, "task-1");

    let result = apply_task_dependency_upsert(
        &conn,
        "task-1:task-1",
        &task_dependency_payload("2026-01-01T00:00:00Z"),
        V_MID,
        false.into(),
        "",
    );
    assert!(result.is_err());
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("Circular dependency"));
}

/// when an existing edge loses the cycle-
/// break tiebreak, the conflict_log row must carry the loser edge's
/// real HLC version and the device suffix that produced it. Pre-fix
/// both fields were written as empty strings, blanking the
/// diagnostics panel.
#[test]
fn cycle_break_logs_loser_hlc_and_device_suffix() {
    // Custom HLCs whose device_suffix is recognizable so the
    // assertion can pin the exact value the conflict_log row must
    // contain.
    const LOCAL_VERSION: &str = "1711234560000_0000_dec01ca1dec01ca1";
    const INCOMING_VERSION: &str = "1711234569999_0000_de007e1ede007e1e";

    let conn = test_db();
    insert_task(&conn, "task-1");
    insert_task(&conn, "task-2");

    // Local edge: task-1 → task-2 at the older HLC. This is the
    // edge that will lose the cycle-break tiebreak.
    let forward = task_dependency_payload("2026-01-01T00:00:00Z");
    apply_task_dependency_upsert(
        &conn,
        "task-1:task-2",
        &forward,
        LOCAL_VERSION,
        false.into(),
        "ts-local",
    )
    .unwrap();

    // Incoming reverse edge with newer HLC closes a cycle and wins
    // the tiebreak. Existing edge gets evicted; conflict_log row
    // captures its identifying metadata.
    let reverse = task_dependency_payload("2026-01-02T00:00:00Z");
    apply_task_dependency_upsert(
        &conn,
        "task-2:task-1",
        &reverse,
        INCOMING_VERSION,
        false.into(),
        "ts-incoming",
    )
    .expect("incoming edge with newer HLC must break the cycle");

    let (entity_id, winner_version, loser_version, loser_device_id, resolved_at): (
        String,
        String,
        String,
        String,
        String,
    ) = conn
        .query_row(
            "SELECT entity_id, winner_version, loser_version, loser_device_id, resolved_at \
             FROM sync_conflict_log \
             WHERE entity_type = ?1 AND resolution_type = ?2",
            params![
                lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
                lorvex_domain::naming::RESOLUTION_CYCLE_BREAK,
            ],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                ))
            },
        )
        .expect("cycle-break must record a conflict_log row");

    assert_eq!(entity_id, "task-1:task-2");
    assert_eq!(winner_version, INCOMING_VERSION);
    assert_eq!(
        loser_version, LOCAL_VERSION,
        "loser_version must be the evicted edge's real HLC, not empty"
    );
    let expected_suffix = lorvex_domain::hlc::Hlc::parse(LOCAL_VERSION)
        .unwrap()
        .device_suffix()
        .to_string();
    assert_eq!(
        loser_device_id, expected_suffix,
        "loser_device_id must derive from the evicted edge's HLC suffix"
    );
    assert_eq!(
        resolved_at, "ts-incoming",
        "resolved_at must propagate the once-per-envelope apply_ts"
    );
}

/// the cycle-break loser election must be a
/// deterministic function of the EDGE SET, not of the insertion
/// order that produced that set. Pre-fix the loser was the HLC-min
/// edge along whichever path the DFS happened to enumerate first
/// — so two devices that arrived at the same logical 3-cycle via
/// different insert orders elected different losers and the
/// cluster forked permanently on cycles of length ≥ 3.
///
/// We exercise the contract by building the same 3-cycle in two
/// different insert orders on two separate connections and
/// asserting that both connections elect the SAME loser when the
/// closing edge fires the cycle-break.
#[test]
fn cycle_break_loser_is_deterministic_across_insert_orders() {
    // Three forward edges that, taken together, form a cycle once
    // the closing edge `t1 → t2` arrives:
    //
    //     t1 → t2 → t3 → t1
    //
    // Each edge carries a recognizable HLC so the loser is
    // unambiguous: the OLDEST forward edge wins the
    // global-MIN(version) competition when the closing edge
    // fires (its incoming version is the newest).
    const V_T2_T3: &str = "1711234561000_0000_aabbccddaabbccdd"; // OLDEST forward edge
    const V_T3_T1: &str = "1711234562000_0000_aabbccddaabbccdd";
    const V_INCOMING_CLOSE: &str = "1711234569999_0000_eeff0011eeff0011";

    // Build the 3-cycle in two different orders. The cycle-break
    // helper runs INSIDE `apply_task_dependency_upsert` only when
    // the insert closes a cycle, so we structure both runs so the
    // FINAL edge closes the cycle. Each iteration plants two
    // forward edges first, then attempts the closing edge — the
    // attempt fires the cycle-break helper and elects a loser.
    fn run_with_closing_edge(
        insert_order: &[(&str, &str, &str)],
        closing_edge: (&str, &str, &str),
    ) -> Vec<(String, String)> {
        let conn = test_db();
        for id in ["t1", "t2", "t3"] {
            insert_task(&conn, id);
        }
        for (from, to, version) in insert_order {
            apply_task_dependency_upsert(
                &conn,
                &format!("{from}:{to}"),
                &task_dependency_payload("2026-01-01T00:00:00Z"),
                version,
                false.into(),
                "ts-seed",
            )
            .expect("seed edge must apply");
        }
        // Closing edge — fires the cycle-break helper.
        let _ = apply_task_dependency_upsert(
            &conn,
            &format!("{}:{}", closing_edge.0, closing_edge.1),
            &task_dependency_payload("2026-01-02T00:00:00Z"),
            closing_edge.2,
            false.into(),
            "ts-incoming",
        );
        let edges: Vec<(String, String)> = conn
            .prepare(
                "SELECT task_id, depends_on_task_id FROM task_dependencies \
                 ORDER BY task_id, depends_on_task_id",
            )
            .unwrap()
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();
        edges
    }

    // Order A: insert t2→t3 (oldest) first, then t3→t1, then close
    // with t1→t2 (newest).
    let edges_a = run_with_closing_edge(
        &[("t2", "t3", V_T2_T3), ("t3", "t1", V_T3_T1)],
        ("t1", "t2", V_INCOMING_CLOSE),
    );

    // Order B: same edges, inserted in the OPPOSITE order. The
    // closing edge is identical so the cycle-break helper sees
    // the same edge SET — only the insertion history differs.
    let edges_b = run_with_closing_edge(
        &[("t3", "t1", V_T3_T1), ("t2", "t3", V_T2_T3)],
        ("t1", "t2", V_INCOMING_CLOSE),
    );

    // The deterministic loser is the global-MIN(version) edge in
    // the SCC, which is `t2 → t3` (V_T2_T3, oldest). Both runs
    // therefore retain the same surviving edge set. Pre-fix the
    // DFS-path-dependent loser election could surface different
    // edges in `edges_a` vs `edges_b`.
    assert_eq!(
        edges_a, edges_b,
        "issue #2973-H8: cycle-break loser must be deterministic across insert orders \
         (order A surviving edges: {edges_a:?}, order B: {edges_b:?})"
    );

    // Sanity: the surviving set should NOT contain `t2 → t3`
    // (the elected loser).
    assert!(
        !edges_a.contains(&("t2".to_string(), "t3".to_string())),
        "global-MIN(version) edge t2→t3 must be the elected loser; \
         got surviving set {edges_a:?}"
    );
}
