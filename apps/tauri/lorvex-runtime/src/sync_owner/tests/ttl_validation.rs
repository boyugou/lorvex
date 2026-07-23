//! TTL validation: zero/negative/`i64::MIN` are hard rejects, and a
//! caller-supplied huge TTL clamps to the documented 24h ceiling.

use super::support::*;

/// non-positive TTLs were previously masked by
/// `.max(1)`, which hid arithmetic bugs upstream (a caller whose
/// TTL formula underflowed to a negative value silently got a
/// 1 ms lease). Both negative and zero must now error out so the
/// underlying bug surfaces at the call site, and the lease row
/// must remain untouched.
#[test]
fn rejects_negative_ttl() {
    let conn = test_conn();
    let err = try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, -1)
        .expect_err("negative ttl must reject");
    assert!(
        matches!(err, RuntimeError::InvalidLeaseTtl(-1)),
        "expected InvalidLeaseTtl(-1), got {err:?}"
    );
    // The acquire must not have written a row.
    assert!(current_sync_owner(&conn, "sync_transport")
        .expect("load owner")
        .is_none());
}

#[test]
fn rejects_zero_ttl() {
    let conn = test_conn();
    let err = try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, 0)
        .expect_err("zero ttl must reject");
    assert!(
        matches!(err, RuntimeError::InvalidLeaseTtl(0)),
        "expected InvalidLeaseTtl(0), got {err:?}"
    );
    assert!(current_sync_owner(&conn, "sync_transport")
        .expect("load owner")
        .is_none());
}

#[test]
fn rejects_i64_min_ttl() {
    let conn = test_conn();
    let err = try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, i64::MIN)
        .expect_err("i64::MIN ttl must reject");
    assert!(
        matches!(err, RuntimeError::InvalidLeaseTtl(v) if v == i64::MIN),
        "expected InvalidLeaseTtl(i64::MIN), got {err:?}"
    );
    assert!(current_sync_owner(&conn, "sync_transport")
        .expect("load owner")
        .is_none());
}

/// `ttl_ms` clamps to the documented ceiling
/// (24h) so an arithmetic bug in the caller can't pin a lease
/// for years. The clamp is silent (the ceiling is policy, not
/// caller error), but the stored `expires_at_epoch_ms` MUST not
/// exceed `now + MAX_LEASE_TTL_MS`.
#[test]
fn try_acquire_sync_owner_clamps_huge_ttl_to_24h() {
    let conn = test_conn();

    let now_epoch_ms = 1_700_000_000_000_i64;
    // Caller supplied TTL of 30 days — must clamp to 24h.
    let ttl_ms = 30 * 24 * 60 * 60 * 1000_i64;
    let acquired = try_acquire_sync_owner(&conn, "sync_transport", "app", now_epoch_ms, ttl_ms)
        .expect("acquire");
    assert!(acquired);

    let lease = current_sync_owner(&conn, "sync_transport")
        .expect("load")
        .expect("present");
    assert_eq!(
        lease.expires_at_epoch_ms,
        now_epoch_ms + MAX_LEASE_TTL_MS,
        "ttl_ms clamps to MAX_LEASE_TTL_MS"
    );
}
