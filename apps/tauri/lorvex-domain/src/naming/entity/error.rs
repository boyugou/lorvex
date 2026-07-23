//! Typed parse error for [`super::EntityKind`].
//!
//! `EntityKind::try_parse` (and the `FromStr` impl that wraps it)
//! return this struct so callers can route unknown values through
//! `tracing::error!` + structured diagnostics instead of silently
//! falling through a `_ =>` arm. Debug builds escalate the same drift
//! to a `debug_assert!` inside `try_parse`.

/// Error returned by `EntityKind::from_str` for unrecognized values.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnknownEntityKind(pub String);

impl std::fmt::Display for UnknownEntityKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "unknown entity kind: {}", self.0)
    }
}

impl std::error::Error for UnknownEntityKind {}
