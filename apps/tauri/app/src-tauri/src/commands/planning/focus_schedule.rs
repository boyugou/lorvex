use lorvex_domain::naming::{ENTITY_FOCUS_SCHEDULE, OP_DELETE, OP_UPSERT};

use super::*;
use crate::commands::sync_timestamp_now;
use crate::error::{AppError, AppResult};
use crate::event_bus;

mod blocks;
pub(crate) mod dismiss;
pub(crate) mod read;
mod sync;
#[cfg(test)]
mod tests;
pub(crate) mod write;

pub use dismiss::dismiss_focus_schedule;
pub use read::get_focus_schedule;
pub use write::update_focus_schedule_blocks;

#[cfg(test)]
use blocks::{normalize_schedule_block_entries, validate_schedule_block_ids};
#[cfg(test)]
use dismiss::dismiss_focus_schedule_with_conn;
#[cfg(test)]
use read::get_focus_schedule_with_conn;
#[cfg(test)]
use write::update_focus_schedule_blocks_with_conn;
