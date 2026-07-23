#[derive(Debug, thiserror::Error)]
pub enum RuntimeError {
    #[error(transparent)]
    Sqlite(#[from] rusqlite::Error),
    #[error("failed to create device identity")]
    DeviceIdentityUnavailable,
    /// `try_acquire_sync_owner` previously masked
    /// non-positive `ttl_ms` with `.max(1)`, so a transport that
    /// computed a TTL like `cap_ms - elapsed_ms` and let it go
    /// negative would silently install a 1 ms lease. Reject the
    /// nonsense input explicitly so the bug surfaces at the caller.
    #[error("ttl_ms must be >= 1, got {0}")]
    InvalidLeaseTtl(i64),
    /// `local_counters.value` is `INTEGER NOT NULL`, so a positive
    /// value is the only legal shape; a negative read indicates
    /// on-disk corruption that broke the monotonicity invariant
    /// callers depend on. Surface it as a typed error so the
    /// corruption is visible to the caller instead of being silently
    /// truncated to a fresh zero counter (which would make "this seq
    /// number is older than that one" unreliable).
    #[error("local_change_seq has non-numeric value {value:?}")]
    CorruptLocalChangeSeq { value: String },
    /// The wall clock returned an epoch millisecond value that overflowed
    /// `i64`. Practically impossible before year 2262, but a corrupted
    /// system clock or a future filesystem migration could produce it.
    /// Surfaced (rather than saturated) by the lease-acquisition path
    /// so that `expires_at_epoch_ms = now.saturating_add(ttl) = i64::MAX`
    /// — a value the strict-less-than steal predicate
    /// (`expires_at_epoch_ms < ?4`) can never beat — does NOT silently
    /// pin a lease forever. The `bump_local_change_seq` path stays
    /// saturating because the `updated_at` column has no liveness
    /// gate hanging off it.
    #[error("system clock returned an epoch ms value past i64::MAX (year ~2262); refusing to mint a lease that cannot be stolen back")]
    SystemClockOutOfRange,
}

pub type RuntimeResult<T> = Result<T, RuntimeError>;
