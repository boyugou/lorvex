#![allow(unused_imports)] // facade re-exports Tauri command entry points

pub(crate) mod reads;
#[cfg(test)]
mod tests;
mod timezone_reanchor;
pub(crate) mod write;

#[cfg(test)]
pub(crate) use reads::default_sync_backend_kind;
pub use reads::{get_default_filesystem_bridge_root_path, get_preference, get_preferences};
pub use write::set_preference;
#[cfg(test)]
use write::set_preference_with_conn;
#[cfg(test)]
pub(crate) use write::set_preference_with_conn_for_tests;
