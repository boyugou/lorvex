use std::collections::HashSet;

use crate::export::VersionedExportRecord;
use lorvex_domain::naming::{
    EntityKind, ENTITY_CALENDAR_EVENT, ENTITY_HABIT, ENTITY_LIST, ENTITY_TAG, ENTITY_TASK,
};

use crate::import::apply::optional_string_field;
use crate::import::ImportError;

#[derive(Default)]
pub(super) struct ScopedArchiveIndex {
    pub(super) lists: HashSet<String>,
    pub(super) tasks: HashSet<String>,
    pub(super) tags: HashSet<String>,
    pub(super) habits: HashSet<String>,
    pub(super) calendar_events: HashSet<String>,
}

impl ScopedArchiveIndex {
    pub(super) fn contains(&self, entity_type: &str, id: &str) -> bool {
        match entity_type {
            ENTITY_LIST => self.lists.contains(id),
            ENTITY_TASK => self.tasks.contains(id),
            ENTITY_TAG => self.tags.contains(id),
            ENTITY_HABIT => self.habits.contains(id),
            ENTITY_CALENDAR_EVENT => self.calendar_events.contains(id),
            _ => false,
        }
    }
}

pub(super) fn build_scoped_archive_index(
    entities: &[VersionedExportRecord],
) -> Result<ScopedArchiveIndex, ImportError> {
    let mut index = ScopedArchiveIndex::default();
    for record in entities {
        let payload = &record.payload;
        // Typed `EntityKind` dispatch. Out-of-stream kinds cannot reach
        // committed apply without failing later, but the scoped index only
        // records archive roots that can seed dependency closure.
        match record.entity_type {
            EntityKind::List => {
                if let Some(id) = optional_string_field(payload, "id", "list payload")? {
                    index.lists.insert(id);
                }
            }
            EntityKind::Task => {
                if let Some(id) = optional_string_field(payload, "id", "task payload")? {
                    index.tasks.insert(id);
                }
            }
            EntityKind::Tag => {
                if let Some(id) = optional_string_field(payload, "id", "tag payload")? {
                    index.tags.insert(id);
                }
            }
            EntityKind::Habit => {
                if let Some(id) = optional_string_field(payload, "id", "habit payload")? {
                    index.habits.insert(id);
                }
            }
            EntityKind::CalendarEvent => {
                if let Some(id) = optional_string_field(payload, "id", "calendar_event payload")? {
                    index.calendar_events.insert(id);
                }
            }
            _ => {}
        }
    }
    Ok(index)
}
