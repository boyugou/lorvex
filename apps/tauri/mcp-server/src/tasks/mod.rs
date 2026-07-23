//! Task domain modules — split from the old `server_task_*` flat tree.
//!
//! Each child mirrors a former `server_task_<name>` module/file. The
//! `support`, `validation`, `dependencies`, and `tags` siblings expose
//! shared helpers used by the routers.

pub(crate) mod batch;
pub(crate) mod day_query;
pub(crate) mod dependencies;
pub(crate) mod lifecycle;
pub(crate) mod lww;
pub(crate) mod mutations;
pub(crate) mod query;
pub(crate) mod recurrence;
pub(crate) mod router;
pub(crate) mod support;
pub(crate) mod update_sync;
pub(crate) mod validation;
