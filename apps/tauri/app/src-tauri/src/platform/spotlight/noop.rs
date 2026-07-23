pub fn remove_task(_task_id: &str) {}

pub fn remove_all_tasks() {}

pub fn reindex_all_tasks() {}

pub fn reindex_tasks_for_list(_conn: &rusqlite::Connection, _list_id: &str) {}

pub fn reindex_tasks_by_ids(_conn: &rusqlite::Connection, _task_ids: &[String]) {}
