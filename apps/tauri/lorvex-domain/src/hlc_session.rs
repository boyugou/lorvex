//! Per-mutation HLC stamp session.
//!
//! [`HlcSession`] is the API boundary between repository / mutation code
//! and the per-surface `HlcState` storage (Tauri's `OnceLock<Mutex<…>>`,
//! CLI's `Mutex<Option<HlcState>>`, MCP server's `Mutex<Option<HlcState>>`).
//!
//! A session is created **once per top-level mutation** — for example, a
//! single MCP `cancel_recurrence` call that produces one parent
//! cancellation plus N child cancellations should construct exactly one
//! `HlcSession` and call `session.next_version()` N+1 times.
//! every repository call independently grabbed the storage lock via
//! `next_hlc_version` / `generate_hlc_version` / `generate_version_result`,
//! paying N lock acquisitions and N counter advances for what is
//! semantically one batch of writes.
//!
//! The session does **not** unify the storage backend: each surface
//! keeps its own `HlcState` (Tauri's app process, the CLI process, and
//! the MCP server process are three separate processes; they share the
//! device suffix via `device_id_to_hlc_suffix` plus a surface tag, not
//! state). What the session unifies is the API boundary — every caller
//! that needs a stamp now goes through `HlcSession::next_version()`.

use crate::hlc::Hlc;
#[cfg(test)]
use crate::hlc_state::HlcState;

/// Storage-side handle that backs an [`HlcSession`].
///
/// Each surface implements this for whatever container holds its
/// `HlcState` (a `Mutex<HlcState>`, `Mutex<Option<HlcState>>`, …) and
/// the session calls `with_state` once per stamp. The closure signature
/// is `&mut HlcState -> Hlc` so the implementation can call
/// `state.generate()` directly.
///
/// Implementations must serialize concurrent calls to `with_state` so
/// the underlying counter advances monotonically across threads — every
/// existing surface already holds a mutex over its state, so this is
/// trivially satisfied.
pub trait HlcStateHandle {
    /// Acquire the storage lock and mint the next strictly-monotonic
    /// HLC from the live `HlcState`. Implementations should serialize
    /// concurrent calls through whatever container guards their state.
    ///
    /// Kept as a fixed-signature method (rather than a generic
    /// `with_state<R>` callback) so the trait is `dyn`-compatible and
    /// `HlcSession` can hold a `&dyn HlcStateHandle` without leaking a
    /// type parameter into every repository signature.
    fn generate(&self) -> Hlc;
}

/// Borrowed handle to a per-surface `HlcState`. Constructed once per
/// top-level mutation by the orchestrator (or, until #3369 lands, by
/// each surface's `with_hlc_session` shim) and threaded through the
/// repository functions that need stamps.
///
/// `'a` is the lifetime of the storage backend the session borrows
/// from. The session is intentionally `!Send` and lock-free at the API
/// surface — every `next_version` call goes back through the trait's
/// `with_state` to acquire the storage lock for the duration of one
/// `HlcState::generate`.
pub struct HlcSession<'a> {
    state: &'a dyn HlcStateHandle,
}

impl<'a> HlcSession<'a> {
    /// Wrap a storage handle in a session. Callers normally do not
    /// invoke this directly — each surface exposes a `with_hlc_session`
    /// helper that constructs a session from its process-wide state.
    #[must_use]
    pub fn new(state: &'a dyn HlcStateHandle) -> Self {
        Self { state }
    }

    /// Mint the next strictly-monotonic [`Hlc`] from the session's
    /// underlying storage. Equivalent to one `HlcState::generate` call.
    #[must_use]
    pub fn next_version(&self) -> Hlc {
        self.state.generate()
    }

    /// Convenience: mint the next stamp and stringify it to the wire
    /// format. Most call sites consume the version as a `&str` anyway,
    /// so this avoids a `.to_string()` at every site.
    #[must_use]
    pub fn next_version_string(&self) -> String {
        self.next_version().to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    struct TestHandle(Mutex<HlcState>);

    impl HlcStateHandle for TestHandle {
        fn generate(&self) -> Hlc {
            let mut guard = self.0.lock().expect("test mutex");
            guard.generate()
        }
    }

    #[test]
    fn session_emits_strictly_monotonic_stamps() {
        let handle = TestHandle(Mutex::new(
            HlcState::new("0123456789abcdef".to_string()).expect("canonical suffix"),
        ));
        let session = HlcSession::new(&handle);
        let v1 = session.next_version();
        let v2 = session.next_version();
        let v3 = session.next_version();
        assert!(v2 > v1, "session stamps must be monotonic ({v1} < {v2})");
        assert!(v3 > v2, "session stamps must be monotonic ({v2} < {v3})");
    }

    #[test]
    fn session_string_form_matches_hlc_to_string() {
        let handle = TestHandle(Mutex::new(
            HlcState::new("fedcba9876543210".to_string()).expect("canonical suffix"),
        ));
        let session = HlcSession::new(&handle);
        let s = session.next_version_string();
        let parsed = Hlc::parse(&s).expect("session string round-trips through Hlc::parse");
        // Re-stringify and compare — the wire format is deterministic.
        assert_eq!(parsed.to_string(), s);
    }
}
