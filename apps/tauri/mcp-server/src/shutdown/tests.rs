use super::*;
use std::sync::atomic::AtomicBool;

#[tokio::test]
async fn shutdown_drain_cancels_before_awaiting_service() {
    let cancelled = Arc::new(AtomicBool::new(false));
    let cancel_seen_by_service = Arc::clone(&cancelled);

    let outcome = cancel_and_drain_service(
        ShutdownTrigger::Signal,
        || cancelled.store(true, Ordering::SeqCst),
        async move {
            if cancel_seen_by_service.load(Ordering::SeqCst) {
                Ok::<_, ()>(())
            } else {
                Err(())
            }
        },
        std::future::ready(()),
        Duration::from_secs(1),
    )
    .await;

    assert_eq!(outcome, Ok(ShutdownDrainOutcome::Drained));
}

#[tokio::test]
async fn shutdown_drain_times_out_when_service_never_finishes() {
    let cancel_count = Arc::new(AtomicUsize::new(0));
    let cancel_count_for_closure = Arc::clone(&cancel_count);

    let outcome = cancel_and_drain_service(
        ShutdownTrigger::ParentProcessChanged,
        || {
            cancel_count_for_closure.fetch_add(1, Ordering::SeqCst);
        },
        std::future::pending::<Result<(), ()>>(),
        std::future::ready(()),
        Duration::from_millis(10),
    )
    .await;

    assert_eq!(outcome, Ok(ShutdownDrainOutcome::TimedOut));
    assert_eq!(cancel_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn shutdown_drain_waits_for_application_work_after_service_stops() {
    let cancel_count = Arc::new(AtomicUsize::new(0));
    let cancel_count_for_closure = Arc::clone(&cancel_count);

    let outcome = cancel_and_drain_service(
        ShutdownTrigger::Signal,
        || {
            cancel_count_for_closure.fetch_add(1, Ordering::SeqCst);
        },
        std::future::ready(Ok::<_, ()>(())),
        std::future::pending::<()>(),
        Duration::from_millis(10),
    )
    .await;

    assert_eq!(outcome, Ok(ShutdownDrainOutcome::TimedOut));
    assert_eq!(cancel_count.load(Ordering::SeqCst), 1);
}

#[tokio::test]
async fn shutdown_drain_waits_for_application_work_before_returning_service_error() {
    let tracker = InFlightTracker::default();
    let guard = tracker.enter();
    let release = tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(5)).await;
        drop(guard);
    });

    let outcome = cancel_and_drain_service(
        ShutdownTrigger::Signal,
        || {},
        std::future::ready(Err::<(), _>("service error")),
        tracker.wait_for_idle(),
        Duration::from_secs(1),
    )
    .await;

    release.await.expect("guard release task should finish");
    assert_eq!(outcome, Err("service error"));
}

#[tokio::test]
async fn shutdown_drain_reports_timeout_before_service_error() {
    let outcome = cancel_and_drain_service(
        ShutdownTrigger::Signal,
        || {},
        std::future::ready(Err::<(), _>("service error")),
        std::future::pending::<()>(),
        Duration::from_millis(10),
    )
    .await;

    assert_eq!(outcome, Ok(ShutdownDrainOutcome::TimedOut));
}

#[tokio::test]
async fn in_flight_tracker_waits_until_last_guard_drops() {
    let tracker = InFlightTracker::default();
    let first = tracker.enter();
    let second = tracker.enter();
    let waiter = tokio::spawn(tracker.clone().wait_for_idle());

    tokio::task::yield_now().await;
    assert!(!waiter.is_finished());

    drop(first);
    tokio::task::yield_now().await;
    assert!(!waiter.is_finished());

    drop(second);
    waiter
        .await
        .expect("waiter should finish after final guard");
}

#[cfg(unix)]
#[test]
#[serial_test::serial(hlc)]
fn parent_process_change_detection_is_explicit_policy() {
    assert!(!parent_process_changed(42, 42));
    assert!(parent_process_changed(42, 1));
}
