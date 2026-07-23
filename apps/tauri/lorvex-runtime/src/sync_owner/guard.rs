use std::sync::Arc;

/// Panic-hook closure invoked when a [`SyncOwnerLeaseGuard`] release
/// closure panics. Receives `(lease_name, owner_id, panic_message)`
/// so a host can correlate the orphan-lease alert with the panicking
/// transport. Wired into the guard via
/// [`super::try_acquire_sync_owner_with_guard`]'s `on_release_panic`
/// parameter. The hook is required so release panic diagnostics never
/// silently fall back to process stderr.
pub type ReleasePanicHook = Arc<dyn Fn(&str, &str, &str) + Send + Sync>;

/// RAII guard returned by [`super::try_acquire_sync_owner_with_guard`] that
/// releases the lease on drop. Holding the connection factory here
/// means the runtime crate owns the release pattern and every
/// consumer gets a single guarantee: once `Some(guard)` is
/// returned, the lease is released on drop regardless of how the
/// enclosing scope exits. Per-transport `*LeaseGuard` reimplementations used
/// to bind the guard AFTER an error / early-return branch — a panic in those
/// intermediate statements would pin the lease for the full TTL.
///
/// The connection factory is opened at drop time rather than holding the
/// original connection: callers can drop their own connection mid-flight to
/// avoid pinning the writer mutex across network I/O.
/// Release closure invoked by [`SyncOwnerLeaseGuard`] on drop. The
/// caller provides the implementation — typically a closure that
/// opens a fresh DB connection and calls [`super::release_sync_owner`].
///
/// `FnOnce` (rather than `FnMut`) encodes the release contract in
/// the type system: the closure runs at most once. A `FnMut` closure
/// could be invoked twice if a future refactor accidentally split
/// the explicit `release()` from the `Drop` path, and
/// `release_sync_owner` is non-idempotent (the second call sees no
/// row and returns `false`, which downstream callers might
/// misinterpret as "lease was stolen"). `FnOnce` makes that bug
/// structurally impossible.
///
/// Returning the closure type as `Box<dyn FnOnce(&str, &str) + Send>`
/// keeps the runtime crate decoupled from the consumer's connection-
/// handle shape (some surfaces hold `Connection` directly, others
/// hand out `MutexGuard<Connection>` from a writer pool).
///
/// The closure receives the lease name and owner id as arguments so
/// it doesn't need to capture them. Errors are logged inside the
/// closure (not propagated) since `Drop` cannot return errors.
pub type LeaseReleaseFn = Box<dyn FnOnce(&str, &str) + Send>;

/// `#[must_use]` so a `let _ = …` or stray
/// expression-statement that drops the guard immediately fires a
/// compiler warning. The guard's only correct use is to bind it for
/// the scope that owns the lease; dropping it on the floor releases
/// the lease the moment the temporary expires, which is virtually
/// never what the caller intended.
#[must_use = "binding the guard to `_` immediately releases the sync-owner lease; \
              keep it bound to a name for the scope that owns the lease, or call \
              `.release()` explicitly"]
pub struct SyncOwnerLeaseGuard {
    lease_name: String,
    owner_id: String,
    /// `Option` so an explicit [`release`] consumes the closure;
    /// [`Drop`] then becomes a no-op. `Send` so the guard can move
    /// across `await` points if a future caller is async.
    ///
    /// [`release`]: SyncOwnerLeaseGuard::release
    release_fn: Option<LeaseReleaseFn>,
    /// Caller-supplied panic hook routed through
    /// [`invoke_release_fn`] when the release closure unwinds.
    /// Wrapped in `Arc` rather than `Box<dyn FnOnce>` because the
    /// guard's `release()` and `Drop` paths each invoke the hook at
    /// most once — but a single hook may be shared across many
    /// guards, so a one-shot box would force every transport to
    /// build a fresh closure per acquire.
    on_release_panic: ReleasePanicHook,
}

