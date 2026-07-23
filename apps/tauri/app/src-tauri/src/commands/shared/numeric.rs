//! Numeric clamping helpers shared by IPC handlers.

pub(crate) fn clamp_limit(value: Option<i64>, default_value: i64, min: i64, max: i64) -> i64 {
    value.unwrap_or(default_value).clamp(min, max)
}
