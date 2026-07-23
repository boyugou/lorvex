//! CREATE — insert a new task row.
//!
//! Owns the [`TaskCreateParams`] carrier, its fluent
//! [`TaskCreateParamsBuilder`], and the canonical [`create_task`] INSERT
//! used by both MCP (full create) and Tauri (quick capture).

use rusqlite::{params, Connection};

use crate::error::StoreError;
use crate::repositories::task::read::{task_from_row, TaskRow, TASK_COLUMNS};

/// Parameters for creating a new task row. Most fields are optional; callers
/// populate the subset relevant to their write surface (MCP full-create vs
/// Tauri quick-capture).
///
/// Fields are crate-private — public construction goes exclusively through
/// the fluent [`TaskCreateParams::builder`] API. The builder requires the
/// five truly mandatory positional fields (`id`, `title`, `status`,
/// `version`, `now`) up front and exposes named-method setters for every
/// optional field, so call sites read as self-documenting chains rather
/// than `..Default::default()` heaps. See [`TaskCreateParamsBuilder`].
#[derive(Debug, Clone)]
pub struct TaskCreateParams<'a> {
    pub(crate) id: &'a str,
    pub(crate) title: &'a str,
    pub(crate) body: Option<&'a str>,
    pub(crate) raw_input: Option<&'a str>,
    pub(crate) ai_notes: Option<&'a str>,
    pub(crate) status: &'a str,
    pub(crate) list_id: Option<&'a str>,
    pub(crate) priority: Option<i64>,
    pub(crate) due_date: Option<&'a str>,
    pub(crate) due_time: Option<&'a str>,
    pub(crate) estimated_minutes: Option<i64>,
    pub(crate) recurrence: Option<&'a str>,
    pub(crate) recurrence_group_id: Option<&'a str>,
    pub(crate) canonical_occurrence_date: Option<&'a str>,
    pub(crate) planned_date: Option<&'a str>,
    pub(crate) version: &'a str,
    pub(crate) now: &'a str,
}

impl<'a> TaskCreateParams<'a> {
    /// Entry point for constructing [`TaskCreateParams`] via the fluent
    /// builder API. The five required fields are passed positionally so
    /// the type system enforces their presence; every optional field is
    /// set via a named setter on the returned [`TaskCreateParamsBuilder`].
    ///
    /// # Example
    ///
    /// ```ignore
    /// let params = TaskCreateParams::builder("t1", "Buy milk", "open", "v1", "2026-04-01T00:00:00Z")
    ///     .body(Some("with oat"))
    ///     .priority(Some(2))
    ///     .build()?;
    /// ```
    pub const fn builder(
        id: &'a str,
        title: &'a str,
        status: &'a str,
        version: &'a str,
        now: &'a str,
    ) -> TaskCreateParamsBuilder<'a> {
        TaskCreateParamsBuilder {
            id,
            title,
            status,
            version,
            now,
            body: None,
            raw_input: None,
            ai_notes: None,
            list_id: None,
            priority: None,
            due_date: None,
            due_time: None,
            estimated_minutes: None,
            recurrence: None,
            recurrence_group_id: None,
            canonical_occurrence_date: None,
            planned_date: None,
        }
    }
}

/// Fluent builder for [`TaskCreateParams`]. Construct via
/// [`TaskCreateParams::builder`] and finalize with
/// [`TaskCreateParamsBuilder::build`] — the latter centralizes per-field
/// validation (priority range, estimated/actual minutes range, date /
/// time format) in one place so each call site does not have to ship
/// its own if-statements.
#[derive(Debug, Clone)]
#[must_use = "TaskCreateParamsBuilder must be finalized with `.build()`"]
pub struct TaskCreateParamsBuilder<'a> {
    id: &'a str,
    title: &'a str,
    status: &'a str,
    version: &'a str,
    now: &'a str,
    body: Option<&'a str>,
    raw_input: Option<&'a str>,
    ai_notes: Option<&'a str>,
    list_id: Option<&'a str>,
    priority: Option<i64>,
    due_date: Option<&'a str>,
    due_time: Option<&'a str>,
    estimated_minutes: Option<i64>,
    recurrence: Option<&'a str>,
    recurrence_group_id: Option<&'a str>,
    canonical_occurrence_date: Option<&'a str>,
    planned_date: Option<&'a str>,
}