impl std::fmt::Debug for SyncOwnerLeaseGuard {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SyncOwnerLeaseGuard")
            .field("lease_name", &self.lease_name)
            .field("owner_id", &self.owner_id)
            .field(
                "release_fn",
                &if self.release_fn.is_some() {
                    "<active>"
                } else {
                    "<released>"
                },
            )
            .finish()
    }
}

impl SyncOwnerLeaseGuard {
    pub(super) fn new(
        lease_name: String,
        owner_id: String,
        release_fn: LeaseReleaseFn,
        on_release_panic: ReleasePanicHook,
    ) -> Self {
        Self {
            lease_name,
            owner_id,
            release_fn: Some(release_fn),
            on_release_panic,
        }
    }

    /// Release the lease explicitly. After this returns, [`Drop`] is
    /// a no-op. The release closure runs synchronously here just as
    /// it would in `Drop`.
    ///
    /// a panic from the release closure is caught
    /// here just as it is in `Drop`. The explicit-release path and
    /// the implicit drop path must agree on panic semantics, or a
    /// caller who picks `release()` over letting the guard fall out
    /// of scope can suddenly experience a panic that the drop path
    /// would have swallowed.
    pub fn release(mut self) {
        if let Some(release_fn) = self.release_fn.take() {
            invoke_release_fn(
                release_fn,
                &self.lease_name,
                &self.owner_id,
                &self.on_release_panic,
            );
        }
    }

    /// The lease name this guard owns. Useful for diagnostics.
    pub fn lease_name(&self) -> &str {
        &self.lease_name
    }

    /// The owner id this guard registered with the lease.
    pub fn owner_id(&self) -> &str {
        &self.owner_id
    }
}

impl Drop for SyncOwnerLeaseGuard {
    /// invoke the release closure inside
    /// `catch_unwind` so a panic in the user-supplied closure cannot
    /// propagate out of `Drop`. A panic during unwinding (i.e. when
    /// the guard is being dropped because the caller's stack is
    /// already unwinding from another panic) would abort the process
    /// — the double-panic rule. Every transport's release closure
    /// touches a SQLite connection it opens at drop time, and any of
    /// those steps (locking the writer mutex, executing the DELETE,
    /// observing a poisoned lock if a sibling thread panicked) can
    /// itself panic. Guarding the call site here is the only safe
    /// pattern; the closure cannot return errors out of `Drop`, and
    /// a missed release will be reaped by the lease's TTL.
    fn drop(&mut self) {
        if let Some(release_fn) = self.release_fn.take() {
            invoke_release_fn(
                release_fn,
                &self.lease_name,
                &self.owner_id,
                &self.on_release_panic,
            );
        }
    }
}

/// Shared release-closure invoker for the explicit `release()` path
/// and the implicit `Drop` path. Wraps the call in
/// `catch_unwind(AssertUnwindSafe(...))` so a panicking closure
/// cannot trigger a double-panic during stack unwinding (audit
/// #2962-M11). `AssertUnwindSafe` is justified because the release
/// closure receives only borrowed `&str` arguments and any state
/// captured by the closure is owned by the closure itself — there
/// is no shared mutable state we could leave in a partially-updated
/// shape from this crate's side.
fn invoke_release_fn(
    release_fn: LeaseReleaseFn,
    lease_name: &str,
    owner_id: &str,
    on_release_panic: &ReleasePanicHook,
) {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        release_fn(lease_name, owner_id);
    }));
    if let Err(payload) = result {
        // Drop must not propagate. Log a coarse-grained message so
        // operators can correlate orphan-lease alerts with the
        // panicking transport. The lease itself will be reaped by
        // its TTL on the next acquirer's pass.
        let panic_message = payload
            .downcast_ref::<&'static str>()
            .map(|s| (*s).to_string())
            .or_else(|| payload.downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "<non-string panic payload>".to_string());
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            on_release_panic(lease_name, owner_id, &panic_message);
        }));
    }
}
