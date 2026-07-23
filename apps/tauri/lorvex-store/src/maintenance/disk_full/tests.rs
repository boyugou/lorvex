use super::*;
use rusqlite::ffi::{Error as FfiError, ErrorCode as FfiErrorCode};

fn disk_full_error() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::DiskFull,
            extended_code: 13,
        },
        Some("database or disk is full".to_string()),
    )
}

fn ioerr_enospc_error() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::SystemIoFailure,
            extended_code: 778, // SQLITE_IOERR_WRITE
        },
        Some("disk I/O error: No space left on device".to_string()),
    )
}

/// a localized macOS/Linux strerror message
/// (here, simulated French — `"plus d'espace disponible sur le
/// périphérique"`) must still trip the breaker because Rust's
/// `io::Error` `Display` impl always appends `(os error 28)`.
fn ioerr_enospc_localized_unix() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::SystemIoFailure,
            extended_code: 778,
        },
        Some(
            "disk I/O error: plus d'espace disponible sur le \
             périphérique (os error 28)"
                .to_string(),
        ),
    )
}

/// localized Windows ENOSPC. The OS error code
/// `112` (`ERROR_DISK_FULL`) holds across every Windows display
/// language.
fn ioerr_enospc_localized_windows() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::SystemIoFailure,
            extended_code: 778,
        },
        Some("disk I/O error: ディスクは満杯です (os error 112)".to_string()),
    )
}

fn busy_error() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::DatabaseBusy,
            extended_code: 5,
        },
        Some("database is locked".to_string()),
    )
}

fn generic_ioerr_error() -> Error {
    Error::SqliteFailure(
        FfiError {
            code: FfiErrorCode::SystemIoFailure,
            extended_code: 266,
        },
        Some("disk I/O error: permission denied".to_string()),
    )
}

#[test]
fn is_disk_full_error_classifies_rusqlite_diskfull() {
    assert!(is_disk_full_error(&disk_full_error()));
}

#[test]
fn is_disk_full_error_classifies_enospc_wrapped_in_systemiofailure() {
    assert!(is_disk_full_error(&ioerr_enospc_error()));
}

/// locale-independent detection via the
/// `(os error 28)` tail Rust always appends. Without this, a
/// non-English macOS/Linux build's translated strerror silently
/// dodged the circuit breaker.
#[test]
fn is_disk_full_error_classifies_localized_unix_enospc_via_os_error_code() {
    assert!(is_disk_full_error(&ioerr_enospc_localized_unix()));
}

/// same guarantee for Windows
/// `ERROR_DISK_FULL` = 112.
#[test]
fn is_disk_full_error_classifies_localized_windows_disk_full_via_os_error_code() {
    assert!(is_disk_full_error(&ioerr_enospc_localized_windows()));
}

#[test]
fn is_disk_full_error_does_not_classify_busy() {
    assert!(!is_disk_full_error(&busy_error()));
}

#[test]
fn is_disk_full_error_does_not_classify_generic() {
    assert!(!is_disk_full_error(&Error::QueryReturnedNoRows));
    // A generic SystemIoFailure without an ENOSPC-flavored message
    // must not be treated as disk-full — could be a permissions
    // error or a read-only filesystem.
    assert!(!is_disk_full_error(&generic_ioerr_error()));
}

#[test]
fn probe_and_reset_clears_flag_on_healthy_connection() {
    let _guard = breaker_test_mutex()
        .lock()
        .expect("breaker test mutex poisoned");
    clear_tripped_for_tests();
    trip_disk_full();
    let conn = Connection::open_in_memory().unwrap();
    probe_and_reset(&conn).expect("in-memory DB is never disk-full");
    assert!(
        !is_tripped(),
        "healthy probe must reset the circuit breaker"
    );
    clear_tripped_for_tests();
}

#[test]
fn test_breaker_does_not_leak_between_parallel_worker_threads() {
    let _guard = breaker_test_mutex()
        .lock()
        .expect("breaker test mutex poisoned");
    clear_tripped_for_tests();
    trip_disk_full();
    assert!(is_tripped(), "current worker thread must observe its trip");

    let other_thread_tripped = std::thread::spawn(is_tripped)
        .join()
        .expect("worker thread should not panic");
    assert!(
        !other_thread_tripped,
        "test-only breaker state must not leak to unrelated unit-test worker threads"
    );

    clear_tripped_for_tests();
}
