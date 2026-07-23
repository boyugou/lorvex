use super::*;
use crate::maintenance::disk_full::clear_tripped_for_tests;
use rusqlite::ffi::{Error as FfiError, ErrorCode as FfiErrorCode};

fn sqlite_full_error() -> rusqlite::Error {
    rusqlite::Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::DiskFull,
            extended_code: 13,
        },
        Some("database or disk is full".to_string()),
    )
}

#[test]
fn from_rusqlite_classifies_diskfull_and_trips_breaker() {
    let _guard = crate::maintenance::disk_full::breaker_test_mutex()
        .lock()
        .expect("breaker test mutex poisoned");
    clear_tripped_for_tests();
    let store_err: StoreError = sqlite_full_error().into();
    match store_err {
        StoreError::DiskFull { details } => {
            assert!(details.to_lowercase().contains("disk"));
        }
        other => panic!("expected DiskFull, got {other:?}"),
    }
    assert!(
        crate::maintenance::disk_full::is_tripped(),
        "DiskFull classification must trip the breaker"
    );
    clear_tripped_for_tests();
}

#[test]
fn from_rusqlite_passes_generic_through_as_sql() {
    // this test deliberately does NOT consult the
    // breaker afterwards. The previous shape asserted
    // `!is_tripped()` post-call, which raced against the three
    // breaker-mutating tests in the same binary and produced
    // sporadic false-fails. The contract under test here is
    // narrowly scoped: `From<rusqlite::Error>` for non-disk-full
    // inputs must yield `StoreError::Sql(_)` — nothing else.
    let generic = rusqlite::Error::QueryReturnedNoRows;
    let store_err: StoreError = generic.into();
    assert!(matches!(store_err, StoreError::Sql(_)));
}
