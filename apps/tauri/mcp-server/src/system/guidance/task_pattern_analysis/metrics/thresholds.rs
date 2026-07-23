use crate::error::McpError;
use rusqlite::Connection;

/// Configurable thresholds for learning insight detection.
/// Reads from preferences; falls back to sensible defaults.
#[derive(Debug)]
pub(in crate::system::guidance::task_pattern_analysis) struct InsightThresholds {
    /// Minimum defer_count to flag a task as "frequently deferred" (default: 3)
    pub(in crate::system::guidance::task_pattern_analysis) defer_count_min: i64,
    /// Days of inactivity before a project is "stalled" (default: 7)
    pub(in crate::system::guidance::task_pattern_analysis) stalled_window_days: i64,
    /// Severity thresholds: (high, medium) for deferred tasks (default: 8, 4)
    pub(in crate::system::guidance::task_pattern_analysis) deferred_severity_high: i64,
    pub(in crate::system::guidance::task_pattern_analysis) deferred_severity_medium: i64,
    /// Severity thresholds for stalled lists (default: 5, 2)
    pub(in crate::system::guidance::task_pattern_analysis) stalled_severity_high: i64,
    pub(in crate::system::guidance::task_pattern_analysis) stalled_severity_medium: i64,
    /// Severity thresholds for overdue tasks (default: 15, 5)
    pub(in crate::system::guidance::task_pattern_analysis) overdue_severity_high: i64,
    pub(in crate::system::guidance::task_pattern_analysis) overdue_severity_medium: i64,
}

impl Default for InsightThresholds {
    fn default() -> Self {
        Self {
            defer_count_min: 3,
            stalled_window_days: 7,
            deferred_severity_high: 8,
            deferred_severity_medium: 4,
            stalled_severity_high: 5,
            stalled_severity_medium: 2,
            overdue_severity_high: 15,
            overdue_severity_medium: 5,
        }
    }
}

/// Closed set of preference keys that contribute to
/// [`InsightThresholds`].
///
/// constants and a fall-through `match key.as_str()` dispatch. Adding
/// a ninth threshold required updating four sites in lockstep — the
/// `KEYS` array, the `params!` binding, the `match` arms, and the
/// `InsightThresholds` struct — with no compiler signal when one
/// surface drifted. The typed enum lets the loader walk
/// `InsightPreferenceKey::ALL` exactly once and the dispatch is
/// exhaustive at compile time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::system::guidance::task_pattern_analysis) enum InsightPreferenceKey {
    DeferCountMin,
    StalledWindowDays,
    DeferredSeverityHigh,
    DeferredSeverityMedium,
    StalledSeverityHigh,
    StalledSeverityMedium,
    OverdueSeverityHigh,
    OverdueSeverityMedium,
}

impl InsightPreferenceKey {
    pub(in crate::system::guidance::task_pattern_analysis) const ALL: [InsightPreferenceKey; 8] = [
        InsightPreferenceKey::DeferCountMin,
        InsightPreferenceKey::StalledWindowDays,
        InsightPreferenceKey::DeferredSeverityHigh,
        InsightPreferenceKey::DeferredSeverityMedium,
        InsightPreferenceKey::StalledSeverityHigh,
        InsightPreferenceKey::StalledSeverityMedium,
        InsightPreferenceKey::OverdueSeverityHigh,
        InsightPreferenceKey::OverdueSeverityMedium,
    ];

