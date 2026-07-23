//! Lease renewal — both the explicit-clock `renew_sync_owner` and the
//! wall-clock `renew_sync_owner_now` constructor. Covers the
//! still-held bump, peer-stolen miss, and already-expired refusal.

use super::support::*;

/// a long-running sync calls `renew_sync_owner`
/// to extend its lease. While we still hold the lease, the SQL
/// `UPDATE ... WHERE owner_id = ? AND expires_at_epoch_ms > ?`
/// matches and we return `true`. The new expiry equals
/// `now_epoch_ms + ttl_ms` so subsequent acquire attempts by other
/// owners are blocked for the full extension window.
#[test]
fn renew_extends_lease_when_still_held() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, 500).expect("seed lease");

    // Renew within TTL — must succeed and bump the expiry.
    let renewed = renew_sync_owner(&conn, "sync_transport", "app", 1_200, 500).expect("renew");
    assert!(renewed, "live lease renewal must succeed");

    let lease = current_sync_owner(&conn, "sync_transport")
        .expect("load")
        .expect("present");
    assert_eq!(lease.owner_id, "app");
    assert_eq!(lease.expires_at_epoch_ms, 1_700, "renew bumps expiry");
}

/// if a peer stole the lease (different
/// `owner_id`), renew must report `false` so the in-flight work
/// can abort instead of continuing under the false belief that
/// we still hold the lease.
#[test]
fn renew_returns_false_when_lease_was_stolen() {
    let conn = test_conn();
    // Peer holds the lease.
    try_acquire_sync_owner(&conn, "sync_transport", "peer", 1_000, 500).expect("seed peer");

    // App calls renew with its own owner_id — must report failure.
    let renewed = renew_sync_owner(&conn, "sync_transport", "app", 1_100, 500).expect("renew");
    assert!(!renewed, "renew on a peer-held lease must report lost");

    // Peer still holds it.
    let lease = current_sync_owner(&conn, "sync_transport")
        .expect("load")
        .expect("present");
    assert_eq!(lease.owner_id, "peer");
}

/// a lease that has already expired (even if
/// nobody else has taken it yet) cannot be renewed — the caller
/// must call `try_acquire_sync_owner` to take it cleanly. The
/// strict `expires_at_epoch_ms > now` predicate enforces this.
#[test]
fn renew_returns_false_when_lease_already_expired() {
    let conn = test_conn();
    try_acquire_sync_owner(&conn, "sync_transport", "app", 1_000, 100).expect("seed");

    // Wall clock is past the expiry (1100). Renew must refuse.
    let renewed = renew_sync_owner(&conn, "sync_transport", "app", 1_500, 500).expect("renew");
    assert!(!renewed, "renew on an expired lease must refuse");
}

/// `renew_sync_owner_now` extends the lease using
/// the runtime's internal wall clock. A live lease must be
/// extendable in-place; a peer-stolen lease must report `false`.
#[test]
fn renew_sync_owner_now_extends_live_lease_via_wall_clock() {
    let conn = test_conn();
    // Acquire via the wall-clock entry point so both acquire and
    // renew agree on the runtime's clock source.
    let acquired = try_acquire_sync_owner_now(&conn, "sync_transport", "app", 600_000)
        .expect("acquire via wall clock");
    assert!(acquired);

    let renewed = renew_sync_owner_now(&conn, "sync_transport", "app", 600_000)
        .expect("renew via wall clock");
    assert!(renewed, "live lease renewal via wall clock must succeed");

    // A different owner_id must report false even when the lease
    // is otherwise live.
    let stolen_renew = renew_sync_owner_now(&conn, "sync_transport", "rival", 600_000)
        .expect("renew attempt by non-owner");
    assert!(
        !stolen_renew,
        "renew_sync_owner_now must refuse a non-owner's renewal"
    );
}
