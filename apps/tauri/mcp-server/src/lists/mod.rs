//! List domain modules — split from the old `server_lists` / `server_list_health` tree.

pub(crate) mod health;
mod mutations;
mod queries;
pub(crate) mod router;

pub(crate) use mutations::{create_list, delete_list, reorganize_list, update_list};
pub(crate) use queries::{get_list, list_lists};
