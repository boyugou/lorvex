//! Shared test fixture builders.
//!
//! [`TaskBuilder`] is the single source of truth for "insert a minimal
//! task row good enough for downstream tests." Per-test
//! `seed_task` / `insert_test_task` helpers would each open-code the
//! same `INSERT INTO tasks (...)` shape with slightly different
//! column lists, `version` strings, and timestamp literals — and
//! every schema change would ripple through ~30 files because each
//! helper would have to be touched independently. Callers tweak only what
//! they care about (status, list_id, title, archived_at, planned_date,
//! due_date) and let the builder fill in the columns the schema requires
//! but the test does not care about (`version`, `created_at`,
//! `updated_at`). When a new NOT NULL column is added to the `tasks`
//! table, the migration code in this module is the only file that has
//! to change.

use rusqlite::Connection;

/// Default HLC `version` for seeded tasks. The all-zero physical-ms
/// stamp deliberately sorts below every real-device write so any
/// production-shaped envelope wins LWW comparisons against a seeded
/// row in tests that exercise the apply pipeline.
pub const SEED_TASK_VERSION: &str = "0000000000000_0000_0000000000000000";

/// Default `created_at` / `updated_at` for seeded tasks. A fixed past
/// date keeps test output deterministic and lets timestamp-sensitive
/// assertions (LWW, retention windows) compare against a known value.
pub const SEED_TASK_TIMESTAMP: &str = "2026-03-20T00:00:00.000Z";

/// Builder for inserting a minimal task row. Required columns
/// (`id`, `title`, `status`, `version`, `created_at`, `updated_at`)
/// have defaults; optional columns map to setter methods that take an
/// `Option`-shaped argument.
///
/// ```ignore
/// use lorvex_store::test_support::fixtures::TaskBuilder;
/// let conn = lorvex_store::test_support::test_conn();
/// TaskBuilder::new("task-1").title("Buy milk").insert(&conn);
/// ```
#[derive(Debug, Clone)]
pub struct TaskBuilder<'a> {
    id: &'a str,
    title: &'a str,
    status: &'a str,
    version: &'a str,
    created_at: &'a str,
    updated_at: &'a str,
    list_id: Option<&'a str>,
    body: Option<&'a str>,
    archived_at: Option<&'a str>,
    planned_date: Option<&'a str>,
    due_date: Option<&'a str>,
    due_time: Option<&'a str>,
    completed_at: Option<&'a str>,
    priority: Option<i64>,
    ai_notes: Option<&'a str>,
    defer_count: Option<i64>,
    recurrence: Option<&'a str>,
    recurrence_group_id: Option<&'a str>,
    recurrence_instance_key: Option<&'a str>,
    canonical_occurrence_date: Option<&'a str>,
    recurrence_exceptions: Option<&'a str>,
    spawned_from: Option<&'a str>,
}

impl<'a> TaskBuilder<'a> {
    /// Start a new builder. `id` is the only required argument; every
    /// other column has a sensible default for tests that exist solely
    /// to give other rows (edges, reminders, dependencies) a parent
    /// task to point at.
    pub const fn new(id: &'a str) -> Self {
        Self {
            id,
            title: "Seed Task",
            status: lorvex_domain::naming::STATUS_OPEN,
            version: SEED_TASK_VERSION,
            created_at: SEED_TASK_TIMESTAMP,
            updated_at: SEED_TASK_TIMESTAMP,
            list_id: None,
            body: None,
            archived_at: None,
            planned_date: None,
            due_date: None,
            due_time: None,
            completed_at: None,
            priority: None,
            ai_notes: None,
            defer_count: None,
            recurrence: None,
            recurrence_group_id: None,
            recurrence_instance_key: None,
            canonical_occurrence_date: None,
            recurrence_exceptions: None,
            spawned_from: None,
        }
    }

    pub const fn title(mut self, title: &'a str) -> Self {
        self.title = title;
        self
    }

    pub const fn status(mut self, status: &'a str) -> Self {
        self.status = status;
        self
    }

    pub const fn version(mut self, version: &'a str) -> Self {
        self.version = version;
        self
    }

    pub const fn created_at(mut self, created_at: &'a str) -> Self {
        self.created_at = created_at;
        self.updated_at = created_at;
        self
    }

    pub const fn updated_at(mut self, updated_at: &'a str) -> Self {
        self.updated_at = updated_at;
        self
    }

    pub const fn list_id(mut self, list_id: Option<&'a str>) -> Self {
        self.list_id = list_id;
        self
    }

    pub const fn body(mut self, body: Option<&'a str>) -> Self {
        self.body = body;
        self
    }

    pub const fn archived_at(mut self, archived_at: Option<&'a str>) -> Self {
        self.archived_at = archived_at;
        self
    }

    pub const fn planned_date(mut self, planned_date: Option<&'a str>) -> Self {
        self.planned_date = planned_date;
        self
    }

    pub const fn due_date(mut self, due_date: Option<&'a str>) -> Self {
        self.due_date = due_date;
        self
    }

