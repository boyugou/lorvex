//! Shared serde helpers.

/// Convert a SQLite `REAL` value (`f64`) to a JSON value, preserving
/// non-finite (NaN / +Inf / -Inf) values losslessly as a string.
///
/// `serde_json::Number::from_f64` returns `None` for non-finite
/// floats — JSON has no canonical representation for them. The
/// sqlite_json`, `lorvex-sync::outbox_enqueue::snapshot`) silently
/// substituted `Value::Null`, which broadcasts a different value
/// across sync than what the local row actually stores. Encoding
/// non-finite as `Value::String("NaN" | "Infinity" | "-Infinity")`
/// preserves the data losslessly so peers see the same `f64::*`
/// sentinel they would have read from the local DB. Lorvex
/// deliberately doesn't store such values in any production schema
/// column today, so the practical risk is low — but the
/// "silently-coerce-to-null" anti-pattern is a correctness footgun
/// the compiler can't catch, and the sentinel is the right shape
/// for diagnostics if a corrupted row ever surfaces.
pub fn sqlite_real_to_json(value: f64) -> serde_json::Value {
    serde_json::Number::from_f64(value).map_or_else(
        || {
            let sentinel = if value.is_nan() {
                "NaN"
            } else if value == f64::INFINITY {
                "Infinity"
            } else {
                "-Infinity"
            };
            serde_json::Value::String(sentinel.to_string())
        },
        serde_json::Value::Number,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finite_real_round_trips_as_number() {
        let v = sqlite_real_to_json(2.5);
        assert!(v.is_number());
        assert_eq!(v.as_f64(), Some(2.5));
    }

    #[test]
    fn nan_real_renders_as_sentinel_string() {
        assert_eq!(sqlite_real_to_json(f64::NAN), serde_json::json!("NaN"));
    }

    #[test]
    fn positive_infinity_renders_as_sentinel_string() {
        assert_eq!(
            sqlite_real_to_json(f64::INFINITY),
            serde_json::json!("Infinity")
        );
    }

    #[test]
    fn negative_infinity_renders_as_sentinel_string() {
        assert_eq!(
            sqlite_real_to_json(f64::NEG_INFINITY),
            serde_json::json!("-Infinity")
        );
    }
}
