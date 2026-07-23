use super::*;

/// TTL for the in-memory best-streak cache. Best-streak is an
/// all-time aggregate that only moves when a habit gains a new long
/// consecutive run, so recomputing once per day per habit is fine.
pub(super) const BEST_STREAK_CACHE_TTL: std::time::Duration =
    std::time::Duration::from_secs(24 * 60 * 60);

/// In-memory cache of `(habit_id -> (best_streak, computed_at))`.
/// Populated lazily on Habits-view opens. Misses trigger a per-habit
/// full-history scan (one SQL round-trip per miss), after which the
/// value is valid for `BEST_STREAK_CACHE_TTL`.
pub(super) fn best_streak_cache() -> &'static Mutex<HashMap<String, (i64, Instant)>> {
    static CACHE: OnceLock<Mutex<HashMap<String, (i64, Instant)>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Public for tests that want to start from a clean slate.
#[cfg(test)]
pub(super) fn clear_best_streak_cache_for_test() {
    if let Ok(mut guard) = best_streak_cache().lock() {
        guard.clear();
    }
}

#[cfg(test)]
fn best_streak_full_history_scan_count() -> &'static AtomicUsize {
    static COUNT: OnceLock<AtomicUsize> = OnceLock::new();
    COUNT.get_or_init(|| AtomicUsize::new(0))
}

#[cfg(test)]
pub(super) fn reset_best_streak_full_history_scan_count_for_test() {
    best_streak_full_history_scan_count().store(0, Ordering::SeqCst);
}

#[cfg(test)]
pub(super) fn best_streak_full_history_scan_count_for_test() -> usize {
    best_streak_full_history_scan_count().load(Ordering::SeqCst)
}

#[cfg(test)]
pub(super) fn record_best_streak_full_history_scan_for_test() {
    best_streak_full_history_scan_count().fetch_add(1, Ordering::SeqCst);
}

#[cfg(not(test))]
pub(super) const fn record_best_streak_full_history_scan_for_test() {}

/// Drop a single habit's cached best-streak. Called from writes that
/// mutate completions so the next Habits-view open recomputes.
pub(crate) fn invalidate_best_streak_cache(habit_id: &lorvex_domain::HabitId) {
    if let Ok(mut guard) = best_streak_cache().lock() {
        guard.remove(habit_id.as_str());
    }
}

/// Drop the entire cache — used after bulk operations (data reset,
/// sync import) that can touch arbitrary habits.
pub(crate) fn clear_best_streak_cache() {
    if let Ok(mut guard) = best_streak_cache().lock() {
        guard.clear();
    }
}