    pub const fn completed_at(mut self, completed_at: Option<&'a str>) -> Self {
        self.completed_at = completed_at;
        self
    }

    pub const fn priority(mut self, priority: Option<i64>) -> Self {
        self.priority = priority;
        self
    }

    pub const fn due_time(mut self, due_time: Option<&'a str>) -> Self {
        self.due_time = due_time;
        self
    }

    pub const fn ai_notes(mut self, ai_notes: Option<&'a str>) -> Self {
        self.ai_notes = ai_notes;
        self
    }

    pub const fn defer_count(mut self, defer_count: i64) -> Self {
        self.defer_count = Some(defer_count);
        self
    }

    /// Set the RRULE string. The schema's `tasks` CHECK constraint
    /// requires `recurrence_group_id`, `canonical_occurrence_date`,
    /// AND `due_date` to also be set whenever `recurrence` is non-NULL
    /// — pair this setter with [`Self::recurrence_group_id`],
    /// [`Self::canonical_occurrence_date`], and [`Self::due_date`] or
    /// the INSERT will trip the CHECK with a non-obvious failure.
    pub const fn recurrence(mut self, rule: &'a str) -> Self {
        self.recurrence = Some(rule);
        self
    }

    pub const fn recurrence_group_id(mut self, group_id: &'a str) -> Self {
        self.recurrence_group_id = Some(group_id);
        self
    }

    pub const fn recurrence_instance_key(mut self, instance_key: &'a str) -> Self {
        self.recurrence_instance_key = Some(instance_key);
        self
    }

    /// Set the stable RRULE cadence anchor. Schema CHECK constraint
    /// requires this whenever `recurrence` is non-NULL — see the
    /// docstring on [`Self::recurrence`] for the full set of required
    /// companion fields.
    pub const fn canonical_occurrence_date(mut self, date: &'a str) -> Self {
        self.canonical_occurrence_date = Some(date);
        self
    }

    /// Set the recurrence-successor backreference. `spawned_from` is
    /// non-NULL on the successor row produced by `spawn_recurrence`
    /// and points at the parent's id; it stays NULL on independently
    /// authored tasks and on the parent itself.
    pub const fn spawned_from(mut self, spawned_from: &'a str) -> Self {
        self.spawned_from = Some(spawned_from);
        self
    }

    /// Set the EXDATE list (JSON array of YMD strings, e.g.
    /// `r#"["2026-04-05"]"#`). Independent of the schema CHECK
    /// constraint set documented on [`Self::recurrence`] —
    /// `recurrence_exceptions` is nullable and only meaningful when
    /// `recurrence` is also set.
    pub const fn recurrence_exceptions(mut self, json: &'a str) -> Self {
        self.recurrence_exceptions = Some(json);
        self
    }

    /// Execute the INSERT. Panics on rusqlite failure — this is a test
    /// helper, not a production writer; a failed seed indicates a
    /// schema or test-fixture bug, not a recoverable error.
    ///
    /// `list_id` is omitted from the column list when the caller
    /// didn't set one so the schema's `NOT NULL DEFAULT 'inbox'`
    /// kicks in — binding `NULL` explicitly would defeat the
    /// default and trip the NOT NULL constraint. The same applies to
    /// `defer_count` (`NOT NULL DEFAULT 0`).
    pub fn insert(self, conn: &Connection) {
        // build the column list dynamically so that a
        // caller who doesn't set `list_id` / `defer_count` falls
        // through to the SQL-side `NOT NULL DEFAULT` rather than
        // binding NULL and tripping the constraint.
        let mut cols: Vec<&'static str> = vec![
            "id",
            "title",
            "body",
            "status",
            "version",
            "created_at",
            "updated_at",
            "archived_at",
            "planned_date",
            "due_date",
            "due_time",
            "completed_at",
            "priority",
            "ai_notes",
            "recurrence",
            "recurrence_group_id",
            "recurrence_instance_key",
            "canonical_occurrence_date",
            "spawned_from",
        ];
        let mut binds: Vec<&dyn rusqlite::ToSql> = vec![
            &self.id,
            &self.title,
            &self.body,
            &self.status,
            &self.version,
            &self.created_at,
            &self.updated_at,
            &self.archived_at,
            &self.planned_date,
            &self.due_date,
            &self.due_time,
            &self.completed_at,
            &self.priority,
            &self.ai_notes,
            &self.recurrence,
            &self.recurrence_group_id,
            &self.recurrence_instance_key,
            &self.canonical_occurrence_date,
            &self.spawned_from,
        ];
        if let Some(list_id) = self.list_id.as_ref() {
            cols.push("list_id");
            binds.push(list_id);
        }
        if let Some(defer_count) = self.defer_count.as_ref() {
            cols.push("defer_count");
            binds.push(defer_count);
        }
        let placeholders: Vec<String> = (1..=cols.len()).map(|n| format!("?{n}")).collect();
        let sql = format!(
            "INSERT INTO tasks ({}) VALUES ({})",
            cols.join(", "),
            placeholders.join(", "),
        );
        conn.execute(&sql, rusqlite::params_from_iter(binds))
            .expect("TaskBuilder::insert: schema mismatch in test fixture");
        if let Some(json) = self.recurrence_exceptions {
            crate::recurrence_exceptions::replace_task_exceptions_from_json(
                conn,
                self.id,
                Some(json),
            )
            .expect("TaskBuilder::insert: seed recurrence_exceptions child rows");
        }
    }
}

