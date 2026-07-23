use super::*;

/// Query blocks from the focus_schedule_blocks sub-table for a given schedule date.
/// DB stores start_time/end_time as INTEGER (minute-of-day); output uses HH:MM strings.
pub(super) fn query_schedule_blocks(
    conn: &rusqlite::Connection,
    schedule_date: &str,
) -> AppResult<Vec<ScheduleBlock>> {
    let mut stmt = conn
        .prepare_cached(
            "SELECT block_type, start_time, end_time, task_id, event_id, title \
             FROM focus_schedule_blocks WHERE schedule_date = ?1 ORDER BY position ASC",
        )
        .map_err(AppError::from)?;
    let mut rows = stmt.query(params![schedule_date]).map_err(AppError::from)?;
    let mut blocks = Vec::new();

    while let Some(row) = rows.next().map_err(AppError::from)? {
        let block_type_raw: String = row.get(0).map_err(AppError::from)?;
        let start_minutes: i64 = row.get(1).map_err(AppError::from)?;
        let end_minutes: i64 = row.get(2).map_err(AppError::from)?;
        let raw_task_id: Option<String> = row.get(3).map_err(AppError::from)?;

        // parse the block_type via the typed
        // `FocusBlockType` so an unknown wire value (a peer that
        // shipped a future variant ahead of us, or a corrupted
        // row) fails loudly instead of being silently rendered as
        // an `event` (the old `else` arm).
        let block_type = lorvex_domain::FocusBlockType::parse(&block_type_raw).ok_or_else(|| {
            AppError::Internal(format!(
                "Focus schedule block for '{schedule_date}' has unknown block_type '{block_type_raw}'"
            ))
        })?;

        let task_id = if block_type.requires_task_id() {
            match raw_task_id.filter(|id| !id.is_empty()) {
                Some(task_id) => Some(task_id),
                None => {
                    return Err(AppError::Internal(format!(
                        "Focus schedule task block for '{schedule_date}' is missing task_id"
                    )))
                }
            }
        } else {
            None
        };

        blocks.push(ScheduleBlock {
            block_type: block_type.as_str().to_string(),
            start_time: lorvex_domain::format_minutes_hhmm(start_minutes).ok_or_else(|| {
                AppError::Internal(format!(
                    "Focus schedule block has out-of-range start_time: {start_minutes}"
                ))
            })?,
            end_time: lorvex_domain::format_minutes_hhmm(end_minutes).ok_or_else(|| {
                AppError::Internal(format!(
                    "Focus schedule block has out-of-range end_time: {end_minutes}"
                ))
            })?,
            task_id,
            event_id: row.get(4).map_err(AppError::from)?,
            title: row.get(5).map_err(AppError::from)?,
        });
    }

    Ok(blocks)
}

pub(super) fn normalize_schedule_block_entries(
    blocks: &[ScheduleBlock],
) -> AppResult<Vec<lorvex_store::focus_schedule_blocks::ScheduleBlockEntry>> {
    blocks
        .iter()
        .map(|block| {
            let start_minutes = lorvex_domain::parse_hhmm_to_minutes(&block.start_time)
                .ok_or_else(|| {
                    AppError::Validation(format!(
                        "Invalid schedule block start_time '{}'. Expected HH:MM.",
                        block.start_time
                    ))
                })?;
            let end_minutes = lorvex_domain::parse_hhmm_to_minutes(&block.end_time)
                .ok_or_else(|| {
                    AppError::Validation(format!(
                        "Invalid schedule block end_time '{}'. Expected HH:MM.",
                        block.end_time
                    ))
                })?;
            if end_minutes <= start_minutes {
                return Err(AppError::Validation(format!(
                    "Invalid schedule block range '{}'-'{}'. end_time must be later than start_time.",
                    block.start_time, block.end_time
                )));
            }

            // Parse `block_type` at the IPC boundary into the closed
            // `FocusBlockType` enum so an unknown string surfaces as a
            // validation error. A fall-through-to-default reader would
            // let a typo from the assistant or a future variant added
            // to the writer path silently land in SQLite.
            let typed_block_type =
                lorvex_domain::FocusBlockType::parse(&block.block_type).ok_or_else(|| {
                    AppError::Validation(format!(
                        "Unknown schedule block_type '{}'. Expected one of: task, buffer, event.",
                        block.block_type
                    ))
                })?;
            let task_id = if typed_block_type.requires_task_id() {
                match block.task_id.as_ref().filter(|id| !id.is_empty()) {
                    Some(task_id) => Some(task_id.clone()),
                    None => {
                        return Err(AppError::Validation(
                            "Task schedule blocks require task_id".to_string(),
                        ))
                    }
                }
            } else {
                None
            };

            Ok(lorvex_store::focus_schedule_blocks::ScheduleBlockEntry {
                block_type: typed_block_type.as_str().to_string(),
                start_minutes,
                end_minutes,
                task_id,
                event_id: block.event_id.clone(),
                title: block.title.clone(),
            })
        })
        .collect()
}

/// Shape-check every block-carried UUID at the IPC boundary before
/// opening the writer transaction. Without this gate a malformed
/// `task_id` or `event_id` would flow into the materialize/enqueue
/// pipeline and surface only as an opaque sync-apply mismatch on a
/// peer device. Matches the validation pattern used by sibling
/// task-id IPC handlers. `event_id` carries calendar-event ids and is
/// validated the same way. Empty-string ids on non-task blocks are
/// normalized later, so the validator is skipped for those (an empty
/// `task_id` on a `task` block is rejected by
/// `normalize_schedule_block_entries` with a dedicated message).
pub(crate) fn validate_schedule_block_ids(blocks: &mut [ScheduleBlock]) -> Result<(), String> {
    for block in blocks.iter_mut() {
        if let Some(task_id) = block.task_id.as_ref() {
            if !task_id.is_empty() {
                block.task_id = Some(crate::commands::shared::validate_uuid_id(
                    task_id, "task_id",
                )?);
            }
        }
        if let Some(event_id) = block.event_id.as_ref() {
            if !event_id.is_empty() {
                block.event_id = Some(crate::commands::shared::validate_uuid_id(
                    event_id, "event_id",
                )?);
            }
        }
    }
    Ok(())
}
