use super::*;

#[test]
fn canonical_test_version_is_lex_below_a_realistic_hlc() {
    // Sanity: TEST_VERSION must sort strictly below a freshly-
    // shaped HLC at any realistic wall-clock ms. We use 2026 as
    // a stand-in for "now" — every realistic post-update HLC is
    // some ms count well past this point.
    let realistic = "1772449200000_0000_devicelo01234567";
    assert!(TEST_VERSION < realistic);
}

#[test]
fn seed_test_row_check_accepts_canonical_constant() {
    assert!(seed_test_row_check(TEST_VERSION).is_ok());
}

#[test]
fn seed_test_row_check_accepts_real_hlc_shape() {
    assert!(seed_test_row_check("1772449200000_0000_devicelo01234567").is_ok());
}

#[test]
fn seed_test_row_check_rejects_letter_prefix() {
    let err = seed_test_row_check("test_ver").expect_err("must reject");
    assert!(err.contains("non-digit"), "unexpected message: {err}");
    assert!(err.contains("test_ver"));
}

#[test]
fn seed_test_row_check_rejects_seed_prefix() {
    assert!(seed_test_row_check("seedseed").is_err());
    assert!(seed_test_row_check("seed-v1").is_err());
}

#[test]
fn seed_test_row_check_rejects_empty_string() {
    let err = seed_test_row_check("").expect_err("must reject");
    assert!(err.contains("empty"));
}
