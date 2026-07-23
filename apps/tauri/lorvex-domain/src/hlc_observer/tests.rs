use super::*;
use std::sync::{Arc, Mutex};

#[test]
fn observe_local_event_is_noop_without_observer() {
    // Default state: no production observer installed for this
    // test binary, no test observer swapped in. The call must
    // succeed silently — if a panic escaped the merge sites would
    // tear down the entire apply transaction.
    let hlc = Hlc::new(1_000_000_000_000, 0, "abcdef0123456789").unwrap();
    observe_local_event(&hlc);
}

#[test]
fn with_temporary_observer_captures_event() {
    let captured = Arc::new(Mutex::new(Vec::<Hlc>::new()));
    let captured_for_observer = Arc::clone(&captured);
    let hlc = Hlc::new(1_000_000_000_000, 5, "abcdef0123456789").unwrap();

    with_temporary_observer(
        move |observed| {
            captured_for_observer
                .lock()
                .expect("capture lock")
                .push(observed.clone());
        },
        || {
            observe_local_event(&hlc);
        },
    );

    let captured = captured.lock().expect("capture lock");
    assert_eq!(captured.len(), 1);
    assert_eq!(captured[0], hlc);
}

#[test]
fn with_temporary_observer_clears_on_drop() {
    // After the helper returns, observe_local_event must NOT route
    // to the previous test observer — otherwise cross-test bleed
    // would silently re-fire prior captures.
    let captured = Arc::new(Mutex::new(0usize));
    let captured_for_observer = Arc::clone(&captured);
    with_temporary_observer(
        move |_| {
            *captured_for_observer.lock().expect("count lock") += 1;
        },
        || {
            observe_local_event(&Hlc::new(1_000_000_000_000, 0, "0000000000000001").unwrap());
        },
    );
    // Now outside the helper.
    observe_local_event(&Hlc::new(2_000_000_000_000, 0, "0000000000000002").unwrap());
    assert_eq!(*captured.lock().expect("count lock"), 1);
}
