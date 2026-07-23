//! Regression coverage for issues #2827 and #2830.
//!
//! - #2827: 01966a3f-7c8b-7d4e-8f3a-000000002137 tombstone permanently blocks single-list re-upsert.
//!   Pre-fix `apply_list_delete` returned `Ok(false)` when the at-least-
//!   one-list invariant fired, but `apply_envelope` still wrote a
//!   tombstone at the envelope's HLC over a still-live row. Any future
//!   re-upsert of the same id from a peer at a lower HLC was silently
//!   rejected by the tombstone-vs-upsert gate. Post-fix the dispatcher
//!   surfaces `EntityApplyOutcome::DeleteSkippedByInvariant`,
//!   `apply_envelope` returns a typed deferral instead of writing the
//!   tombstone, and the caller parks the envelope in `sync_pending_inbox`
//!   for a later drain retry.
//!
//! - #2830: `promote_payload_shadows` lacked FK preflight + redirect
//!   chase. The redirect chase + FK preflight + per-row SAVEPOINT
//!   landed under #2964-M4 and #2917-L2; the remaining gap was that
//!   FK-missing shadows silently stayed in place and were invisible
//!   to the diagnostics surface. Post-fix the synthetic envelope is
//!   enqueued into `sync_pending_inbox` so the FK-arrival drain can
//!   replay it as soon as the parent lands.

use super::*;
use crate::pending_inbox::get_all_pending;

// ──────────────────────────────────────────────────────────────────
// #2827: 01966a3f-7c8b-7d4e-8f3a-000000002137 invariant skip no longer writes a tombstone
// ──────────────────────────────────────────────────────────────────

