//! Task-domain repository subtree.
//!
//! All SQL for the `tasks` table and its directly-attached child tables
//! (dependencies, reminders, calendar event links, recurrence exceptions,
//! checklist items, plus the cold-open markdown-to-checklist promotion)
//! lives here. Every call site in the workspace (Tauri commands, MCP
//! handlers, sync apply, workflow mutations) routes through these
//! modules instead of embedding its own SQL.
//!
//! Layout reflects read/write split where useful and groups child-table
//! repositories under their parent concern:
//!
//! - [`read`] — query side of the `tasks` table itself (paginated
//!   listing, lookup, today/upcoming/overdue/deferred buckets, search,
//!   tag scoping, archive enumeration, dependency-aware lookups, and
//!   the `TaskRow` row shape every reader returns).
//! - [`write`] — `INSERT` / `UPDATE` / `DELETE` of the `tasks` table:
//!   create, dynamic patch update, soft + hard delete, duplicate.
//! - [`dependencies`] — `task_dependencies` edge writes plus the
//!   graph-traversal read API (`graph` submodule).
//! - [`reminders`] — `task_reminders` read API.
//! - [`checklist`] — `task_checklist_items`: a read API (`read`) and
//!   the cold-open markdown-body promotion migration (`promote`).
//! - [`calendar_links`] — `task_calendar_event_links` UPSERT API.
//! - [`recurrence`] — `task_recurrence_exceptions` per-occurrence
//!   override CRUD.

pub mod calendar_links;
pub mod checklist;
pub mod dependencies;
pub mod read;
pub mod recurrence;
pub mod reminders;
pub mod write;
