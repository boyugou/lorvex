//! Cross-domain query router.
//!
//! Aggregates read-only tools that span multiple domains (tasks, lists, sync,
//! system overview, guidance). Mutation routers live alongside their domain
//! roots; this one stays cross-cutting because the underlying ops do too.

pub(crate) mod router;
