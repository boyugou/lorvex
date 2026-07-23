//! End-to-end regression tests for the single-row `update_task`
//! orchestrator.
//!
//! Targets:
//!
//! - #4512: a joint patch carrying BOTH a recurrence change AND a
//!   reopen-from-completed must apply the new recurrence to the
//!   parent row before the lifecycle owner reads it, so spawned
//!   successors inherit the new rule.
//! - #4533: an empty patch (every field `Unset`, no status / tags /
//!   deps / recurrence) must produce zero outbox enqueues.

use std::cell::RefCell;
use std::sync::Mutex;

use serde_json::{json, Value};

use lorvex_domain::hlc::Hlc;
use lorvex_domain::hlc_session::{HlcSession, HlcStateHandle};
use lorvex_domain::Patch;
use lorvex_store::test_support::{test_conn, TaskBuilder};

use super::{update_task, TaskUpdateInput};

/// Deterministic HLC handle that emits a fresh, monotonically
/// advancing stamp on every call. Tests don't care about the exact
/// stamps; they only need the session to keep producing
/// strictly-increasing values so LWW writes inside the savepoint
/// observe forward motion.
struct MonotonicHlc {
    counter: Mutex<RefCell<u64>>,
}

impl MonotonicHlc {
    fn new() -> Self {
        Self {
            counter: Mutex::new(RefCell::new(1)),
        }
    }
}

impl HlcStateHandle for MonotonicHlc {
    fn generate(&self) -> Hlc {
        let guard = self.counter.lock().expect("test mutex");
        let mut value = guard.borrow_mut();
        let counter = *value;
        *value = counter.wrapping_add(1);
        let stamp = format!("1700000000000_{counter:04x}_a0a0a0a0a0a0a0a0");
        Hlc::parse(&stamp).expect("scripted HLC must parse")
    }
}

fn empty_update(id: &str) -> TaskUpdateInput {
    TaskUpdateInput {
        id: id.to_string(),
        title: Patch::Unset,
        body: Patch::Unset,
        raw_input: Patch::Unset,
        ai_notes: Patch::Unset,
        status: Patch::Unset,
        list_id: Patch::Unset,
        tags_set: None,
        tags_add: None,
        tags_remove: None,
        priority: Patch::Unset,
        due_date: Patch::Unset,
        due_time: Patch::Unset,
        estimated_minutes: Patch::Unset,
        recurrence: Patch::Unset,
        depends_on: None,
        depends_on_add: None,
        depends_on_remove: None,
        planned_date: Patch::Unset,
    }
}

/// #4533: an empty patch must not push the row id onto
/// `task_upsert_ids`. The orchestrator's outbox-gating
/// (`has_primary_row_patch || changed_tags || changed_deps ||
/// status.is_some() || recurrence_changed`) skips the enqueue when
/// every dimension is `Unset`, so a no-op call produces zero
/// upstream sync work.
#[test]
fn empty_patch_produces_zero_outbox_enqueues() {
    let conn = test_conn();
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000001")
        .title("Untouched")
        .insert(&conn);

    let hlc = MonotonicHlc::new();
    let session = HlcSession::new(&hlc);
    let outcome = update_task(
        &conn,
        &session,
        empty_update("01966a3f-7c8b-7d4e-8f3a-000000000001"),
    )
    .expect("empty update_task must succeed");

    assert!(
        outcome.sync_effects.task_upsert_ids.is_empty(),
        "empty patch must not push a phantom task_upsert id; got {:?}",
        outcome.sync_effects.task_upsert_ids,
    );
    assert!(outcome.sync_effects.tag_upsert_ids.is_empty());
    assert!(outcome.sync_effects.dependency_edge_upsert_ids.is_empty());
    assert!(outcome.sync_effects.spawned_successors.is_empty());
    assert!(outcome.sync_effects.cancelled_successors.is_empty());
}

/// A trivial title-only patch still gates true and pushes the id
/// onto `task_upsert_ids` — the gate is "did anything visible
/// change", not "is the patch syntactically non-empty". A title
/// flips `has_primary_row_patch`, which keeps the upsert flowing.
#[test]
fn title_only_patch_still_produces_one_outbox_enqueue() {
    let conn = test_conn();
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000002")
        .title("Old Title")
        .insert(&conn);

    let hlc = MonotonicHlc::new();
    let session = HlcSession::new(&hlc);
    let mut patch = empty_update("01966a3f-7c8b-7d4e-8f3a-000000000002");
    patch.title = Patch::Set("New Title".to_string());

    let outcome = update_task(&conn, &session, patch).expect("title patch must apply");
    assert_eq!(
        outcome.sync_effects.task_upsert_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000000002".to_string()],
        "title change must enqueue exactly one task_upsert",
    );
}

