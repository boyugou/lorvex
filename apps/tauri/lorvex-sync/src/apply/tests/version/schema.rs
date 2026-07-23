use super::*;

#[test]
fn apply_deferred_when_payload_too_far_ahead() {
    let conn = test_db();
    let mut env = make_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    env.payload_schema_version = PAYLOAD_SCHEMA_VERSION + 2;

    let result = apply_envelope(&conn, &env).unwrap();
    assert!(matches!(result, ApplyResult::Deferred { .. }));
}

#[test]
fn apply_succeeds_with_forward_compat_version() {
    let conn = test_db();
    let mut env = make_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    env.payload_schema_version = PAYLOAD_SCHEMA_VERSION + 1;

    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);
}

#[test]
fn apply_succeeds_with_older_payload_version() {
    let conn = test_db();
    let mut env = make_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );
    // payload_schema_version 0 is older than current
    env.payload_schema_version = 0;

    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);
}

#[test]
fn apply_is_idempotent() {
    let conn = test_db();
    let env = make_envelope(
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4",
    );

    // Apply the same envelope twice.
    let r1 = apply_envelope(&conn, &env).unwrap();
    let r2 = apply_envelope(&conn, &env).unwrap();

    // First apply succeeds. Second is skipped because local version == remote version.
    assert_eq!(r1, ApplyResult::Applied);
    assert!(
        r2 == ApplyResult::Applied || matches!(r2, ApplyResult::Skipped { .. }),
        "idempotent apply should be Applied or Skipped, got: {r2:?}"
    );
}
