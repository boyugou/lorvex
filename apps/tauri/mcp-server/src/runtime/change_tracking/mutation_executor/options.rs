//! Caller-supplied options threaded through [`super::core::execute_with`].

use lorvex_workflow::mutation::MutationExecution;
use serde_json::Value;
use std::collections::HashMap;

/// Optional tombstone routing for delete-shaped mutations.
///
/// When `Some(payloads)`:
///
/// - The finalizer runs BEFORE the audit row is written (delete-shaped
///   mutations frequently need to enqueue follow-up syncs against the
///   row that is about to disappear from the live tables).
/// - The audit row is skipped entirely when the mutation reports
///   `deleted == false` in its `after` JSON — the idempotent
///   delete-of-missing short-circuit. Every caller that routes through
///   the executor uses the canonical `"deleted"` key
///   ([`TOMBSTONE_DELETED_KEY`]); bespoke shapes whose `after` names
///   the gate differently bypass [`super::core::execute_with`] entirely.
/// - `payloads` is threaded into `log_change` so the per-entity sync
///   envelopes carry the pre-delete row body.
pub(crate) type TombstonePayloads = HashMap<String, Value>;

/// JSON field every tombstone-shaped mutation that routes through
/// [`super::core::execute_with`] must use for its "row was actually
/// deleted" gate.
///
/// Mutations whose `after` shape names the gate field differently
/// (`cleared` for `clear_current_focus`, `plan_cleared` for
/// `remove_from_current_focus`) bypass [`super::core::execute_with`]
/// entirely and hand-roll `log_change` in their own per-shape audit
/// shim, because those paths also need to switch the audit `operation`
/// between `delete` and `update` based on the same gate — a knob the
/// executor does not (and should not) own. The executor's tombstone
/// short-circuit is therefore parametric in nothing: every caller that
/// reaches it uses the canonical `"deleted"` key.
pub(crate) const TOMBSTONE_DELETED_KEY: &str = "deleted";

/// Caller-supplied options for [`super::core::execute_with`].
///
/// Use [`ExecuteOptions::default`] for the common case (single audit
/// row, finalize-after-audit). Reach for the `with_*` setters only for
/// the variants the wrapper-per-shape API express.
#[derive(Default)]
pub(crate) struct ExecuteOptions {
    /// Delete-shaped routing. See [`TombstonePayloads`].
    pub(super) tombstone_payloads: Option<TombstonePayloads>,
    /// When `false` (default), [`super::core::execute_with`] emits the
    /// audit row before running the caller's finalizer. When `true`,
    /// the finalizer runs first — required for tombstone variants where
    /// the finalizer references rows the audit-row sync envelope is
    /// about to mark deleted.
    pub(super) finalize_before_audit: bool,
    /// When `Some(predicate)` and the predicate returns `false`, the
    /// audit row is suppressed entirely (the finalizer still runs).
    /// Used by no-op-shaped link mutations where the apply pass
    /// stamped an "already-linked" extra and the changelog should not
    /// record a redundant edit. The boxed signature keeps
    /// [`ExecuteOptions`] object-safe across the call sites that
    /// stash one in a local before passing it in.
    #[allow(clippy::type_complexity)]
    pub(super) should_emit: Option<Box<dyn FnOnce(&MutationExecution) -> bool>>,
}

impl ExecuteOptions {
    /// Wire delete-shaped routing for the canonical
    /// `after["deleted"]: bool` shape. Mutations whose `after` names
    /// the gate field differently (`cleared`, `plan_cleared`, …) do
    /// not share the executor's audit shape and must compose their
    /// own audit shim outside [`super::core::execute_with`].
    pub(crate) fn with_tombstone(mut self, payloads: TombstonePayloads) -> Self {
        self.tombstone_payloads = Some(payloads);
        self.finalize_before_audit = true;
        self
    }

    pub(crate) fn with_emit_if(
        mut self,
        predicate: impl FnOnce(&MutationExecution) -> bool + 'static,
    ) -> Self {
        self.should_emit = Some(Box::new(predicate));
        self
    }
}
