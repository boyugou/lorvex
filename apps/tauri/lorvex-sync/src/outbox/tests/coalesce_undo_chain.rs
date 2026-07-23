//! Coalesce-burst behavior: several rapid writes to the same entity
//! collapse onto a single queued row carrying the newest HLC.

use super::*;

/// A burst of updates on the same entity inside one push cycle
/// coalesces onto a single outbox row holding the latest version and
/// payload — every earlier envelope is superseded, not accumulated.
#[test]
fn coalesce_burst_lands_on_single_row_with_latest_version() {
    let conn = test_db();
    let entity_id = "01966a3f-7c8b-7d4e-8f3a-0000000044a0";

    let mut last_payload = String::new();
    for idx in 0..3 {
        let mut env = make_envelope(
            "task",
            entity_id,
            &format!("171123456789{idx}_0000_a1b2c3d4a1b2c3d4"),
        );
        env.payload = format!(r#"{{"title":"burst-{idx}"}}"#);
        last_payload = env.payload.clone();
        enqueue_coalesced(&conn, &env).unwrap();
    }

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1, "burst must collapse to one queued row");
    assert_eq!(
        pending[0].envelope.version.to_string(),
        "1711234567892_0000_a1b2c3d4a1b2c3d4",
        "newest HLC in the burst wins",
    );
    assert_eq!(
        pending[0].envelope.payload, last_payload,
        "latest payload survives the coalesce",
    );
}
