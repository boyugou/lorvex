//! Recurrence-related fields for a task. See [`crate::repositories::task::read::TaskRow`].

/// Recurrence-related fields for a task. See [`crate::repositories::task::read::TaskRow`].
///
/// `canonical_occurrence_date` uses the typed [`lorvex_domain::time::Date`] newtype so the
/// `YYYY-MM-DD` schema invariant is type-system enforced. Wire format
/// is unchanged because the newtype serializes transparently.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TaskRecurrenceState {
    pub(crate) recurrence: Option<String>,
    pub(crate) recurrence_exceptions: Option<String>,
    pub(crate) spawned_from: Option<String>,
    pub(crate) recurrence_group_id: Option<String>,
    pub(crate) canonical_occurrence_date: Option<lorvex_domain::time::Date>,
    pub(crate) recurrence_instance_key: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct TaskRecurrenceStateFields {
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
    pub spawned_from: Option<String>,
    pub recurrence_group_id: Option<String>,
    pub canonical_occurrence_date: Option<lorvex_domain::time::Date>,
    pub recurrence_instance_key: Option<String>,
}

impl TaskRecurrenceState {
    pub fn new(fields: TaskRecurrenceStateFields) -> Self {
        Self {
            recurrence: fields.recurrence,
            recurrence_exceptions: fields.recurrence_exceptions,
            spawned_from: fields.spawned_from,
            recurrence_group_id: fields.recurrence_group_id,
            canonical_occurrence_date: fields.canonical_occurrence_date,
            recurrence_instance_key: fields.recurrence_instance_key,
        }
    }

    pub fn recurrence(&self) -> Option<&str> {
        self.recurrence.as_deref()
    }
    pub fn recurrence_exceptions(&self) -> Option<&str> {
        self.recurrence_exceptions.as_deref()
    }
    pub fn spawned_from(&self) -> Option<&str> {
        self.spawned_from.as_deref()
    }
    pub fn recurrence_group_id(&self) -> Option<&str> {
        self.recurrence_group_id.as_deref()
    }
    pub const fn canonical_occurrence_date(&self) -> Option<lorvex_domain::time::Date> {
        self.canonical_occurrence_date
    }
    pub fn recurrence_instance_key(&self) -> Option<&str> {
        self.recurrence_instance_key.as_deref()
    }

    pub fn into_fields(self) -> TaskRecurrenceStateFields {
        TaskRecurrenceStateFields {
            recurrence: self.recurrence,
            recurrence_exceptions: self.recurrence_exceptions,
            spawned_from: self.spawned_from,
            recurrence_group_id: self.recurrence_group_id,
            canonical_occurrence_date: self.canonical_occurrence_date,
            recurrence_instance_key: self.recurrence_instance_key,
        }
    }
}
