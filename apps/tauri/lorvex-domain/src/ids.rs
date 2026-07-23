//! Typed entity identifier newtypes.
//!
//! Every Lorvex entity kind (task, list, calendar event, tag, habit,
//! memory, reminder, checklist item) is identified by a UUIDv7 string
//! at the storage and wire layer. The newtypes in this module enforce
//! type discipline at the API boundary so that swapping two distinct
//! id kinds at a call site is a compile error rather than a silent
//! SQL miss or wrong-row update. The wrapper stays thin around the
//! canonical UUIDv7 string at the wire / schema layer:
//!
//! - `#[serde(transparent)]` so JSON / sync envelopes / MCP arg shapes
//!   keep encoding the id as a bare string.
//! - `as_str()` + `AsRef<str>` + `Display` so SQL bind sites and log
//!   strings stay ergonomic.
//! - `parse(s)` reuses the existing
//!   [`crate::entity_id::parse_id_with_sentinel`] contract so trust-
//!   boundary surfaces (Tauri IPC, MCP server, CLI) keep their unified
//!   trim / sentinel / UUID-shape rules.
//! - `new()` mints a fresh UUIDv7 via
//!   [`crate::entity_id::new_entity_id_string`].
//! - Optional `rusqlite::ToSql` / `FromSql` impls behind the `rusqlite`
//!   cargo feature so storage call sites in `lorvex-store` can bind a
//!   typed id directly into `params!` without going through `.as_str()`.
//!
//! ## Sentinels
//!
//! Some id kinds accept a single non-UUID sentinel value:
//! - `ListId::INBOX` (`"inbox"`) is the schema-seeded universal inbox
//!   list; it predates the UUID convention and lives forever.
//!
//! `ListId::parse` accepts the sentinel; the other id kinds reject any
//! non-UUID input.

use crate::entity_id::{new_entity_id_string, parse_id_with_sentinel};
use crate::validation::ValidationError;

