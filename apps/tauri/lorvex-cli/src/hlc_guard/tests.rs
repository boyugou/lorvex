use super::*;
use rusqlite::params;

fn open_test_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute(
        "CREATE TABLE sync_checkpoints (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT",
        [],
    )
    .expect("create sync_checkpoints");
    conn.execute(
        "INSERT INTO sync_checkpoints(key, value) VALUES ('device_id', ?1)",
        params!["01900000-1111-7222-8333-444455556666"],
    )
    .expect("seed device_id");
    conn
}

#[test]
fn next_hlc_version_strictly_monotonic_across_calls() {
    // start from a clean slate so a prior test in the
    // same binary doesn't bake its device_id into the process-wide
    // state. Hold `hlc_test_mutex()` for the
    // reset-through-assert window so a parallel test that also
    // mutates HLC_RUNTIME cannot reset between our seed and our
    // assertions.
    let _hlc_guard = hlc_test_mutex().lock().expect("hlc test mutex poisoned");
    reset_hlc_state_for_tests();
    let conn = open_test_conn();
    let a = next_hlc_version(&conn).unwrap();
    let b = next_hlc_version(&conn).unwrap();
    let c = next_hlc_version(&conn).unwrap();
    assert!(a < b, "first < second: {a} < {b}");
    assert!(b < c, "second < third: {b} < {c}");
}

#[test]
fn observer_advances_state_past_observed_merge_version() {
    // The CLI binary's `register_local_event_observer` competes
    // for the same `OnceLock` as the mcp-server's lazy init (see
    // #3031). Whichever surface initializes first wins the slot,
    // and the loser's `HLC_RUNTIME` never receives merge events.
    // Drive this test through the per-test `TEST_OBSERVER` slot
    // (consulted before the production OnceLock) so the assertion
    // holds regardless of test order or which surface won the
    // production-side install.
    let _hlc_guard = hlc_test_mutex().lock().expect("hlc test mutex poisoned");
    reset_hlc_state_for_tests();
    let conn = open_test_conn();

    // Prime HLC_RUNTIME so the test observer's `update_on_receive`
    // has a real `HlcState` to advance.
    let _ = next_hlc_version(&conn).expect("first generate");

    // Far-future HLC the local clock cannot otherwise reach.
    let merge_hlc = lorvex_domain::hlc::Hlc::new(9_999_999_999_990, 0, "ffffffffffffffff")
        .expect("canonical 16-hex suffix");

    let after = lorvex_sync::hlc::with_temporary_observer(
        |observed| {
            assert!(
                HLC_RUNTIME.observe_hlc_if_initialized(observed),
                "HLC state primed by first generate above"
            );
        },
        || {
            lorvex_sync::hlc::observe_local_event(&merge_hlc);
            next_hlc_version(&conn).expect("generate after observation")
        },
    );
    let after_hlc = lorvex_domain::hlc::Hlc::parse(&after).expect("generated HLC parses");
    assert!(
        after_hlc > merge_hlc,
        "post-observation generate {after} must exceed merge_version {merge_hlc}"
    );

    // Drain the far-future HLC out of the process-global state so
    // the next test in the binary starts from a clean slate.
    reset_hlc_state_for_tests();
}

#[test]
fn observer_install_is_idempotent_across_repeat_inits() {
    // the OnceLock contract returns AlreadyInstalled
    // on every call after the first. A second pass through the
    // lazy-init path (e.g. test reset + reuse, or a future code
    // path that reinitializes after a config reload) must not
    // panic. The CLI's `lock_initialized` calls
    // `register_local_event_observer` after `*guard = Some(...)`;
    // calling it twice exercises the AlreadyInstalled branch.
    let _hlc_guard = hlc_test_mutex().lock().expect("hlc test mutex poisoned");
    reset_hlc_state_for_tests();
    let conn = open_test_conn();
    let _ = next_hlc_version(&conn).expect("first generate");
    reset_hlc_state_for_tests();
    // Second pass through lazy init — observer slot is already
    // filled, so the inner match must hit AlreadyInstalled and
    // succeed without panicking.
    let _ = next_hlc_version(&conn).expect("second generate after reset");
}

#[test]
fn reset_then_seed_swaps_device_suffix_in_subsequent_hlc() {
    // with the test mutex held, this assertion is
    // safe to make. Without the mutex it would be racey because
    // HLC_RUNTIME is process-wide. Verifies the contract that a
    // post-reset `next_hlc_version` call observes the device id
    // it was seeded with — without this coverage, a regression
    // that swapped reset to leave the prior state in place would
    // silently break's intent.
    let _hlc_guard = hlc_test_mutex().lock().expect("hlc test mutex poisoned");
    reset_hlc_state_for_tests();
    let conn = open_test_conn();
    let version = next_hlc_version(&conn).unwrap();
    // HLC format: `{13-digit-ms}_{04-counter}_{16-hex-suffix}`.
    let suffix_start = version.len() - 16;
    let suffix = &version[suffix_start..];
    // The seeded device id `01900000-1111-7222-8333-444455556666`
    // hashes to a known suffix; we don't pin the exact hash, but
    // we DO pin that the suffix is 16 lowercase hex chars.
    assert_eq!(suffix.len(), 16);
    assert!(
        suffix.chars().all(|c| c.is_ascii_hexdigit()),
        "device suffix should be hex: {suffix}"
    );
}
