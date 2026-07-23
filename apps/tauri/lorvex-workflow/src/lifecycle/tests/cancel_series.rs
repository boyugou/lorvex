use std::cell::RefCell;
use std::sync::Mutex;

use rusqlite::params;

use super::support::{run_cancel_in_tx, test_conn, tid};
use lorvex_domain::hlc::Hlc;
use lorvex_domain::hlc_session::{HlcSession, HlcStateHandle};
use lorvex_store::StoreError;

/// Test HLC handle that emits a caller-prescribed sequence of stamps.
/// Each `generate` call pops the next pre-built `Hlc` off the deque,
/// letting tests assert on the exact stamps the lifecycle helper
/// minted from the session.
struct ScriptedHlcHandle {
    stamps: Mutex<RefCell<std::collections::VecDeque<Hlc>>>,
}

impl ScriptedHlcHandle {
    fn new(versions: &[&str]) -> Self {
        let parsed: std::collections::VecDeque<Hlc> = versions
            .iter()
            .map(|v| Hlc::parse(v).expect("scripted HLC version must parse"))
            .collect();
        Self {
            stamps: Mutex::new(RefCell::new(parsed)),
        }
    }

    fn remaining(&self) -> usize {
        self.stamps.lock().expect("test mutex").borrow().len()
    }
}

impl HlcStateHandle for ScriptedHlcHandle {
    fn generate(&self) -> Hlc {
        self.stamps
            .lock()
            .expect("test mutex")
            .borrow_mut()
            .pop_front()
            .expect("scripted HLC handle exhausted")
    }
}

/// H2 regression — `cancel_series=true` must bump `version` on the
/// recurrence-clear UPDATE so the outbox ships a strictly-newer HLC
/// to peers. Pre-fix the UPDATE wrote only `updated_at`, leaving
/// `version` at the value `cancel_task` had just stamped, so peers
/// received the cancel envelope but the recurrence-clear envelope
/// (re-stamped at the same HLC) was a no-op — the recurrence fields
/// would silently come back on the next sync from a peer that still
/// had them.
#[test]
fn cancel_series_advances_version_when_clearing_recurrence_fields() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("r1")
        .title("Recurring")
        .due_date(Some("2026-04-01"))
        .canonical_occurrence_date("2026-04-01")
        .recurrence(r#"{"freq":"daily"}"#)
        .recurrence_group_id("grp-r1")
        .recurrence_instance_key("grp-r1#2026-04-01")
        .insert(&conn);

    let now = "2026-03-26T10:00:00Z";
    let reminder_version = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    run_cancel_in_tx(&conn, "r1", now, reminder_version, true).unwrap();

    let (status, version, recurrence, group_id, instance_key): (
        String,
        String,
        Option<String>,
        Option<String>,
        Option<String>,
    ) = conn
        .query_row(
            "SELECT status, version, recurrence, recurrence_group_id, recurrence_instance_key \
             FROM tasks WHERE id = 'r1'",
            [],
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
        .unwrap();
    assert_eq!(status, "cancelled");
    assert!(recurrence.is_none(), "recurrence cleared");
    assert!(group_id.is_none(), "recurrence_group_id cleared");
    assert!(instance_key.is_none(), "recurrence_instance_key cleared");
    // The recurrence-clear UPDATE must advance `version` past
    // `reminder_version` so peers see a strictly-newer HLC for the
    // series-clear write than for the cancel write.
    assert!(
        version.as_str() > reminder_version,
        "expected version strictly > reminder_version (`{reminder_version}`), got `{version}`"
    );
}

#[test]
fn cancel_series_uses_caller_supplied_hlc_for_recurrence_clear() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("r-surface")
        .title("Recurring surface")
        .due_date(Some("2026-04-01"))
        .canonical_occurrence_date("2026-04-01")
        .recurrence(r#"{"freq":"daily"}"#)
        .recurrence_group_id("grp-r-surface")
        .recurrence_instance_key("grp-r-surface#2026-04-01")
        .insert(&conn);

    let now = "2026-03-26T10:00:00Z";
    let reminder_version = "0000000000100_0000_1111111111111111";
    let series_clear_version = "0000000000100_0001_2222222222222222";
    let handle = ScriptedHlcHandle::new(&[reminder_version, series_clear_version]);
    let session = HlcSession::new(&handle);

    lorvex_store::transaction::with_immediate_transaction(&conn, |c| {
        super::super::effects::run_cancel(c, &tid("r-surface"), now, true, &session)
    })
    .unwrap();

    assert_eq!(
        handle.remaining(),
        0,
        "recurring cancel_series should consume both scripted HLC stamps"
    );

    let stored_version: String = conn
        .query_row(
            "SELECT version FROM tasks WHERE id = 'r-surface'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored_version, series_clear_version,
        "recurrence clear must persist the caller-supplied surface HLC"
    );
}

/// H2 regression — when a strictly-newer remote version has already
/// landed on the row between the cancel write and the recurrence-clear
/// write, the LWW gate must reject and the helper must surface
/// `StaleVersion` so the boundary layer can re-stamp HLC and retry.
#[test]
fn cancel_series_surfaces_stale_version_when_peer_advances_first() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("r1")
        .title("Recurring")
        .due_date(Some("2026-04-01"))
        .canonical_occurrence_date("2026-04-01")
        .recurrence(r#"{"freq":"daily"}"#)
        .recurrence_group_id("grp-r1")
        .insert(&conn);

    // The reminder_version is the HLC `cancel_task` will stamp; the
    // recurrence-clear write derives its version by appending
    // `_series` to that prefix. Pre-seed a row whose version already
    // exceeds the derived `<reminder_version>_series` so the gate
    // rejects.
    let reminder_version = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    let newer = "9999999999999_0000_ffffffffffffffff";
    conn.execute(
        "UPDATE tasks SET version = ?1 WHERE id = 'r1'",
        params![newer],
    )
    .unwrap();

    let err =
        run_cancel_in_tx(&conn, "r1", "2026-03-26T10:00:00Z", reminder_version, true).unwrap_err();
    assert!(matches!(err, StoreError::StaleVersion { .. }));

    // The transaction rolled back: status must remain "open" and
    // recurrence fields must remain populated.
    let (status, recurrence): (String, Option<String>) = conn
        .query_row(
            "SELECT status, recurrence FROM tasks WHERE id = 'r1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(status, "open");
    assert!(recurrence.is_some());
}
