use super::*;
use rusqlite::ffi::{Error as FfiError, ErrorCode as FfiErrorCode};
use std::cell::Cell;

fn busy_error() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::DatabaseBusy,
            extended_code: 5,
        },
        Some("database is locked".to_string()),
    )
}

fn locked_error() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::DatabaseLocked,
            extended_code: 6,
        },
        Some("database table is locked".to_string()),
    )
}

fn constraint_error() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::ConstraintViolation,
            extended_code: 19,
        },
        Some("UNIQUE constraint failed".to_string()),
    )
}

#[test]
fn with_busy_retry_succeeds_first_try() {
    let calls = Cell::new(0u32);
    let result = with_busy_retry(DEFAULT_RETRY_BUDGET, || {
        calls.set(calls.get() + 1);
        Ok::<_, Error>(42u32)
    })
    .expect("closure should succeed");
    assert_eq!(result, 42);
    assert_eq!(calls.get(), 1, "closure must be called exactly once");
}

#[test]
fn with_busy_retry_surfaces_non_busy_error_immediately() {
    let calls = Cell::new(0u32);
    let err = with_busy_retry::<(), _>(DEFAULT_RETRY_BUDGET, || {
        calls.set(calls.get() + 1);
        Err(constraint_error())
    })
    .expect_err("non-busy error must bypass retry");
    assert!(
        matches!(err, Error::SqliteFailure(code, _) if code.code == FfiErrorCode::ConstraintViolation),
        "unexpected error: {err}"
    );
    assert_eq!(
        calls.get(),
        1,
        "non-busy errors must be surfaced without retry"
    );
}

#[test]
fn with_busy_retry_exhausts_budget_on_persistent_busy() {
    let calls = Cell::new(0u32);
    let budget = 3;
    let err = with_busy_retry::<(), _>(budget, || {
        calls.set(calls.get() + 1);
        Err(busy_error())
    })
    .expect_err("persistent busy must surface after budget");
    assert!(
        matches!(err, Error::SqliteFailure(code, _) if code.code == FfiErrorCode::DatabaseBusy),
        "final error must still be a BUSY: {err}"
    );
    assert_eq!(
        calls.get(),
        budget,
        "closure must be called exactly `budget` times"
    );
}

#[test]
fn with_busy_retry_also_retries_locked() {
    let calls = Cell::new(0u32);
    let err = with_busy_retry::<(), _>(2, || {
        calls.set(calls.get() + 1);
        Err(locked_error())
    })
    .expect_err("LOCKED must be treated as retryable");
    assert!(
        matches!(err, Error::SqliteFailure(code, _) if code.code == FfiErrorCode::DatabaseLocked)
    );
    assert_eq!(calls.get(), 2);
}

#[test]
fn with_busy_retry_recovers_after_transient_busy() {
    let calls = Cell::new(0u32);
    let result = with_busy_retry(DEFAULT_RETRY_BUDGET, || {
        calls.set(calls.get() + 1);
        if calls.get() < 3 {
            Err(busy_error())
        } else {
            Ok::<_, Error>("done")
        }
    })
    .expect("should succeed once contention clears");
    assert_eq!(result, "done");
    assert_eq!(calls.get(), 3, "closure must be retried until it succeeds");
}

#[test]
fn with_busy_retry_zero_budget_still_runs_once() {
    let calls = Cell::new(0u32);
    let err = with_busy_retry::<(), _>(0, || {
        calls.set(calls.get() + 1);
        Err(busy_error())
    })
    .expect_err("zero budget must still run the closure once");
    assert!(
        matches!(err, Error::SqliteFailure(code, _) if code.code == FfiErrorCode::DatabaseBusy)
    );
    assert_eq!(calls.get(), 1, "zero budget should be treated as one");
}

#[test]
fn is_busy_error_classifies_correctly() {
    assert!(is_busy_error(&busy_error()));
    assert!(is_busy_error(&locked_error()));
    assert!(!is_busy_error(&constraint_error()));
    assert!(!is_busy_error(&Error::QueryReturnedNoRows));
}
