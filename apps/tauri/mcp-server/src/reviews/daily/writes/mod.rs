mod add;
mod amend;

pub(crate) use add::add_daily_review;
pub(crate) use amend::amend_daily_review;

use crate::error::McpError;

fn validate_review_scales(mood: Option<u8>, energy_level: Option<u8>) -> Result<(), McpError> {
    if mood.is_some_and(|value| !(1..=5).contains(&value)) {
        return Err(McpError::Validation(
            "mood must be between 1 and 5".to_string(),
        ));
    }
    if energy_level.is_some_and(|value| !(1..=5).contains(&value)) {
        return Err(McpError::Validation(
            "energy_level must be between 1 and 5".to_string(),
        ));
    }
    Ok(())
}
