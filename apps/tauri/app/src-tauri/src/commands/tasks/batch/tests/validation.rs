use super::super::*;
use super::support::*;

#[test]
fn validate_batch_task_ids_rejects_empty_input() {
    let error = validate_batch_task_ids(&[]).expect_err("empty input should be rejected");
    assert!(matches!(error, AppError::Validation(_)));
}

#[test]
fn validate_batch_task_ids_rejects_too_many_ids() {
    let ids: Vec<String> = (0..MAX_BATCH_TASK_IDS + 1).map(|_| uid()).collect();
    let error = validate_batch_task_ids(&ids).expect_err("over-limit input should be rejected");
    match error {
        AppError::Validation(message) => {
            assert!(message.contains("maximum"), "unexpected: {message}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn validate_batch_task_ids_accepts_boundary_limit() {
    let ids: Vec<String> = (0..MAX_BATCH_TASK_IDS).map(|_| uid()).collect();
    let validated = validate_batch_task_ids(&ids).expect("boundary-sized batch should be accepted");
    assert_eq!(validated.len(), MAX_BATCH_TASK_IDS);
}

#[test]
fn validate_batch_task_ids_deduplicates_first_seen_ids() {
    let task_a = uid();
    let task_b = uid();
    let validated = validate_batch_task_ids(&[
        task_a.clone(),
        task_b.clone(),
        task_a.clone(),
        task_b.clone(),
    ])
    .expect("duplicate ids should be accepted and normalized");

    assert_eq!(validated, vec![task_a, task_b]);
}

/// `validate_batch_task_ids` now shape-checks every
/// id against the canonical UUIDv7 contract before any writer
/// transaction opens. A non-UUID id would previously have flowed
/// straight into `fetch_tasks_by_ids` and only surfaced as an
/// opaque sync-apply mismatch on a peer device.
#[test]
fn validate_batch_task_ids_rejects_non_uuid_ids() {
    let bogus = vec!["not-a-uuid".to_string(), uid()];
    let error = validate_batch_task_ids(&bogus).expect_err("non-UUID id must be rejected");
    match error {
        AppError::Validation(message) => assert!(
            message.contains("task_id"),
            "expected task_id-tagged error, got: {message}"
        ),
        other => panic!("expected Validation, got {other:?}"),
    }
}
