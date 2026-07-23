use super::*;

use super::{
    classify_apartment_ownership, ApartmentOwnership, ComApartmentGuard, RPC_E_CHANGED_MODE,
    S_FALSE, S_OK,
};
use std::sync::atomic::{AtomicUsize, Ordering};
use windows::core::HRESULT;

// ---- Pure classification mapping (HRESULT -> ApartmentOwnership) ----

#[test]
fn classification_maps_s_ok_to_owned() {
    assert_eq!(
        classify_apartment_ownership(S_OK),
        ApartmentOwnership::Owned
    );
}

#[test]
fn classification_maps_s_false_to_borrowed_same_model() {
    // S_FALSE means the thread was already initialized with the
    // same model — someone else owns the lifecycle. We must NOT
    // call CoUninitialize on drop in this case.
    assert_eq!(
        classify_apartment_ownership(S_FALSE),
        ApartmentOwnership::BorrowedSameModel
    );
}

#[test]
fn classification_maps_rpc_e_changed_mode_to_borrowed_different_model() {
    // RPC_E_CHANGED_MODE means the thread is initialized with a
    // different model; same lifecycle rule as BorrowedSameModel.
    assert_eq!(
        classify_apartment_ownership(RPC_E_CHANGED_MODE),
        ApartmentOwnership::BorrowedDifferentModel
    );
}

#[test]
fn classification_maps_unknown_hresult_to_borrowed_different_model() {
    // E_OUTOFMEMORY / E_INVALIDARG / any other failure: route to
    // borrowed so the Drop impl skips CoUninitialize. We must
    // never uninitialize on top of a CoInitializeEx that did NOT
    // succeed.
    let e_outofmemory = HRESULT(0x8007000E_u32 as i32);
    assert_eq!(
        classify_apartment_ownership(e_outofmemory),
        ApartmentOwnership::BorrowedDifferentModel
    );
}

// ---- RAII pairing semantics ----
//
// The actual `ComApartmentGuard::Drop` calls `CoUninitialize` (an
// FFI call into the Win32 COM runtime), so we can't observe a
// counter directly. Instead we verify the *pattern*: a guard
// constructed from each `ApartmentOwnership` variant must drop
// exactly the way `ComApartmentGuard` does, and the structural
// invariant — "exactly one CoUninitialize per S_OK CoInitializeEx,
// zero otherwise" — is captured by a sentinel that mirrors the
// same `if owned { release(); }` branch and increments a counter.

struct RaiiPair {
    ownership: ApartmentOwnership,
    release_count: &'static AtomicUsize,
}

impl Drop for RaiiPair {
    fn drop(&mut self) {
        if self.ownership == ApartmentOwnership::Owned {
            self.release_count.fetch_add(1, Ordering::SeqCst);
        }
    }
}

#[test]
fn raii_pair_releases_exactly_once_when_owned() {
    static RELEASES: AtomicUsize = AtomicUsize::new(0);
    RELEASES.store(0, Ordering::SeqCst);
    {
        let _p = RaiiPair {
            ownership: ApartmentOwnership::Owned,
            release_count: &RELEASES,
        };
        assert_eq!(RELEASES.load(Ordering::SeqCst), 0, "no release before drop");
    }
    assert_eq!(
        RELEASES.load(Ordering::SeqCst),
        1,
        "Owned variant must call CoUninitialize exactly once on drop"
    );
}

#[test]
fn raii_pair_does_not_release_when_borrowed_same_model() {
    static RELEASES: AtomicUsize = AtomicUsize::new(0);
    RELEASES.store(0, Ordering::SeqCst);
    {
        let _p = RaiiPair {
            ownership: ApartmentOwnership::BorrowedSameModel,
            release_count: &RELEASES,
        };
    }
    assert_eq!(
        RELEASES.load(Ordering::SeqCst),
        0,
        "BorrowedSameModel must NOT call CoUninitialize — someone else owns the lifecycle"
    );
}

#[test]
fn raii_pair_does_not_release_when_borrowed_different_model() {
    static RELEASES: AtomicUsize = AtomicUsize::new(0);
    RELEASES.store(0, Ordering::SeqCst);
    {
        let _p = RaiiPair {
            ownership: ApartmentOwnership::BorrowedDifferentModel,
            release_count: &RELEASES,
        };
    }
    assert_eq!(
        RELEASES.load(Ordering::SeqCst),
        0,
        "BorrowedDifferentModel (RPC_E_CHANGED_MODE) must NOT call CoUninitialize"
    );
}

#[test]
fn raii_pair_pairs_init_with_release_per_scope() {
    // Three nested scopes, each independently owned, must each
    // pair exactly one release. This is the invariant the audit
    // (#2913-M2 / #2833) demanded: every CoInitializeEx that
    // returns S_OK is followed by exactly one CoUninitialize.
    static RELEASES: AtomicUsize = AtomicUsize::new(0);
    RELEASES.store(0, Ordering::SeqCst);
    for _ in 0..3 {
        let _p = RaiiPair {
            ownership: ApartmentOwnership::Owned,
            release_count: &RELEASES,
        };
    }
    assert_eq!(
        RELEASES.load(Ordering::SeqCst),
        3,
        "three scoped acquires must produce three matched releases"
    );
}

// ---- Real CoInitializeEx round-trip on a dedicated thread ----

#[test]
fn real_guard_round_trip_owns_first_acquire_and_borrows_second() {
    // Use a dedicated OS thread so we don't pollute the test
    // harness's apartment state. The first guard on a clean
    // thread must own (S_OK); the second nested guard on the
    // same thread, same model, must borrow (S_FALSE).
    let handle = std::thread::spawn(|| {
        let outer = ComApartmentGuard::enter_sta();
        assert!(
            outer.is_owned(),
            "first CoInitializeEx on a clean thread must return S_OK ({:?})",
            outer.initial_hresult()
        );
        {
            let inner = ComApartmentGuard::enter_sta();
            assert!(
                !inner.is_owned(),
                "nested CoInitializeEx on the same thread+model must return S_FALSE — borrowed, not owned ({:?})",
                inner.initial_hresult()
            );
            // `inner` drops here — must NOT call CoUninitialize
            // (would tear down `outer`'s apartment from under it).
        }
        // `outer` still alive; drop here pairs the original S_OK.
        drop(outer);
    });
    handle.join().expect("dedicated COM-test thread panicked");
}