    pub(in crate::system::guidance::task_pattern_analysis) const fn as_str(self) -> &'static str {
        match self {
            InsightPreferenceKey::DeferCountMin => "insight_defer_count_min",
            InsightPreferenceKey::StalledWindowDays => "insight_stalled_window_days",
            InsightPreferenceKey::DeferredSeverityHigh => "insight_deferred_severity_high",
            InsightPreferenceKey::DeferredSeverityMedium => "insight_deferred_severity_medium",
            InsightPreferenceKey::StalledSeverityHigh => "insight_stalled_severity_high",
            InsightPreferenceKey::StalledSeverityMedium => "insight_stalled_severity_medium",
            InsightPreferenceKey::OverdueSeverityHigh => "insight_overdue_severity_high",
            InsightPreferenceKey::OverdueSeverityMedium => "insight_overdue_severity_medium",
        }
    }

    fn parse(raw: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|key| key.as_str() == raw)
    }

    const fn assign(self, thresholds: &mut InsightThresholds, value: i64) {
        match self {
            InsightPreferenceKey::DeferCountMin => thresholds.defer_count_min = value,
            InsightPreferenceKey::StalledWindowDays => thresholds.stalled_window_days = value,
            InsightPreferenceKey::DeferredSeverityHigh => thresholds.deferred_severity_high = value,
            InsightPreferenceKey::DeferredSeverityMedium => {
                thresholds.deferred_severity_medium = value;
            }
            InsightPreferenceKey::StalledSeverityHigh => thresholds.stalled_severity_high = value,
            InsightPreferenceKey::StalledSeverityMedium => {
                thresholds.stalled_severity_medium = value;
            }
            InsightPreferenceKey::OverdueSeverityHigh => thresholds.overdue_severity_high = value,
            InsightPreferenceKey::OverdueSeverityMedium => {
                thresholds.overdue_severity_medium = value;
            }
        }
    }
}

/// Load configurable insight thresholds from preferences.
/// Any missing preference uses the default value.
///
/// the 8 thresholds triggered 8 separate
/// `SELECT value FROM preferences WHERE key = ?` round-trips. Batch
/// into a single `WHERE key IN (...)` scan and hand-roll the
/// default/parse loop. Even though the preferences table is tiny,
/// `read_changelog_summary` / `get_learning_metrics` are frequently-
/// called MCP tools and 8 → 1 query reduces writer-mutex contention.
///
/// dispatch is now driven by the typed
/// [`InsightPreferenceKey`] enum so adding a future threshold takes
/// a single struct field + a single enum variant — the compiler then
/// drives the loader, the `WHERE key IN (...)` placeholder list, and
/// the assign dispatcher to stay in lockstep.
pub(in crate::system::guidance::task_pattern_analysis) fn load_insight_thresholds(
    conn: &Connection,
) -> Result<InsightThresholds, McpError> {
    let mut t = InsightThresholds::default();

    let key_strings: [&str; 8] = std::array::from_fn(|i| InsightPreferenceKey::ALL[i].as_str());

    let mut stmt = conn.prepare_cached(
        "SELECT key, value FROM preferences WHERE key IN
         (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
    )?;
    let rows = stmt.query_map(
        rusqlite::params![
            key_strings[0],
            key_strings[1],
            key_strings[2],
            key_strings[3],
            key_strings[4],
            key_strings[5],
            key_strings[6],
            key_strings[7],
        ],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
    )?;

    for row in rows {
        let (key, raw) = row?;
        let parsed = lorvex_domain::parse_positive_i64_preference(&raw, &key)?;
        if let Some(typed_key) = InsightPreferenceKey::parse(&key) {
            typed_key.assign(&mut t, parsed);
        }
        // Preferences table can carry historical / forward-compat
        // keys not in the current `InsightPreferenceKey::ALL` set;
        // ignore them silently since the SQL `WHERE key IN (...)`
        // already filtered to our known keys (this branch only
        // fires if the const array drifts away from the SQL bind
        // list, which is precisely the regression the typed enum
        // exists to prevent).
    }

    normalize_severity_pair(
        &mut t.deferred_severity_high,
        &mut t.deferred_severity_medium,
    );
    normalize_severity_pair(&mut t.stalled_severity_high, &mut t.stalled_severity_medium);
    normalize_severity_pair(&mut t.overdue_severity_high, &mut t.overdue_severity_medium);
    Ok(t)
}

const fn normalize_severity_pair(high: &mut i64, medium: &mut i64) {
    if *high < *medium {
        std::mem::swap(high, medium);
    }
}
