use crate::error::{AppError, AppResult};
use std::fmt::Display;

#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
pub(super) fn required_windows_value<T, E>(value: Result<T, E>, context: &str) -> AppResult<T>
where
    E: Display,
{
    value.map_err(|error| AppError::Validation(format!("{context}: {error}")))
}

#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
pub(super) fn optional_windows_string<T, E>(
    value: Result<T, E>,
    context: &str,
) -> AppResult<Option<String>>
where
    T: ToString,
    E: Display,
{
    required_windows_value(value, context).map(|value| {
        let text = value.to_string();
        (!text.is_empty()).then_some(text)
    })
}