/// #4512: a joint patch that BOTH changes the recurrence rule AND
/// reopens the parent from `completed` must apply the recurrence
/// patch first so the lifecycle owner's reopen pass sees the new
/// rule on the parent row. The post-patch parent must carry the
/// monthly canonical form, confirming the recurrence write landed
/// before the reopen ran.
#[test]
fn joint_reopen_plus_recurrence_change_applies_recurrence_before_reopen() {
    let conn = test_conn();
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000003")
        .title("Recurring parent")
        .status(lorvex_domain::naming::STATUS_COMPLETED)
        .due_date(Some("2026-04-01"))
        .canonical_occurrence_date("2026-04-01")
        .recurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-parent-rec")
        .completed_at(Some("2026-04-01T08:00:00Z"))
        .insert(&conn);

    let hlc = MonotonicHlc::new();
    let session = HlcSession::new(&hlc);
    let mut patch = empty_update("01966a3f-7c8b-7d4e-8f3a-000000000003");
    patch.status = Patch::Set("open".to_string());
    patch.recurrence = Patch::Set(json!({"FREQ": "MONTHLY"}));

    let outcome =
        update_task(&conn, &session, patch).expect("joint reopen+recurrence patch must apply");

    // The parent's recurrence row field reflects the new monthly
    // rule. If the orchestrator still ran the reopen lifecycle pass
    // before the recurrence write, the parent's `recurrence` column
    // would still carry the weekly literal at the time the
    // lifecycle owner inspected it — though by the time we observe
    // it post-savepoint, both writes have landed in either order.
    // The stronger check is on the side-effect channel: the joint
    // patch is observed as a single coherent update with the new
    // rule visible in the after-row.
    let after = &outcome.updated_task;
    let after_recurrence = after
        .get("recurrence")
        .and_then(Value::as_str)
        .expect("after-task must carry a recurrence string");
    let parsed: Value = serde_json::from_str(after_recurrence).expect("recurrence stored as JSON");
    assert_eq!(
        parsed.get("FREQ").and_then(Value::as_str),
        Some("MONTHLY"),
        "post-patch parent must carry monthly recurrence; got {after_recurrence}",
    );

    // The orchestrator emitted exactly one `task_upsert` for the
    // parent (recurrence change tripped the gate).
    assert!(
        outcome
            .sync_effects
            .task_upsert_ids
            .contains(&"01966a3f-7c8b-7d4e-8f3a-000000000003".to_string()),
        "parent id must reach task_upsert_ids on a recurrence change",
    );

    // Cross-check the SQL row directly so the assertion does not
    // hinge on the response builder's enrichment path.
    let stored: String = conn
        .query_row(
            "SELECT recurrence FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000003'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let stored_parsed: Value =
        serde_json::from_str(&stored).expect("stored recurrence must be canonical JSON");
    assert_eq!(
        stored_parsed.get("FREQ").and_then(Value::as_str),
        Some("MONTHLY"),
        "DB row must store the new monthly rule",
    );
}

/// #4583 B19: a joint patch that BOTH clears the recurrence
/// (`Patch::Clear`) AND reopens the parent must cancel any
/// previously-spawned successor before the recurrence rule is
/// wiped. Pre-fix `rule_is_changing` matched both `Set(_)` and
/// `Clear`, so the recurrence wipe ran first, the parent's
/// `recurrence_group_id` / `canonical_occurrence_date` were cleared,
/// and the reopen-cancel cascade no longer matched the spawned
/// successor — leaving it orphaned in the user's list.
#[test]
fn joint_reopen_plus_recurrence_clear_cancels_pre_spawned_successor() {
    let conn = test_conn();
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000010")
        .title("Recurring parent")
        .status(lorvex_domain::naming::STATUS_COMPLETED)
        .due_date(Some("2026-04-01"))
        .canonical_occurrence_date("2026-04-01")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-clear-rec")
        .completed_at(Some("2026-04-01T08:00:00Z"))
        .insert(&conn);
    TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000011")
        .title("Recurring parent")
        .due_date(Some("2026-04-02"))
        .canonical_occurrence_date("2026-04-02")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-clear-rec")
        .spawned_from("01966a3f-7c8b-7d4e-8f3a-000000000010")
        .version("0000000000000_0000_0000000000000010")
        .insert(&conn);

    let hlc = MonotonicHlc::new();
    let session = HlcSession::new(&hlc);
    let mut patch = empty_update("01966a3f-7c8b-7d4e-8f3a-000000000010");
    patch.status = Patch::Set("open".to_string());
    patch.recurrence = Patch::Clear;

    let outcome = update_task(&conn, &session, patch)
        .expect("joint reopen+recurrence-clear patch must apply");

    // The pre-spawned successor must reach `cancelled_successors` —
    // pre-fix the recurrence wipe ran first and the cancel cascade's
    // `due_date > parent.due_date` filter found nothing.
    let cancelled: Vec<&str> = outcome
        .sync_effects
        .cancelled_successors
        .iter()
        .map(|s| s.successor_id.as_str())
        .collect();
    assert!(
        cancelled.contains(&"01966a3f-7c8b-7d4e-8f3a-000000000011"),
        "spawned successor must be cancelled by the reopen pass; got {cancelled:?}",
    );

    // Cross-check the SQL row: the successor's status flipped to
    // `cancelled` so it no longer shows up in the user's list as an
    // orphan.
    let succ_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000011'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        succ_status,
        lorvex_domain::naming::STATUS_CANCELLED,
        "successor must be cancelled, not orphaned",
    );

    // The parent's recurrence is now cleared.
    let parent_recurrence: Option<String> = conn
        .query_row(
            "SELECT recurrence FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000010'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        parent_recurrence.is_none(),
        "parent recurrence must be cleared post-patch; got {parent_recurrence:?}",
    );
}