/// Build a typed identifier newtype with a fixed field label used in
/// `ValidationError::InvalidFormat { field, .. }`.
///
/// `$sentinel` is `None` for kinds that always require a UUID-shaped
/// value, or `Some("…")` for kinds (currently only `ListId`) that
/// accept a single seeded sentinel.
macro_rules! impl_typed_id {
    ($name:ident, $field_label:literal, $sentinel:expr) => {
        #[doc = concat!("Typed identifier for the `", $field_label, "` column / field.")]
        ///
        /// Wire encoding: bare UUIDv7 string (or sentinel where supported).
        /// `serde` flattens the wrapper via `#[serde(transparent)]`, so
        /// JSON / sync envelopes / MCP arg shapes do not change.
        #[derive(Clone, Debug, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
        #[serde(transparent)]
        #[repr(transparent)]
        pub struct $name(String);

        impl $name {
            /// Mint a new id from a fresh UUIDv7.
            pub fn new() -> Self {
                Self(new_entity_id_string())
            }

            /// Parse an untrusted string at a trust boundary.
            ///
            /// Trims surrounding whitespace, accepts the configured
            /// sentinel (if any), and otherwise enforces UUID shape via
            /// [`parse_id_with_sentinel`]. The returned
            /// `ValidationError` carries the field label
            #[doc = concat!("`", $field_label, "`")]
            /// so caller surfaces can render
            /// caller-meaningful errors without rebuilding the message.
            pub fn parse(value: impl AsRef<str>) -> Result<Self, ValidationError> {
                parse_id_with_sentinel(value.as_ref(), $field_label, $sentinel).map(Self)
            }

            /// Borrow the canonical string representation.
            #[inline]
            pub fn as_str(&self) -> &str {
                &self.0
            }

            /// Consume the wrapper and return the canonical string.
            #[inline]
            pub fn into_string(self) -> String {
                self.0
            }

            /// Construct a typed id from an already-validated string
            /// without re-running the trust-boundary parser.
            ///
            /// Reserved for storage-layer reads (rusqlite row → newtype)
            /// and intra-process channels where the value has already
            /// crossed a `parse(…)` boundary. Trust-boundary surfaces
            /// MUST go through [`Self::parse`] to enforce trim /
            /// sentinel / UUID-shape rules.
            #[inline]
            pub const fn from_trusted(value: String) -> Self {
                Self(value)
            }

            /// Construct from a trusted `&str` without going through
            /// the call-site `.to_string()` dance.
            ///
            /// Folds the common
            /// `Self::from_trusted(s.to_string())` pair into a single
            /// typed-construction call so the call site reads as
            /// "borrow as a typed id" rather than "allocate, then
            /// re-borrow." A future zero-cost `&str → &Self` borrow
            /// requires reshaping the underlying storage from `String`
            /// to a `str` DST; today the wrapper still owns the
            /// allocation, but the call-site noise is gone.
            ///
            /// Same trust contract as [`Self::from_trusted`] — the
            /// caller must have already validated the value at a
            /// boundary; trust-boundary surfaces use [`Self::parse`].
            #[inline]
            #[must_use]
            pub fn from_trusted_str(value: &str) -> Self {
                Self(value.to_string())
            }
        }

        impl Default for $name {
            fn default() -> Self {
                Self::new()
            }
        }

        impl AsRef<str> for $name {
            #[inline]
            fn as_ref(&self) -> &str {
                &self.0
            }
        }

        impl std::fmt::Display for $name {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str(&self.0)
            }
        }

        impl From<$name> for String {
            #[inline]
            fn from(id: $name) -> String {
                id.0
            }
        }

        // Convenience: allow comparing a typed id against a raw string
        // slice in tests and log assertions without unwrapping.
        impl PartialEq<str> for $name {
            #[inline]
            fn eq(&self, other: &str) -> bool {
                self.0 == other
            }
        }

        impl PartialEq<&str> for $name {
            #[inline]
            fn eq(&self, other: &&str) -> bool {
                self.0 == *other
            }
        }

        #[cfg(feature = "rusqlite")]
        impl rusqlite::ToSql for $name {
            #[inline]
            fn to_sql(&self) -> rusqlite::Result<rusqlite::types::ToSqlOutput<'_>> {
                self.0.to_sql()
            }
        }

        #[cfg(feature = "rusqlite")]
        impl rusqlite::types::FromSql for $name {
            #[inline]
            fn column_result(
                value: rusqlite::types::ValueRef<'_>,
            ) -> rusqlite::types::FromSqlResult<Self> {
                String::column_result(value).map(Self)
            }
        }
    };
}

// One id newtype per entity kind. The field labels match the column
// names used in the schema and the parameter names used across the
// repositories so `ValidationError::InvalidFormat { field, .. }`
// surfaces the same caller-meaningful label callers expected before
// the typed migration.
impl_typed_id!(TaskId, "task_id", None);
impl_typed_id!(ListId, "list_id", Some(ListId::INBOX_SENTINEL));
impl_typed_id!(EventId, "event_id", None);
impl_typed_id!(TagId, "tag_id", None);
impl_typed_id!(HabitId, "habit_id", None);
impl_typed_id!(MemoryKey, "memory_key", None);
impl_typed_id!(ReminderId, "reminder_id", None);
impl_typed_id!(ChecklistItemId, "checklist_item_id", None);
impl_typed_id!(HabitReminderPolicyId, "habit_reminder_policy_id", None);
impl_typed_id!(MemoryRevisionId, "memory_revision_id", None);

impl ListId {
    /// Sentinel value for the schema-seeded universal inbox list.
    ///
    /// This predates the UUID convention and remains a non-UUID string
    /// because every install ships with one inbox row at this fixed id;
    /// migrating it to a UUID would force every existing database to
    /// rewrite every `tasks.list_id = 'inbox'` reference.
    const INBOX_SENTINEL: &'static str = "inbox";