impl<'a> TaskCreateParamsBuilder<'a> {
    /// Set the optional task body (long-form description).
    pub const fn body(mut self, value: Option<&'a str>) -> Self {
        self.body = value;
        self
    }

    /// Set the optional raw input string (the verbatim user/AI utterance
    /// captured before normalization).
    pub const fn raw_input(mut self, value: Option<&'a str>) -> Self {
        self.raw_input = value;
        self
    }

    /// Set the optional AI notes column (assistant-authored commentary).
    pub const fn ai_notes(mut self, value: Option<&'a str>) -> Self {
        self.ai_notes = value;
        self
    }

    /// Set the parent list id. When `None`, [`create_task`] defaults to
    /// the schema-seeded [`INBOX_LIST_ID`] list.
    pub const fn list_id(mut self, value: Option<&'a str>) -> Self {
        self.list_id = value;
        self
    }

    /// Set the optional priority. Validated at [`Self::build`] against
    /// the canonical priority range.
    pub const fn priority(mut self, value: Option<i64>) -> Self {
        self.priority = value;
        self
    }

    /// Set the optional due-date column (YYYY-MM-DD). Validated at
    /// [`Self::build`] for shape.
    pub const fn due_date(mut self, value: Option<&'a str>) -> Self {
        self.due_date = value;
        self
    }

    /// Set the optional due-time column (HH:MM). Validated at
    /// [`Self::build`] for shape.
    pub const fn due_time(mut self, value: Option<&'a str>) -> Self {
        self.due_time = value;
        self
    }

    /// Set the optional `estimated_minutes` column. Validated at
    /// [`Self::build`] against `1..=MAX_ESTIMATED_MINUTES`.
    pub const fn estimated_minutes(mut self, value: Option<i64>) -> Self {
        self.estimated_minutes = value;
        self
    }

    /// Set the optional recurrence rule (canonical RRULE-like JSON
    /// string, normalized upstream).
    pub const fn recurrence(mut self, value: Option<&'a str>) -> Self {
        self.recurrence = value;
        self
    }

    /// Set the recurrence-series group id (shared across all instances
    /// of the same recurring series).
    pub const fn recurrence_group_id(mut self, value: Option<&'a str>) -> Self {
        self.recurrence_group_id = value;
        self
    }

    /// Set the canonical occurrence date for a recurring series anchor.
    pub const fn canonical_occurrence_date(mut self, value: Option<&'a str>) -> Self {
        self.canonical_occurrence_date = value;
        self
    }

    /// Set the optional `planned_date` (the AI-scheduled execution date,
    /// distinct from `due_date`). Validated at [`Self::build`] for shape.
    pub const fn planned_date(mut self, value: Option<&'a str>) -> Self {
        self.planned_date = value;
        self
    }

