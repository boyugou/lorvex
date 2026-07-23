//! Golden snapshot tests for every top-level render function, split
//! by domain. The snapshot files live alongside this directory and
//! are namespaced via the canonical
//! `lorvex__render__snapshots__<domain>__<test>` path, so any drift
//! surfaces as a reviewable diff under `cargo insta review`.
//!
//! Each split file pulls fixtures from [`fixtures`] and uses the
//! [`snapshot!`] / [`snapshot_json!`] helper macros that pin
//! `snapshot_path => "."` so the `.snap` files sit in this directory
//! rather than insta's default `<source-dir>/snapshots/`
//! subdirectory (which would collide with the module dir itself).

/// Assert a text-format snapshot in this directory (not the
/// insta-default `snapshots/` subdirectory). Per-domain modules call
/// this so the existing co-located `.snap` files keep round-tripping
/// after the split.
macro_rules! snapshot {
    ($value:expr) => {{
        ::insta::with_settings!({ snapshot_path => "." }, {
            ::insta::assert_snapshot!($value);
        });
    }};
}

/// Companion for JSON-suffixed snapshots: keeps the `@json` suffix
/// while pinning the same in-directory snapshot path.
macro_rules! snapshot_json {
    ($value:expr) => {{
        ::insta::with_settings!({ snapshot_path => ".", snapshot_suffix => "json" }, {
            ::insta::assert_snapshot!($value);
        });
    }};
}

mod calendar;
mod fixtures;
mod focus;
mod habits;
mod lists;
mod memory;
mod tags;
mod tasks;