/// Builder for inserting a minimal `lists` row. Mirrors [`TaskBuilder`]:
/// every required column has a default and optional columns map to
/// setter methods. Centralizing the `lists` insert closes the same
/// drift hazard the task fixture closed: pre-builder every test had its
/// own `INSERT INTO lists (id, name, version, created_at, updated_at)
/// VALUES …` statement, and a future schema column would need to be
/// applied in every fixture.
///
/// ```ignore
/// use lorvex_store::test_support::fixtures::ListBuilder;
/// let conn = lorvex_store::test_support::test_conn();
/// ListBuilder::new("list-1").name("Personal").insert(&conn);
/// ```
#[derive(Debug, Clone)]
pub struct ListBuilder<'a> {
    id: &'a str,
    name: &'a str,
    version: &'a str,
    created_at: &'a str,
    updated_at: &'a str,
    color: Option<&'a str>,
    icon: Option<&'a str>,
    description: Option<&'a str>,
    ai_notes: Option<&'a str>,
    /// When `Some(true)`, use `INSERT OR IGNORE` so the seed is a
    /// no-op against an already-seeded id. The migration baseline
    /// always seeds `'inbox'`, so most tests want
    /// `or_ignore(true)` when re-seeding it.
    or_ignore: bool,
}

impl<'a> ListBuilder<'a> {
    pub const fn new(id: &'a str) -> Self {
        Self {
            id,
            name: "Seed List",
            version: SEED_TASK_VERSION,
            created_at: SEED_TASK_TIMESTAMP,
            updated_at: SEED_TASK_TIMESTAMP,
            color: None,
            icon: None,
            description: None,
            ai_notes: None,
            or_ignore: false,
        }
    }

    pub const fn name(mut self, name: &'a str) -> Self {
        self.name = name;
        self
    }

    pub const fn version(mut self, version: &'a str) -> Self {
        self.version = version;
        self
    }

    pub const fn created_at(mut self, created_at: &'a str) -> Self {
        self.created_at = created_at;
        self.updated_at = created_at;
        self
    }

    pub const fn updated_at(mut self, updated_at: &'a str) -> Self {
        self.updated_at = updated_at;
        self
    }

    pub const fn color(mut self, color: Option<&'a str>) -> Self {
        self.color = color;
        self
    }

    pub const fn icon(mut self, icon: Option<&'a str>) -> Self {
        self.icon = icon;
        self
    }

    pub const fn description(mut self, description: Option<&'a str>) -> Self {
        self.description = description;
        self
    }

    pub const fn ai_notes(mut self, ai_notes: Option<&'a str>) -> Self {
        self.ai_notes = ai_notes;
        self
    }

    /// Switch the INSERT to `INSERT OR IGNORE` so the seed is a no-op
    /// against an already-seeded id. Useful when re-seeding `'inbox'`,
    /// which the migration baseline always seeds at first open.
    pub const fn or_ignore(mut self, or_ignore: bool) -> Self {
        self.or_ignore = or_ignore;
        self
    }

    /// Execute the INSERT. Panics on rusqlite failure — this is a
    /// test helper, not a production writer; a failed seed indicates
    /// a schema or test-fixture bug, not a recoverable error.
    pub fn insert(self, conn: &Connection) {
        let mut cols: Vec<&'static str> = vec!["id", "name", "version", "created_at", "updated_at"];
        let mut binds: Vec<&str> = vec![
            self.id,
            self.name,
            self.version,
            self.created_at,
            self.updated_at,
        ];
        if let Some(color) = self.color {
            cols.push("color");
            binds.push(color);
        }
        if let Some(icon) = self.icon {
            cols.push("icon");
            binds.push(icon);
        }
        if let Some(description) = self.description {
            cols.push("description");
            binds.push(description);
        }
        if let Some(ai_notes) = self.ai_notes {
            cols.push("ai_notes");
            binds.push(ai_notes);
        }
        let placeholders: Vec<String> = (1..=cols.len()).map(|n| format!("?{n}")).collect();
        let prefix = if self.or_ignore {
            "INSERT OR IGNORE INTO"
        } else {
            "INSERT INTO"
        };
        let sql = format!(
            "{prefix} lists ({}) VALUES ({})",
            cols.join(", "),
            placeholders.join(", "),
        );
        conn.execute(&sql, rusqlite::params_from_iter(binds))
            .expect("ListBuilder::insert: schema mismatch in test fixture");
    }
}

#[cfg(test)]
mod tests;
