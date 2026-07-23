use crate::hlc::*;

/// the canonical [`TEST_VERSION`] constant must keep
/// its LWW-safe shape. Any change that breaks the digit-prefix
/// invariant fails this test (and would silently break every
/// downstream test fixture that relies on it).
#[test]
fn test_version_is_lww_safe() {
    // Starts with an ASCII digit so it sorts strictly below every
    // realistic HLC at runtime.
    assert!(TEST_VERSION.as_bytes()[0].is_ascii_digit());
    // Parses as a valid HLC (the compile-time assertion only
    // checks the leading byte; this check confirms the full shape).
    Hlc::parse(TEST_VERSION).expect("TEST_VERSION must parse as a valid HLC");
    // Belt-and-braces: the const-fn gate also accepts it.
    assert_test_version_safe(TEST_VERSION);
}

/// The compile-time assertion rejects letter-prefixed literals,
/// which sort lex-greater than digit-prefixed HLCs at runtime and
/// would silently no-op LWW-gated test mutations.
#[test]
#[should_panic(expected = "must start with an ASCII digit")]
fn assert_test_version_safe_rejects_letter_prefix() {
    assert_test_version_safe("v1");
}

#[test]
#[should_panic(expected = "must start with an ASCII digit")]
fn assert_test_version_safe_rejects_test_ver_literal() {
    assert_test_version_safe("test_ver");
}

#[test]
#[should_panic(expected = "is empty")]
fn assert_test_version_safe_rejects_empty() {
    assert_test_version_safe("");
}
