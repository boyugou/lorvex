use super::*;

#[test]
fn delete_entry_removes_from_outbox() {
    let conn = test_db();
    let env = make_envelope(
        "task",
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    enqueue(&conn, &env).unwrap();

    let pending = get_pending(&conn).unwrap();
    assert_eq!(pending.len(), 1);

    delete_entry(&conn, pending[0].id).unwrap();

    let pending_after = get_pending(&conn).unwrap();
    assert!(pending_after.is_empty());
}