    /// The inbox sentinel as a typed `ListId`.
    pub fn inbox() -> Self {
        Self::from_trusted(Self::INBOX_SENTINEL.to_string())
    }
}

// ---------------------------------------------------------------------------
// Composite edge ids
// ---------------------------------------------------------------------------
//
// The `task_tags` and `task_dependencies` join tables key on a pair of
// task / tag ids; the outbox envelope and sync conflict log identify
// those rows with a composite `"left:right"` string. These newtypes
// own the encoding so call sites can't ad-hoc `format!("{a}:{b}")` an
// id with a colon-bearing payload (a malformed edge id never reaches
// the wire), and the parser is paired with the formatter so the two
// can never drift out of sync.

/// Error returned when a composite edge id is not of the form
/// `"<left_uuid>:<right_uuid>"`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompositeEdgeIdParseError {
    /// The composite id string that failed to parse.
    pub input: String,
    /// Human-readable reason for the failure.
    pub reason: &'static str,
}

impl std::fmt::Display for CompositeEdgeIdParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "composite edge id '{}' is invalid: {}",
            self.input, self.reason
        )
    }
}

impl std::error::Error for CompositeEdgeIdParseError {}

/// Composite id for a `task_tags` edge row.
///
/// Wire form is `"<task_id>:<tag_id>"` — the format the outbox envelope
/// stamps on `entity_id` for the `task_tag` edge channel. Construction
/// goes through [`Self::new`] so a bare `format!("{a}:{b}")` cannot
/// silently emit a malformed id, and [`Self::try_parse`] is the single
/// canonical decoder.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
#[repr(transparent)]
pub struct TaskTagEdgeId(String);

impl TaskTagEdgeId {
    /// Build the composite id from a typed task + tag pair.
    #[inline]
    #[must_use]
    pub fn new(task_id: &TaskId, tag_id: &TagId) -> Self {
        Self(format!("{}:{}", task_id.as_str(), tag_id.as_str()))
    }

    /// Borrow the wire-format `"task_id:tag_id"` string.
    #[inline]
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Consume the wrapper and return the wire string.
    #[inline]
    #[must_use]
    pub fn into_string(self) -> String {
        self.0
    }

    /// Decode a wire-form composite into the underlying typed pair.
    ///
    /// Validates the colon split shape only; the constituent ids are
    /// returned via [`TaskId::from_trusted`] / [`TagId::from_trusted`]
    /// because the caller is already past a sync-boundary parse for
    /// the parent envelope.
    pub fn try_parse(value: &str) -> Result<(TaskId, TagId), CompositeEdgeIdParseError> {
        let (left, right) = value
            .split_once(':')
            .ok_or_else(|| CompositeEdgeIdParseError {
                input: value.to_string(),
                reason: "expected '<task_id>:<tag_id>'",
            })?;
        if left.is_empty() || right.is_empty() {
            return Err(CompositeEdgeIdParseError {
                input: value.to_string(),
                reason: "empty left or right half",
            });
        }
        Ok((
            TaskId::from_trusted(left.to_string()),
            TagId::from_trusted(right.to_string()),
        ))
    }
}

impl std::fmt::Display for TaskTagEdgeId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl AsRef<str> for TaskTagEdgeId {
    #[inline]
    fn as_ref(&self) -> &str {
        &self.0
    }
}

impl From<TaskTagEdgeId> for String {
    #[inline]
    fn from(id: TaskTagEdgeId) -> String {
        id.0
    }
}

/// Composite id for a `task_dependencies` edge row.
///
/// Wire form is `"<task_id>:<depends_on_task_id>"`. Same construction
/// + parse contract as [`TaskTagEdgeId`].
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
#[repr(transparent)]
pub struct TaskDependencyEdgeId(String);

impl TaskDependencyEdgeId {
    /// Build the composite id from a dependent + dependency pair.
    ///
    /// `task_id` is the row that depends on `depends_on_task_id`.
    #[inline]
    #[must_use]
    pub fn new(task_id: &TaskId, depends_on_task_id: &TaskId) -> Self {
        Self(format!(
            "{}:{}",
            task_id.as_str(),
            depends_on_task_id.as_str()
        ))
    }

