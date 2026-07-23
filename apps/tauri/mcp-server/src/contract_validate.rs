//! Trait + context surface for the `lorvex_mcp_derive::ContractValidate`
//! derive macro (#3373 / #3437).
//!
//! The derive emits an `impl ContractValidate for <Args>` that runs
//! the same shape / range / existence checks the hand-rolled handlers
//! in `tasks/validation.rs` already enforce. Centralizing the trait
//! here means every `#[derive(ContractValidate)]` site can call
//! `args.validate_shape()?` (no DB) or `args.validate(&ctx)?` (with
//! DB) without reaching into the macro crate's namespace.
//!
//! See the crate-level doc on `lorvex_mcp_derive` for the supported
//! attribute surface and the migration playbook.

use crate::error::McpError;
use rusqlite::Connection;

/// Handle the validation impl needs to perform DB-touching
/// `exists_in` checks. The borrow lifetime is `'a` so handlers can
/// build the ctx from a `&Connection` without cloning.
pub(crate) struct ValidationCtx<'a> {
    pub(crate) conn: &'a Connection,
}

impl<'a> ValidationCtx<'a> {
    pub(crate) const fn new(conn: &'a Connection) -> Self {
        Self { conn }
    }
}

/// Auto-derived contract validation. Implementors are produced by
/// `#[derive(lorvex_mcp_derive::ContractValidate)]`. Hand-written
/// impls are not expected.
pub(crate) trait ContractValidate {
    /// Run every non-DB check (UUID shape, string lengths, range
    /// bounds, tag-element length). Cheap; safe to call before
    /// opening any savepoint.
    fn validate_shape(&self) -> Result<(), McpError>;

    /// Run shape checks first, then `exists_in` lookups against the
    /// DB. The default impl calls `validate_shape` and is overridden
    /// by the derive when at least one field carries an
    /// `#[validate(exists_in = "...")]` attribute. Kept callable for
    /// shape-only structs so handler call sites can uniformly call
    /// `args.validate(&ctx)?` regardless of whether the struct has
    /// any DB-backed fields.
    fn validate(&self, _ctx: &ValidationCtx<'_>) -> Result<(), McpError> {
        self.validate_shape()
    }
}
