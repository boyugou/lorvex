use super::types::FocusScheduleBlockInput;

pub(super) fn parse_focus_schedule_blocks_json(
    blocks_json: &str,
) -> Result<Vec<lorvex_store::focus_schedule_blocks::ScheduleBlockEntry>, crate::error::CliError> {
    let raw_blocks: Vec<FocusScheduleBlockInput> =
        serde_json::from_str(blocks_json).map_err(|error| {
            crate::error::CliError::Validation(format!(
                "focus schedule blocks-json must be a JSON array: {error}"
            ))
        })?;
    raw_blocks
        .into_iter()
        .enumerate()
        .map(|(index, block)| {
            let block_type = block.block_type.trim().to_ascii_lowercase();
            if !matches!(block_type.as_str(), "task" | "buffer" | "event") {
                return Err(crate::error::CliError::Validation(format!(
                    "focus schedule blocks[{index}].block_type must be one of task, buffer, event"
                )));
            }
            let start_minutes = lorvex_domain::parse_hhmm_to_minutes(&block.start_time)
                .ok_or_else(|| {
                    crate::error::CliError::Validation(format!(
                        "focus schedule blocks[{index}].start_time must be HH:MM"
                    ))
                })?;
            let end_minutes = lorvex_domain::parse_hhmm_to_minutes(&block.end_time)
                .ok_or_else(|| {
                    crate::error::CliError::Validation(format!(
                        "focus schedule blocks[{index}].end_time must be HH:MM"
                    ))
                })?;
            if end_minutes <= start_minutes {
                return Err(crate::error::CliError::Validation(format!(
                    "focus schedule blocks[{index}].end_time must be later than start_time"
                )));
            }
            let task_id = block
                .task_id
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty());
            let event_id = block
                .event_id
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty());
            let title = block
                .title
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty());

            match block_type.as_str() {
                "task" if task_id.is_none() => {
                    return Err(crate::error::CliError::Validation(format!(
                        "focus schedule blocks[{index}].task_id is required for task blocks"
                    )));
                }
                "buffer" if task_id.is_some() || event_id.is_some() => {
                    return Err(crate::error::CliError::Validation(format!(
                        "focus schedule blocks[{index}] buffer blocks must not include task_id or event_id"
                    )));
                }
                "event" if event_id.is_none() && title.is_none() => {
                    return Err(crate::error::CliError::Validation(format!(
                        "focus schedule blocks[{index}] event blocks require event_id or title"
                    )));
                }
                _ => {}
            }

            Ok(lorvex_store::focus_schedule_blocks::ScheduleBlockEntry {
                block_type,
                start_minutes,
                end_minutes,
                task_id,
                event_id,
                title,
            })
        })
        .collect()
}
