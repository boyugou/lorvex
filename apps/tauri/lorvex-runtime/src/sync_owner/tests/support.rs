//! Shared fixtures for the sync_owner test suite. Re-exports the
//! parent module's symbols so each split file stays focused on its
//! domain.

pub(super) use super::super::*;
pub(super) use crate::local_state::initialize_local_runtime_tables;

pub(super) fn test_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    initialize_local_runtime_tables(&conn).expect("init tables");
    conn
}

pub(super) fn noop_release_panic_hook() -> ReleasePanicHook {
    std::sync::Arc::new(|_, _, _| {})
}