/// When the at-least-one-list invariant fires (`total_lists <= 1`):
///   - the SQL DELETE is suppressed (row stays alive), and
///   - NO tombstone is recorded for the list, and
///   - the delete envelope returns a typed deferral so a future drain
///     (after another list arrives) can retry it.
#[test]
fn list_delete_invariant_skip_does_not_write_tombstone_and_defers_to_inbox() {
    let conn = test_db();
    let list_id = "inbox";

    // The schema seeds the well-known `inbox` list as the only row
    // in `lists`, so a delete envelope targeting it is guaranteed to
    // hit the at-least-one-list invariant.
    let total_lists: i64 = conn
        .query_row("SELECT COUNT(*) FROM lists", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        total_lists, 1,
        "fixture must have exactly one list to trigger the invariant"
    );

    // Fire a delete envelope at a strictly newer HLC.
    let env = make_delete_envelope(naming::ENTITY_LIST, list_id, LWW_V_NEW);
    let result = apply_envelope(&conn, &env).unwrap();

    // The result is Deferred with the new typed reason.
    match result {
        ApplyResult::Deferred {
            reason:
                DeferralReason::AggregateInvariantBlocked {
                    ref entity_type,
                    ref entity_id,
                    invariant,
                },
        } => {
            assert_eq!(*entity_type, naming::EntityKind::List);
            assert_eq!(entity_id, list_id);
            assert_eq!(invariant, "at_least_one_list");
        }
        other => panic!("expected AggregateInvariantBlocked deferral, got {other:?}"),
    }

    // The row is still alive (invariant preserved).
    let still_alive: i64 = conn
        .query_row("SELECT COUNT(*) FROM lists WHERE id = ?1", [list_id], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(still_alive, 1, "list row must remain after invariant skip");

    // CRUCIAL #2827: NO tombstone was written. Pre-fix the tombstone
    // sat at the envelope's HLC over the still-live row and blocked
    // every future re-upsert.
    assert!(
        !crate::tombstone::is_tombstoned(&conn, naming::ENTITY_LIST, list_id).unwrap(),
        "#2827: invariant-blocked delete must NOT mint a tombstone"
    );

    // `apply_envelope` owns apply semantics only; callers own durable
    // pending-inbox storage for every `ApplyResult::Deferred` variant.
    // This keeps invariant-blocked deletes consistent with
    // `SchemaTooNew` and `MissingDependency` and avoids duplicate retry
    // increments when a pending row is replayed through the drain.
    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(
        pending.len(),
        0,
        "apply_envelope must not enqueue deferred envelopes itself"
    );
}

/// Once another list arrives, a peer-authored upsert at a LOWER HLC
/// than the suppressed delete envelope must still land. Pre-fix the
/// tombstone (written at the delete's HLC) silently rejected this
/// upsert via the tombstone-vs-upsert gate, even though the receiving
/// device still had the row alive locally.
#[test]
fn peer_upsert_lands_on_single_list_after_invariant_skip() {
    let conn = test_db();
    // The schema seeds `inbox` as the sole list, which triggers the
    // at-least-one-list invariant on the first delete attempt.
    let list_id = "inbox";

    // Peer A authors a delete at NEW HLC (peer A locally had >1 lists).
    let delete_env = make_delete_envelope(naming::ENTITY_LIST, list_id, LWW_V_NEW);
    let result = apply_envelope(&conn, &delete_env).unwrap();
    assert!(
        matches!(result, ApplyResult::Deferred { .. }),
        "delete must be deferred under invariant"
    );

    // Peer B (concurrent edit) authors an upsert at OLD HLC (lower
    // than the delete's HLC). Pre-fix the tombstone-vs-upsert gate
    // would silently reject this upsert; post-fix there is no
    // tombstone, the LWW gate compares against the live row's
    // OLD-versioned state, and the upsert with a fresh peer HLC
    // (here we use a strictly-NEW one to mirror real concurrent
    // edits) lands.
    let edit_version = "1711234565000_0000_b1b2b3b4b1b2b3b4";
    let upsert_env = SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::List,
        entity_id: list_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(edit_version).expect("test fixture version must be a canonical HLC"),
        payload_schema_version: PAYLOAD_SCHEMA_VERSION,
        payload: r#"{"name":"renamed by peer B","created_at":"2026-04-20T00:00:00.000Z","updated_at":"2026-04-20T00:01:00.000Z"}"#.to_string(),
        device_id: "peer-b".to_string(),
    };
    let upsert_result = apply_envelope(&conn, &upsert_env).unwrap();
    assert_eq!(
        upsert_result,
        ApplyResult::Applied,
        "peer upsert must land — there is no tombstone to block it"
    );
    let renamed: String = conn
        .query_row("SELECT name FROM lists WHERE id = ?1", [list_id], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(renamed, "renamed by peer B");
}

/// Issue #3313 supersedes the original #2827 behavior here: the
/// schema's `trg_lists_before_delete` trigger re-homes referencing
/// tasks (active OR archived) to `inbox` before the DELETE, so a
/// non-inbox 01966a3f-7c8b-7d4e-8f3a-000000002137 with referencing tasks now applies cleanly,
/// rather than being deferred + quarantined. Tombstone is still
/// minted by the caller as part of the normal applied path.
#[test]
fn list_delete_with_referencing_tasks_applies_via_rehome_trigger() {
    let conn = test_db();
    let list_id = "01966a3f-7c8b-7d4e-8f3a-00000000212d";

    // Need >1 lists so we don't trip the at-least-one-list invariant
    // first. The schema seeds `inbox`; add a target list and pin a
    // task to it.
    lorvex_store::test_support::ListBuilder::new(list_id)
        .name("target")
        .version(LWW_V_OLD)
        .created_at("2026-04-20T00:00:00.000Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at) \
         VALUES ('t-pinned', 't', 'open', ?1, ?2, '2026-04-20T00:00:00.000Z', '2026-04-20T00:00:00.000Z')",
        rusqlite::params![list_id, LWW_V_OLD],
    )
    .unwrap();

    let env = make_delete_envelope(naming::ENTITY_LIST, list_id, LWW_V_NEW);
    let result = apply_envelope(&conn, &env).unwrap();
    assert!(
        matches!(result, ApplyResult::Applied),
        "delete must apply now that the trigger re-homes referencing tasks; got {result:?}"
    );

    // List row gone; task survives, re-homed to inbox.
    let gone: i64 = conn
        .query_row("SELECT COUNT(*) FROM lists WHERE id = ?1", [list_id], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(gone, 0, "list row must be deleted");

    let rehomed: String = conn
        .query_row("SELECT list_id FROM tasks WHERE id = 't-pinned'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(rehomed, "inbox", "task must be re-homed to inbox");

    // No fk_stalled conflict — non-inbox delete is a clean apply.
    let fk_stalled: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_conflict_log \
             WHERE entity_type = ?1 AND entity_id = ?2 AND resolution_type = ?3",
            rusqlite::params![naming::ENTITY_LIST, list_id, naming::RESOLUTION_FK_STALLED],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(fk_stalled, 0);

    // Nothing pending — applied envelopes don't enqueue.
    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(pending.len(), 0);
}

// ──────────────────────────────────────────────────────────────────
// #2830: shadow promotion FK miss enqueues into pending_inbox
// ──────────────────────────────────────────────────────────────────

/// A shadow row whose FK target is not yet present locally must
/// enqueue a synthesized envelope into `sync_pending_inbox` with the
/// missing-dependency identity preserved. Pre-fix the FK miss left
/// the shadow alone and was invisible to the FK-arrival drain.
#[test]
fn shadow_promotion_fk_miss_enqueues_pending_inbox() {
    let conn = test_db();

    // Seed a payload shadow for a `task_reminder` whose parent
    // `task_id` does NOT exist locally. The shadow's payload supplies
    // the FK target name; preflight will fail on the missing parent.
    let reminder_id = "01966a3f-7c8b-7d4e-8f3a-00000000214e";
    let parent_task_id = "01966a3f-7c8b-7d4e-8f3a-00000000218c";
    let shadow_version = "1711234560000_0000_dec0009900000099";
    conn.execute(
        "INSERT INTO sync_payload_shadow (entity_type, entity_id, base_version,
                                          payload_schema_version, raw_payload_json,
                                          source_device_id, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            naming::ENTITY_TASK_REMINDER,
            reminder_id,
            shadow_version,
            lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            format!(
                r#"{{"task_id":"{parent_task_id}","reminder_at":"2026-05-01T09:00:00.000Z","created_at":"2026-04-20T00:00:00.000Z","updated_at":"2026-04-20T00:00:00.000Z"}}"#,
            ),
            "remote-device",
            "2026-04-20T00:00:00.000Z",
        ],
    )
    .unwrap();

    let promoted = promote_payload_shadows(&conn).unwrap();
    assert_eq!(
        promoted, 0,
        "promotion must be a no-op while the FK target is missing"
    );

    // The synthesized envelope is now in the pending inbox keyed by
    // the missing parent identity.
    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(
        pending.len(),
        1,
        "FK miss must enqueue exactly one pending row"
    );
    let entry = &pending[0];
    assert_eq!(
        entry.missing_entity_type.as_deref(),
        Some(naming::ENTITY_TASK),
        "the missing dep is the task parent"
    );
    assert_eq!(
        entry.missing_entity_id.as_deref(),
        Some(parent_task_id),
        "the missing dep id matches the shadow payload's task_id"
    );

    // The shadow is still in place — the durable forward-compat copy
    // survives until the eventual replay clears it via
    // `finalize_payload_shadow`.
    let shadow_after = lorvex_sync_payload::payload_shadow::get_shadow(
        &conn,
        naming::ENTITY_TASK_REMINDER,
        reminder_id,
    )
    .unwrap();
    assert!(
        shadow_after.is_some(),
        "shadow must persist alongside the pending inbox row"
    );
}

/// A repeated promote pass while the FK target is still missing must
/// be idempotent — no second pending_inbox row is created (the
/// `enqueue_pending` UPSERT keys on
/// `(entity_type, entity_id, version)` per H1).
#[test]
fn shadow_promotion_fk_miss_does_not_flood_pending_inbox() {
    let conn = test_db();
    let reminder_id = "01966a3f-7c8b-7d4e-8f3a-00000000214f";
    let parent_task_id = "01966a3f-7c8b-7d4e-8f3a-000000002170";
    let shadow_version = "1711234560000_0000_dec0009900000099";

    conn.execute(
        "INSERT INTO sync_payload_shadow (entity_type, entity_id, base_version,
                                          payload_schema_version, raw_payload_json,
                                          source_device_id, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        rusqlite::params![
            naming::ENTITY_TASK_REMINDER,
            reminder_id,
            shadow_version,
            lorvex_domain::version::PAYLOAD_SCHEMA_VERSION,
            format!(
                r#"{{"task_id":"{parent_task_id}","reminder_at":"2026-05-01T09:00:00.000Z","created_at":"2026-04-20T00:00:00.000Z","updated_at":"2026-04-20T00:00:00.000Z"}}"#,
            ),
            "remote-device",
            "2026-04-20T00:00:00.000Z",
        ],
    )
    .unwrap();

    // Two promote passes back-to-back.
    promote_payload_shadows(&conn).unwrap();
    promote_payload_shadows(&conn).unwrap();

    let pending = get_all_pending(&conn).unwrap();
    assert_eq!(
        pending.len(),
        1,
        "duplicate enqueue must coalesce on (entity_type, entity_id, version)"
    );
    assert!(
        pending[0].attempt_count >= 2,
        "second promote pass must bump attempt_count: got {}",
        pending[0].attempt_count
    );
}
