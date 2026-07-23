use super::*;

pub const TRASH_RETENTION_DAYS: i64 = 30;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StartupTrashPurgeReport {
    pub deleted: usize,
    pub deleted_ids: Vec<String>,
    pub remaining: i64,
}

pub type StartupTrashPurgeResult<T> = Result<T, SyncError>;
