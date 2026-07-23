use super::simple_pk::simple_pk_supported;
use super::{stamp_entity_version, VersionStampError};
use crate::test_db;
use lorvex_domain::naming::{EDGE_TASK_TAG, ENTITY_AI_CHANGELOG, ENTITY_TASK};
use lorvex_store::test_support::fixtures::TaskBuilder;

#[test]
fn covers_all_simple_pk_entity_types() {
    let simple_types = [
        "task",
        "list",
        "habit",
        "tag",
        "calendar_event",
        "task_reminder",
        "habit_reminder_policy",
        "preference",
        "memory",
        "memory_revision",
        "daily_review",
        "current_focus",
        "focus_schedule",
        "calendar_subscription",
    ];
    for et in &simple_types {
        assert!(
            simple_pk_supported(et),
            "simple_pk_sql should return Some for {et}"
        );
    }
}

#[test]
fn returns_none_for_composite_pk_types() {
    let composite_types = [
        "task_calendar_event_link",
        "habit_completion",
        "task_tag",
        "task_dependency",
    ];
    for et in &composite_types {
        assert!(
            !simple_pk_supported(et),
            "simple_pk_sql should return None for composite type {et}"
        );
    }
}

/// also cover the missing `task_checklist_item`
/// simple-PK entity that was added to `entity_type_to_table_pk`
/// but missing from this coverage list before the rewrite.
#[test]
fn task_checklist_item_is_covered_in_simple_pk_dispatch() {
    assert!(simple_pk_supported("task_checklist_item"));
}

#[test]
fn stamp_entity_version_allows_known_no_version_entities() {
    let conn = test_db();

    stamp_entity_version(&conn, ENTITY_AI_CHANGELOG, "chg-1", "v1")
        .expect("ai changelog should be exempt from version stamping");
}

#[test]
fn stamp_entity_version_rejects_malformed_composite_entity_ids() {
    let conn = test_db();

    let error = stamp_entity_version(&conn, EDGE_TASK_TAG, "not-a-composite-id", "v1")
        .expect_err("malformed composite ids should fail");

    assert!(
        error.to_string().contains("invalid composite entity id"),
        "unexpected error: {error}"
    );
}

#[test]
fn stamp_entity_version_returns_entity_not_found_for_missing_simple_pk_row() {
    let conn = test_db();
    let error = stamp_entity_version(&conn, ENTITY_TASK, "no-such-task", "v1")
        .expect_err("missing row should surface as EntityNotFound");
    match error {
        VersionStampError::EntityNotFound {
            entity_type,
            entity_id,
        } => {
            assert_eq!(entity_type, "task");
            assert_eq!(entity_id, "no-such-task");
        }
        other => panic!("expected EntityNotFound, got {other:?}"),
    }
}

#[test]
fn stamp_entity_version_returns_entity_not_found_for_missing_composite_edge() {
    let conn = test_db();
    let error = stamp_entity_version(&conn, EDGE_TASK_TAG, "task-missing:tag-missing", "v1")
        .expect_err("missing edge row should surface as EntityNotFound");
    match error {
        VersionStampError::EntityNotFound { entity_type, .. } => {
            assert_eq!(entity_type, "task_tag");
        }
        other => panic!("expected EntityNotFound, got {other:?}"),
    }
}

/// the new LWW guard must NOT regress tasks.version
/// when a stale stamp attempt races behind a newer concurrent
/// writer. Scenario: row currently at v2; caller tries to stamp
/// v1 (older). The UPDATE must be a no-op.
///
/// tightened to also assert the typed
/// `Superseded` variant. The pre-fix shape silently returned
/// `Ok(())` and the caller proceeded to enqueue an envelope at
/// the now-stale `v1`, producing an outbox row whose HLC didn't
/// match the row state.
///
/// fixture upgraded from `'v1'`/`'v2'` literals
/// to canonical 13-digit-physical-ms HLCs. The new
/// corruption-tolerance branch only surfaces `Superseded` when
/// BOTH sides parse as HLCs; the legacy alphabetic literals
/// would silently fall through to `Ok(())` instead of triggering
/// the regression guard the test exists to verify.
#[test]
fn stamp_entity_version_does_not_regress_newer_version() {
    let conn = test_db();
    let newer = "1711234567200_0000_dec0000200000002";
    let older = "1711234567000_0000_dec0000100000001";
    TaskBuilder::new("t-regress")
        .title("T")
        .version(newer)
        .created_at("2026-03-01T00:00:00Z")
        .insert(&conn);

    // Stale stamp attempt — must NOT regress tasks.version, and
    // must surface as a typed Superseded error.
    let err = stamp_entity_version(&conn, ENTITY_TASK, "t-regress", older)
        .expect_err("stale stamp must surface as Superseded");
    match err {
        VersionStampError::Superseded {
            entity_type,
            entity_id,
            existing_version,
        } => {
            assert_eq!(entity_type, ENTITY_TASK);
            assert_eq!(entity_id, "t-regress");
            assert_eq!(existing_version, newer);
        }
        other => panic!("expected Superseded, got {other:?}"),
    }

    let observed: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id='t-regress'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        observed, newer,
        "stamp guard must not regress tasks.version"
    );
}

