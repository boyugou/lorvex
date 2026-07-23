//! Scheduling fields for a task — when it is planned, deferred, estimated.
//! See [`crate::repositories::task::read::TaskRow`].

/// Scheduling fields for a task — when it is planned, deferred, estimated. See [`crate::repositories::task::read::TaskRow`].
///
/// The (`due_date`, `due_time`) pair flows as a single typed
/// [`DueAt`](lorvex_domain::time::DueAt) carrier so the implicit
/// invariant — a `due_time` without a `due_date` is invalid — is
/// type-system enforced rather than re-checked at every call site.
/// Wire format is preserved by the [`DueAtFlat`](lorvex_domain::time::DueAtFlat)
/// adapter, which `#[serde(flatten)]`s back into the legacy two
/// flat keys (`due_date`, `due_time`) so on-disk `payload_shadow`
/// JSON and cross-peer apply continue to read byte-identical rows.
/// `planned_date` uses the typed [`Date`](lorvex_domain::time::Date)
/// newtype.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TaskScheduling {
    #[serde(
        flatten,
        serialize_with = "serialize_due_as_flat",
        deserialize_with = "deserialize_due_from_flat"
    )]
    pub(crate) due: lorvex_domain::time::DueAt,
    pub(crate) estimated_minutes: Option<i64>,
    pub(crate) planned_date: Option<lorvex_domain::time::Date>,
    /// Defer-until date: the task is hidden from active lanes until this
    /// date (unless overdue). `None` = always visible. Serializes as the
    /// flat `available_from` key (null when absent), mirroring
    /// `planned_date`, so the present/absent sync contract holds.
    pub(crate) available_from: Option<lorvex_domain::time::Date>,
    pub(crate) defer_count: i64,
    pub(crate) last_deferred_at: Option<String>,
    pub(crate) last_defer_reason: Option<String>,
}

fn serialize_due_as_flat<S>(
    due: &lorvex_domain::time::DueAt,
    serializer: S,
) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    let flat = lorvex_domain::time::DueAtFlat::from(*due);
    serde::Serialize::serialize(&flat, serializer)
}

/// Mirror of [`serialize_due_as_flat`]. Reads the two flat keys
/// (`due_date`, `due_time`) via [`DueAtFlat`] and routes them through
/// [`DueAt::from_optional_pair`] so the `(None, Some)` invariant
/// violation surfaces as a deserialize error at the wire boundary —
/// the same shape `DueAtFlat::TryFrom` enforces.
fn deserialize_due_from_flat<'de, D>(
    deserializer: D,
) -> Result<lorvex_domain::time::DueAt, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let flat = <lorvex_domain::time::DueAtFlat as serde::Deserialize>::deserialize(deserializer)?;
    lorvex_domain::time::DueAt::try_from(flat).map_err(serde::de::Error::custom)
}

/// Owned-field bundle accepted by [`TaskScheduling::new`].
#[derive(Debug, Clone, Default)]
pub struct TaskSchedulingFields {
    pub due: lorvex_domain::time::DueAt,
    pub estimated_minutes: Option<i64>,
    pub planned_date: Option<lorvex_domain::time::Date>,
    pub available_from: Option<lorvex_domain::time::Date>,
    pub defer_count: i64,
    pub last_deferred_at: Option<String>,
    pub last_defer_reason: Option<String>,
}

impl TaskScheduling {
    pub fn new(fields: TaskSchedulingFields) -> Self {
        debug_assert!(
            fields.defer_count >= 0,
            "TaskScheduling.defer_count must be non-negative"
        );
        Self {
            due: fields.due,
            estimated_minutes: fields.estimated_minutes,
            planned_date: fields.planned_date,
            available_from: fields.available_from,
            defer_count: fields.defer_count,
            last_deferred_at: fields.last_deferred_at,
            last_defer_reason: fields.last_defer_reason,
        }
    }

    /// The full typed due-moment carrier. Use this when matching on
    /// the three valid shapes (Unscheduled / OnDay / AtMoment); use
    /// the legacy [`Self::due_date`] / [`Self::due_time`] accessors
    /// when bridging into a SQL bind site or wire-format slot that
    /// still expects the flat pair.
    pub const fn due(&self) -> lorvex_domain::time::DueAt {
        self.due
    }
    pub const fn due_date(&self) -> Option<lorvex_domain::time::Date> {
        self.due.date()
    }
    pub const fn due_time(&self) -> Option<lorvex_domain::time::TimeOfDay> {
        self.due.time()
    }
    pub const fn estimated_minutes(&self) -> Option<i64> {
        self.estimated_minutes
    }
    pub const fn planned_date(&self) -> Option<lorvex_domain::time::Date> {
        self.planned_date
    }
    pub const fn available_from(&self) -> Option<lorvex_domain::time::Date> {
        self.available_from
    }
    pub const fn defer_count(&self) -> i64 {
        self.defer_count
    }
    pub fn last_deferred_at(&self) -> Option<&str> {
        self.last_deferred_at.as_deref()
    }
    pub fn last_defer_reason(&self) -> Option<&str> {
        self.last_defer_reason.as_deref()
    }

    pub fn into_fields(self) -> TaskSchedulingFields {
        TaskSchedulingFields {
            due: self.due,
            estimated_minutes: self.estimated_minutes,
            planned_date: self.planned_date,
            available_from: self.available_from,
            defer_count: self.defer_count,
            last_deferred_at: self.last_deferred_at,
            last_defer_reason: self.last_defer_reason,
        }
    }
}
