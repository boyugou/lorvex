//! SQL identifier safety guard.
//!
//! Defense-in-depth for `format!`-interpolated SQL identifiers.

/// Validate that a string is a safe SQL identifier (table or column name).
///
/// Only allows ASCII alphanumeric characters and underscores. This is a
/// defense-in-depth guard for `format!`-interpolated SQL identifiers — all
/// current callers use hardcoded string constants, but this check makes the
/// injection surface explicit and prevents future regressions if a caller
/// starts accepting user input.
///
/// # Panics
///
/// This function panics on invalid input rather than returning an error,
/// because an invalid SQL identifier at a `format!` call site is always a
/// programming error (not a user-input problem).
pub fn assert_safe_sql_identifier(s: &str) {
    assert!(
        !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_'),
        "invalid SQL identifier: \"{s}\" — only ASCII alphanumeric and underscore are allowed"
    );
}
