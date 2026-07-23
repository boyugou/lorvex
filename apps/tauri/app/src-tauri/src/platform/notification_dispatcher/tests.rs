use super::*;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

static TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

fn isolated_counter() -> MutexGuard<'static, ()> {
    let guard = TEST_LOCK
        .get_or_init(|| Mutex::new(()))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    IN_FLIGHT.store(0, Ordering::SeqCst);
    guard
}

#[test]
fn track_emit_increments_then_decrements() {
    let _guard = isolated_counter();

    assert_eq!(IN_FLIGHT.load(Ordering::SeqCst), 0);
    let inside = track_emit(|| IN_FLIGHT.load(Ordering::SeqCst));
    assert_eq!(inside, 1);
    assert_eq!(IN_FLIGHT.load(Ordering::SeqCst), 0);
}

#[test]
fn wait_for_idle_returns_true_when_already_idle() {
    let _guard = isolated_counter();

    assert!(wait_for_idle(Duration::from_millis(50)));
}

#[test]
fn track_emit_drop_guards_against_panic() {
    let _guard = isolated_counter();

    let observed = Arc::new(AtomicBool::new(false));
    let observed_clone = Arc::clone(&observed);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        track_emit(|| {
            observed_clone.store(true, Ordering::SeqCst);
            panic!("simulated emit failure");
        });
    }));
    assert!(result.is_err());
    assert!(observed.load(Ordering::SeqCst));
    // Counter must have been decremented even though body panicked.
    assert_eq!(IN_FLIGHT.load(Ordering::SeqCst), 0);
}