    /// Finalize the builder into a [`TaskCreateParams`], running
    /// per-field validation in one place so individual call sites do
    /// not have to repeat each check:
    ///
    /// * `priority` — must be in `PRIORITY_MIN..=PRIORITY_MAX`.
    /// * `estimated_minutes` — must be in `1..=MAX_ESTIMATED_MINUTES`.
    /// * `due_date`, `planned_date`, `canonical_occurrence_date` — must
    ///   parse as YYYY-MM-DD.
    /// * `due_time` — must parse as HH:MM.
    ///
    /// [`PRIORITY_MIN`]: lorvex_domain::validation::PRIORITY_MIN
    pub fn build(self) -> Result<TaskCreateParams<'a>, StoreError> {
        if let Some(p) = self.priority {
            lorvex_domain::validation::validate_priority(p)?;
        }
        if let Some(m) = self.estimated_minutes {
            lorvex_domain::validation::validate_estimated_minutes(m)?;
        }
        if let Some(d) = self.due_date {
            lorvex_domain::validation::validate_date_format(d)?;
        }
        lorvex_domain::time::DueAt::from_optional_str_pair(self.due_date, self.due_time)?;
        if let Some(d) = self.planned_date {
            lorvex_domain::validation::validate_date_format(d)?;
        }
        if let Some(d) = self.canonical_occurrence_date {
            lorvex_domain::validation::validate_date_format(d)?;
        }
        Ok(TaskCreateParams {
            id: self.id,
            title: self.title,
            body: self.body,
            raw_input: self.raw_input,
            ai_notes: self.ai_notes,
            status: self.status,
            list_id: self.list_id,
            priority: self.priority,
            due_date: self.due_date,
            due_time: self.due_time,
            estimated_minutes: self.estimated_minutes,
            recurrence: self.recurrence,
            recurrence_group_id: self.recurrence_group_id,
            canonical_occurrence_date: self.canonical_occurrence_date,
            planned_date: self.planned_date,
            version: self.version,
            now: self.now,
        })
    }
}

/// Well-known ID for the default Inbox list seeded in every fresh database.
pub const INBOX_LIST_ID: &str = "inbox";

/// Insert a new task row and return the inserted [`TaskRow`]. This is
/// the single canonical INSERT used by both MCP (full create) and
/// Tauri (quick capture). Tags and dependencies are handled
/// separately by the caller after this function returns.
///
/// If `list_id` is `None`, defaults to the schema-seeded `"inbox"` list.
///
/// Returns the inserted row directly so callers don't need to
/// re-fetch with [`crate::repositories::task::read::get_task`] just to
/// expose the canonical `created_at` / `updated_at` / `priority_effective`
/// the schema computes. A `Result<(), _>` shape would force every caller
/// into an extra round-trip and risk fetching a stale row if a
/// sibling writer slipped between INSERT and SELECT. Aligns the
/// create-shape with `list_repo::create_list`, which also returns
/// the inserted row.
pub fn create_task(
    conn: &Connection,
    params: &TaskCreateParams<'_>,
) -> Result<TaskRow, StoreError> {
    let resolved_list_id = params.list_id.unwrap_or(INBOX_LIST_ID);
    // RETURNING the inserted row in a single round-trip avoids the
    // extra `get_task()` SELECT that a two-statement create would
    // pay per insert. Halves the writer-mutex hold time on the MCP
    // create hot path (#3366). Reuses the canonical `TASK_COLUMNS` projection
    // and `task_from_row` mapper so any future column additions flow
    // through one place.
    let sql = format!(
        "INSERT INTO tasks \
         (id, title, body, raw_input, ai_notes, status, list_id, priority, \
          due_date, due_time, estimated_minutes, \
          recurrence, recurrence_group_id, canonical_occurrence_date, \
          planned_date, version, created_at, updated_at, \
          completed_at, last_deferred_at, defer_count) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, \
                 ?12, ?13, ?14, ?15, ?16, ?17, ?17, NULL, NULL, 0) \
         RETURNING {TASK_COLUMNS}"
    );
    let row = conn.prepare_cached(&sql)?.query_row(
        params![
            params.id,
            params.title,
            params.body,
            params.raw_input,
            params.ai_notes,
            params.status,
            resolved_list_id,
            params.priority,
            params.due_date,
            params.due_time,
            params.estimated_minutes,
            params.recurrence,
            params.recurrence_group_id,
            params.canonical_occurrence_date,
            params.planned_date,
            params.version,
            params.now,
        ],
        task_from_row,
    )?;
    Ok(row)
}
