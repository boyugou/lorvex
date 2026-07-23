//! Typed error enum for the MCP server crate.
//!
//! Internal helpers return `Result<T, McpError>` instead of
//! `Result<T, String>`. The outermost MCP tool handlers keep
//! `Result<String, String>` as the protocol boundary, with a canonical
//! `McpError -> String` conversion that preserves the server's sanitization
//! policy.
//!
//! **Wire format (#2182, refined #4492).** rmcp's MCP transport requires
//! the error side of a tool result to be a string. To give the calling
//! assistant enough structure to programmatically classify failures
//! (retry vs. reshape vs. surface to the user) we emit a JSON-RPC-shaped
//! object *inside* that string:
//!
//! ```json
//! {
//!   "code": "validation" | "not_found" | "db_busy" | "sync_conflict"
//!         | "serialization" | "rate_limited" | "internal",
//!   "message": "<human-readable, already sanitized>",
//!   "retryable": bool,
//!   "details": {
//!     "docs_hint": "<optional pointer>",
//!     "entity_id": "<optional>"
//!   }
//! }
//! ```
//!
//! The `details` object is omitted entirely when neither sub-field has
//! a value, keeping the wire payload compact on the chatty error path.
//!
//! One escape hatch keeps the boundary useful for humans and ops:
//!
//! 1. `CancelledByClient` stays as the short literal `"Error: cancelled by
//!    client"` — #2133 treats it as a normal client-initiated outcome and
//!    grep-friendliness matters more than structure.
//!
//! ## Module layout
//!
//! It now splits
//! into four submodules so the security-sensitive wire encoding stays
//! independently auditable:
//!
//! - [`types`] — the `McpError` enum and the structured `ErrorKind`
//!   discriminator (with `retryable` + `docs_hint` policy).
//! - [`conversions`] — `From<…>` impls that lift external errors into
//!   `McpError`.
//! - [`wire`] — the protocol-boundary encoder: sanitization, kind
//!   classification, JSON payload assembly, and `From<McpError> for
//!   String`. This is the surface a security audit looks at.
//! - tests (gated `#[cfg(test)]`) — round-trip coverage for every
//!   structured variant, kind classifier, and the sanitizer's
//!   injection guards.

mod conversions;
mod types;
mod wire;

#[cfg(test)]
mod tests;

pub use types::McpError;
// `ErrorKind` stays pub(crate) on its own definition (in `types.rs`)
// rather than via a re-export here. Adding `pub(crate) use
// types::ErrorKind;` triggers an `unused_imports` warning at the
// crate-root scope (no external module references it; `wire.rs` and
// `tests.rs` reach it via `super::types::ErrorKind`). Keep the
// re-export commented out as documentation: if a future cross-module
// caller needs the discriminator, lift the alias here and the
// existing `pub(crate)` visibility on the enum carries through.