    /// Borrow the wire-format `"task_id:depends_on_task_id"` string.
    #[inline]
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Consume the wrapper and return the wire string.
    #[inline]
    #[must_use]
    pub fn into_string(self) -> String {
        self.0
    }

    /// Decode a wire-form composite into the underlying typed pair.
    pub fn try_parse(value: &str) -> Result<(TaskId, TaskId), CompositeEdgeIdParseError> {
        let (left, right) = value
            .split_once(':')
            .ok_or_else(|| CompositeEdgeIdParseError {
                input: value.to_string(),
                reason: "expected '<task_id>:<depends_on_task_id>'",
            })?;
        if left.is_empty() || right.is_empty() {
            return Err(CompositeEdgeIdParseError {
                input: value.to_string(),
                reason: "empty left or right half",
            });
        }
        Ok((
            TaskId::from_trusted(left.to_string()),
            TaskId::from_trusted(right.to_string()),
        ))
    }
}

impl std::fmt::Display for TaskDependencyEdgeId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl AsRef<str> for TaskDependencyEdgeId {
    #[inline]
    fn as_ref(&self) -> &str {
        &self.0
    }
}

impl From<TaskDependencyEdgeId> for String {
    #[inline]
    fn from(id: TaskDependencyEdgeId) -> String {
        id.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID_V7: &str = "01966a3f-7c8b-7d4e-8f3a-000000000001";

    #[test]
    fn task_id_new_produces_uuid_shape() {
        let id = TaskId::new();
        assert_eq!(id.as_str().len(), 36);
        assert!(uuid::Uuid::parse_str(id.as_str()).is_ok());
    }

    #[test]
    fn task_id_parse_accepts_uuid() {
        let id = TaskId::parse(VALID_V7).unwrap();
        assert_eq!(id.as_str(), VALID_V7);
    }

    #[test]
    fn task_id_parse_trims_whitespace() {
        let padded = format!("  {VALID_V7}  ");
        let id = TaskId::parse(&padded).unwrap();
        assert_eq!(id.as_str(), VALID_V7);
    }

    #[test]
    fn task_id_parse_rejects_garbage_with_field_label() {
        let err = TaskId::parse("not-a-uuid").unwrap_err();
        match err {
            ValidationError::InvalidFormat { field, actual, .. } => {
                assert_eq!(field, "task_id");
                assert_eq!(actual, "not-a-uuid");
            }
            other => panic!("expected InvalidFormat, got {other:?}"),
        }
    }

    #[test]
    fn task_id_parse_rejects_empty() {
        assert!(matches!(
            TaskId::parse("   ").unwrap_err(),
            ValidationError::Empty("task_id")
        ));
    }

    #[test]
    fn list_id_accepts_inbox_sentinel() {
        let id = ListId::parse("inbox").unwrap();
        assert_eq!(id.as_str(), "inbox");
        assert_eq!(ListId::inbox(), id);
    }

    #[test]
    fn list_id_inbox_sentinel_trims() {
        let id = ListId::parse("  inbox  ").unwrap();
        assert_eq!(id, ListId::inbox());
    }

    #[test]
    fn list_id_does_not_accept_inbox_for_other_kinds() {
        // The sentinel is list-specific; task ids must always be UUIDs.
        assert!(matches!(
            TaskId::parse("inbox").unwrap_err(),
            ValidationError::InvalidFormat { .. }
        ));
    }

    #[test]
    fn event_tag_habit_memory_reminder_checklist_parse_uuid() {
        for parsed in [
            EventId::parse(VALID_V7).map(EventId::into_string),
            TagId::parse(VALID_V7).map(TagId::into_string),
            HabitId::parse(VALID_V7).map(HabitId::into_string),
            MemoryKey::parse(VALID_V7).map(MemoryKey::into_string),
            ReminderId::parse(VALID_V7).map(ReminderId::into_string),
            ChecklistItemId::parse(VALID_V7).map(ChecklistItemId::into_string),
        ] {
            assert_eq!(parsed.unwrap(), VALID_V7);
        }
    }

    #[test]
    fn serde_round_trips_as_bare_string() {
        let id = TaskId::parse(VALID_V7).unwrap();
        let json = serde_json::to_string(&id).unwrap();
        // `#[serde(transparent)]` → encodes as a JSON string, NOT
        // `{"0": "..."}` — wire format must stay byte-identical.
        assert_eq!(json, format!("\"{VALID_V7}\""));
        let round_trip: TaskId = serde_json::from_str(&json).unwrap();
        assert_eq!(round_trip, id);
    }

    #[test]
    fn into_string_returns_canonical() {
        let id = TaskId::parse(VALID_V7).unwrap();
        let s: String = id.into_string();
        assert_eq!(s, VALID_V7);
    }

    #[test]
    fn task_tag_edge_id_round_trip() {
        let task = TaskId::from_trusted(VALID_V7.to_string());
        let tag = TagId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000002".to_string());
        let edge = TaskTagEdgeId::new(&task, &tag);
        assert_eq!(
            edge.as_str(),
            "01966a3f-7c8b-7d4e-8f3a-000000000001:01966a3f-7c8b-7d4e-8f3a-000000000002"
        );
        let (parsed_task, parsed_tag) = TaskTagEdgeId::try_parse(edge.as_str()).unwrap();
        assert_eq!(parsed_task.as_str(), task.as_str());
        assert_eq!(parsed_tag.as_str(), tag.as_str());
    }

    #[test]
    fn task_dependency_edge_id_round_trip() {
        let task = TaskId::from_trusted(VALID_V7.to_string());
        let dep = TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000003".to_string());
        let edge = TaskDependencyEdgeId::new(&task, &dep);
        let (parsed_task, parsed_dep) = TaskDependencyEdgeId::try_parse(edge.as_str()).unwrap();
        assert_eq!(parsed_task.as_str(), task.as_str());
        assert_eq!(parsed_dep.as_str(), dep.as_str());
    }

    #[test]
    fn task_tag_edge_id_rejects_malformed() {
        assert!(TaskTagEdgeId::try_parse("no-colon").is_err());
        assert!(TaskTagEdgeId::try_parse(":right").is_err());
        assert!(TaskTagEdgeId::try_parse("left:").is_err());
    }

    #[test]
    fn from_trusted_str_matches_from_trusted() {
        let from_str = TaskId::from_trusted_str(VALID_V7);
        let from_owned = TaskId::from_trusted(VALID_V7.to_string());
        assert_eq!(from_str, from_owned);
    }

    #[test]
    fn from_trusted_skips_validation() {
        // Storage-layer reads rely on this contract: rows already in
        // the DB went through a parse boundary on insert, so we don't
        // re-run UUID-shape validation on every read.
        let id = TaskId::from_trusted("not-a-uuid".to_string());
        assert_eq!(id.as_str(), "not-a-uuid");
    }

    #[test]
    fn distinct_kinds_do_not_unify_at_compile_time() {
        // Compile-time guarantee: the whole point of the migration.
        // A function that demands `&TaskId` rejects a `&ListId` at
        // build time. We can't write a negative compile test in
        // a unit test, but we can pin the runtime equality semantics
        // — two different newtypes never compare equal, even when the
        // underlying strings match — and rely on rustc to enforce the
        // type-distinction half.
        let task = TaskId::parse(VALID_V7).unwrap();
        let list = ListId::parse(VALID_V7).unwrap();
        // PartialEq is only defined for `(TaskId, TaskId)` etc., so
        // `task == list` would be a compile error. Compare via
        // `as_str()` to demonstrate the shared underlying value:
        assert_eq!(task.as_str(), list.as_str());
    }
}