/// when the row's existing version is a stale-
/// shape literal (`'v1'`, `'test_ver'`, etc.) that doesn't parse
/// as an HLC, the stamp call must NOT return `Superseded` based
/// on a raw string lex-compare (which can have perverse outcomes
/// — `'v1' > '1711234567000_...'` is TRUE because `'v'` > `'1'`).
/// Instead, the corruption-tolerance branch falls through to
/// `Ok(())` so legacy/test rows don't block real writes.
#[test]
fn stamp_entity_version_surfaces_superseded_for_unparseable_existing_that_beats_stamp_bytewise() {
    let conn = test_db();
    TaskBuilder::new("t-corrupt")
        .title("T")
        .version("v1")
        .created_at("2026-03-01T00:00:00Z")
        .insert(&conn);
    // The stamp value is a canonical HLC; the row's existing
    // version is `'v1'` (legacy / hand-edited / fixture residue).
    // SQL byte-compare puts `'v1' > '1711...'` because ASCII
    // letters sort above digits, so the UPDATE predicate
    // `?1 > version` refuses. Pre-fix audit-sync M16 the function
    // silently returned Ok() here — but the row's `version`
    // column stayed tainted while the caller's outbox enqueue
    // shipped an envelope at the canonical stamp version,
    // producing the "outbox row HLC disagrees with row.version"
    // drift the typed `Superseded` error was added to prevent.
    // Surface Superseded so the caller sees the gate refusal and
    // the tainted row is visible to operators rather than papered
    // over.
    let err = stamp_entity_version(
        &conn,
        ENTITY_TASK,
        "t-corrupt",
        "1711234567000_0000_dec0000100000001",
    )
    .expect_err("tainted local row that beats stamp byte-wise must surface Superseded");
    match err {
        VersionStampError::Superseded {
            existing_version, ..
        } => assert_eq!(existing_version, "v1"),
        other => panic!("expected Superseded, got {other:?}"),
    }
}

/// the typed `Superseded` variant must
/// also surface for composite-PK edge tables. Without this branch,
/// concurrent edge writers (task_tags, task_dependencies, etc.)
/// would silently drop their outbox row at a stale version.
#[test]
fn stamp_entity_version_returns_superseded_for_composite_edge() {
    let conn = test_db();
    // canonical HLC fixtures so the
    // corruption-tolerance branch doesn't swallow the
    // Superseded signal this test exists to verify. The
    // parent task/tag rows can use any HLC (they're not
    // compared against the stamp); only `task_tags.version`
    // matters for the Superseded check.
    let parent_v = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    let edge_newer = "1711234567300_0000_dec0000300000003";
    let stale_stamp = "1711234567200_0000_dec0000200000002";
    TaskBuilder::new("t-edge")
        .title("T")
        .version(parent_v)
        .created_at("2026-03-01T00:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
         VALUES ('tag-edge', 'X', 'x', ?1, '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
        [parent_v],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version) \
         VALUES ('t-edge', 'tag-edge', '2026-03-01T00:00:00Z', ?1)",
        [edge_newer],
    )
    .unwrap();

    let err = stamp_entity_version(&conn, EDGE_TASK_TAG, "t-edge:tag-edge", stale_stamp)
        .expect_err("stale composite stamp must surface as Superseded");
    match err {
        VersionStampError::Superseded {
            entity_type,
            entity_id,
            existing_version,
        } => {
            assert_eq!(entity_type, EDGE_TASK_TAG);
            assert_eq!(entity_id, "t-edge:tag-edge");
            assert_eq!(existing_version, edge_newer);
        }
        other => panic!("expected Superseded, got {other:?}"),
    }
}

/// Forward stamp (newer version) must still succeed and the row
/// must reflect the new version.
#[test]
fn stamp_entity_version_updates_when_new_version_is_strictly_greater() {
    let conn = test_db();
    TaskBuilder::new("t-forward")
        .title("T")
        .version("v1")
        .created_at("2026-03-01T00:00:00Z")
        .insert(&conn);

    stamp_entity_version(&conn, ENTITY_TASK, "t-forward", "v2").expect("forward stamp works");

    let observed: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id='t-forward'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(observed, "v2");
}
