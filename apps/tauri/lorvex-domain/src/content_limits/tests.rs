use super::*;

#[test]
fn ascii_under_limit_is_unchanged() {
    let outcome = clamp_to_byte_limit("hello world", 100);
    assert_eq!(outcome, ClampOutcome::Untouched("hello world".to_string()));
    assert!(!outcome.was_truncated());
}

#[test]
fn ascii_over_limit_is_truncated_at_byte_boundary() {
    let input = "x".repeat(200);
    let outcome = clamp_to_byte_limit(&input, 100);
    match outcome {
        ClampOutcome::Truncated {
            ref value,
            dropped_bytes,
        } => {
            assert_eq!(value.len(), 100);
            assert_eq!(dropped_bytes, 100);
        }
        _ => panic!("expected truncated outcome, got {outcome:?}"),
    }
}

#[test]
fn multibyte_never_splits_a_codepoint() {
    // "😀" is 4 UTF-8 bytes. With a cap of 3 bytes we must drop
    // the whole codepoint rather than emit an invalid prefix.
    let input = "😀😀";
    let outcome = clamp_to_byte_limit(input, 3);
    assert!(outcome.was_truncated());
    assert_eq!(outcome.value(), ""); // No whole codepoint fits.
                                     // Output must be valid UTF-8 (guaranteed by String return, but
                                     // assert explicitly for the contract).
    assert!(std::str::from_utf8(outcome.value().as_bytes()).is_ok());
    if let ClampOutcome::Truncated { dropped_bytes, .. } = outcome {
        assert_eq!(dropped_bytes, 8, "two 4-byte emoji dropped");
    } else {
        panic!("expected Truncated arm");
    }
}

#[test]
fn multibyte_keeps_fitting_codepoints_whole() {
    // Two 4-byte emoji: with a cap of 5, one must fit whole and
    // the second must be dropped entirely.
    let input = "😀😀";
    let outcome = clamp_to_byte_limit(input, 5);
    assert!(outcome.was_truncated());
    assert_eq!(outcome.value(), "😀");
    assert_eq!(outcome.value().len(), 4);
    if let ClampOutcome::Truncated { dropped_bytes, .. } = outcome {
        assert_eq!(dropped_bytes, 4);
    } else {
        panic!("expected Truncated arm");
    }
}

#[test]
fn equal_length_is_not_truncated() {
    let input = "x".repeat(100);
    let outcome = clamp_to_byte_limit(&input, 100);
    assert!(!outcome.was_truncated());
    assert_eq!(outcome.value().len(), 100);
}

#[test]
fn zero_cap_yields_empty() {
    let outcome = clamp_to_byte_limit("nonempty", 0);
    assert_eq!(outcome.value(), "");
    assert!(outcome.was_truncated());
    if let ClampOutcome::Truncated { dropped_bytes, .. } = outcome {
        assert_eq!(dropped_bytes, "nonempty".len());
    } else {
        panic!("expected Truncated arm");
    }
}

#[test]
fn empty_input_is_never_truncated() {
    let outcome = clamp_to_byte_limit("", 0);
    assert_eq!(outcome.value(), "");
    assert!(!outcome.was_truncated());
}
