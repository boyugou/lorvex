//! Typed error enum for the Tauri app crate.
//!
//! Internal helpers return `Result<T, AppError>` instead of
//! `Result<T, String>`. The outermost `#[tauri::command]` handlers keep
//! `Result<T, String>` as the protocol boundary, but the canonical
//! `AppError -> String` conversion now emits a typed JSON envelope
//! ([`CommandError`]) parsed on the frontend in
//! `app/src/lib/ipc/commandError.ts`. The CLI surface completed an
//! analogous `CliError` rewrite in commit `2c08c97c8`; #2949 mirrors
//! that work for the Tauri command surface.
//!
//! Wire format:
//!
//! ```json
//! { "kind": "not_found", "message": "Task not found", "detail": null }
//! { "kind": "disk_full", "message": "...", "detail": "..." }
//! ```
//!
//! The frontend switches on `kind` directly. The parser falls back
//! to treating non-JSON strings as plain `internal` errors so any
//! third-party `String`-typed reject still renders through the same
//! envelope.

mod boundary;
mod conversions;
mod envelope;
#[cfg(test)]
mod tests;
mod types;

pub use types::{AppError, AppResult};
