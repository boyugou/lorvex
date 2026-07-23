use super::*;
use lorvex_store::open_db_in_memory;
use lorvex_store::test_support::TaskBuilder;

const TEST_VERSION: &str = "v-test";
const TEST_TS: &str = "2026-04-04T00:00:00Z";

fn seed_minimal_task(conn: &rusqlite::Connection, id: &str) {
    TaskBuilder::new(id)
        .title("Test")
        .version(TEST_VERSION)
        .created_at(TEST_TS)
        .insert(conn);
}

fn parse(d: &str) -> Option<chrono::NaiveDate> {
    Some(lorvex_domain::time::parse_iso_date(d).unwrap())
}

#[test]
fn compute_enrichments_empty_input_is_noop() {
    let conn = open_db_in_memory().unwrap();
    let map = compute_enrichments(&conn, &[], "2026-04-04").unwrap();
    assert!(map.is_empty());
}

#[test]
fn compute_enrichments_lateness_past_planned() {
    let conn = open_db_in_memory().unwrap();
    seed_minimal_task(&conn, "t1");
    let dates = [("t1", parse("2026-04-01"), None)];
    let map = compute_enrichments(&conn, &dates, "2026-04-04").unwrap();
    assert_eq!(
        map.get("t1").and_then(|e| e.lateness),
        Some(lorvex_domain::TaskLateness::PastPlanned)
    );
}

#[test]
fn compute_enrichments_lateness_no_dates_omits_entry() {
    let conn = open_db_in_memory().unwrap();
    seed_minimal_task(&conn, "t1");
    let dates = [("t1", None, None)];
    let map = compute_enrichments(&conn, &dates, "2026-04-04").unwrap();
    assert!(map.get("t1").and_then(|e| e.lateness).is_none());
}

#[test]
fn compute_enrichments_invalid_today_is_validation_error() {
    let conn = open_db_in_memory().unwrap();
    seed_minimal_task(&conn, "t1");
    let dates = [("t1", None, None)];
    let err = compute_enrichments(&conn, &dates, "bad-date").unwrap_err();
    match err {
        StoreError::Validation(msg) => assert!(msg.contains("invalid today date")),
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn compute_enrichments_no_tags_returns_no_entry() {
    let conn = open_db_in_memory().unwrap();
    seed_minimal_task(&conn, "t1");
    let dates = [("t1", None, None)];
    let map = compute_enrichments(&conn, &dates, "2026-04-04").unwrap();
    assert!(map.get("t1").and_then(|e| e.tags.clone()).is_none());
}

#[test]
fn compute_enrichments_tags_returns_display_names() {
    let conn = open_db_in_memory().unwrap();
    seed_minimal_task(&conn, "t1");
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
        rusqlite::params!["tag1", "Work", "work", TEST_VERSION, TEST_TS],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at) \
         VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params!["t1", "tag1", TEST_VERSION, TEST_TS],
    )
    .unwrap();

    let dates = [("t1", None, None)];
    let map = compute_enrichments(&conn, &dates, "2026-04-04").unwrap();
    assert_eq!(
        map.get("t1").unwrap().tags.as_deref(),
        Some(&["Work".to_string()][..])
    );
}

#[test]
fn compute_enrichments_depends_on_returns_dependency_ids() {
    let conn = open_db_in_memory().unwrap();
    seed_minimal_task(&conn, "t1");
    TaskBuilder::new("t2")
        .title("Dependency")
        .version(TEST_VERSION)
        .created_at(TEST_TS)
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) \
         VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params!["t1", "t2", TEST_VERSION, TEST_TS],
    )
    .unwrap();

    let dates = [("t1", None, None)];
    let map = compute_enrichments(&conn, &dates, "2026-04-04").unwrap();
    assert_eq!(
        map.get("t1").unwrap().depends_on.as_deref(),
        Some(&["t2".to_string()][..])
    );
}

#[test]
fn compute_enrichments_checklist_items_returns_ordered_items() {
    let conn = open_db_in_memory().unwrap();
    seed_minimal_task(&conn, "t1");
    conn.execute(
        "INSERT INTO task_checklist_items (id, task_id, position, text, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
        rusqlite::params!["ci1", "t1", 0, "First item", TEST_VERSION, TEST_TS],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_checklist_items (id, task_id, position, text, version, created_at, updated_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
        rusqlite::params!["ci2", "t1", 1, "Second item", TEST_VERSION, TEST_TS],
    )
    .unwrap();

    let dates = [("t1", None, None)];
    let map = compute_enrichments(&conn, &dates, "2026-04-04").unwrap();
    let items = map.get("t1").unwrap().checklist_items.as_ref().unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(items[0].text, "First item");
    assert_eq!(items[1].text, "Second item");
}
