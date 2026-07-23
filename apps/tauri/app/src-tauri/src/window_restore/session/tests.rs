use super::state::{
    claim_window_restore_in_flight, mark_window_restore_pending, release_window_restore_in_flight,
    take_window_restore_pending,
};
use std::sync::{Mutex, OnceLock};

fn restore_state_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

fn reset_restore_state() {
    release_window_restore_in_flight();
    let _ = take_window_restore_pending();
}

#[test]
fn window_restore_single_flight_and_pending_replay_state_machine() {
    let _guard = restore_state_lock()
        .lock()
        .expect("lock restore state test mutex");
    reset_restore_state();

    assert!(claim_window_restore_in_flight());
    assert!(!claim_window_restore_in_flight());

    mark_window_restore_pending();
    mark_window_restore_pending();
    release_window_restore_in_flight();

    assert!(take_window_restore_pending());
    assert!(!take_window_restore_pending());

    assert!(claim_window_restore_in_flight());
    release_window_restore_in_flight();
    reset_restore_state();
}
