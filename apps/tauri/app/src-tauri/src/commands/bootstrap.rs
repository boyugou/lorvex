//! First-paint coalesced bootstrap for the main window.
//!
//! `get_today_bootstrap` collapses every synchronous read the first
//! paint depends on (`getOverview`, `getAllLists`,
//! `getPreference(timezone)`, two sidebar preferences,
//! `getSetupStatus`, `getCurrentFocus`, and several panel-conditional
//! tails) into a single IPC round-trip and pins them inside one
//! `BEGIN DEFERRED` snapshot so every field observes the same
//! point-in-time database state. Without it, mounting the React
//! shell would fan into 15+ sequential `invoke()` calls and produce a
//! visible two-wave 120–200 ms waterfall on slower machines.
//!
//! The individual commands (`get_overview`, `get_all_lists`,
//! `get_preference`, `get_setup_status`, `get_current_focus`) are
//! unchanged — the bootstrap is additive, not a replacement. Any view
//! that mounts outside the main-window bootstrap path or triggers a
//! targeted refetch continues to hit the original endpoints.

use std::collections::HashMap;

use lorvex_domain::preference_keys::{
    PREF_DASHBOARD_LAYOUT, PREF_SIDEBAR_HIDE_EMPTY_LISTS, PREF_SIDEBAR_VISIBLE_MODULES,
    PREF_TIMEZONE,
};
use lorvex_store::with_deferred_read_transaction;
use serde::Serialize;

use crate::db::get_read_conn;
use crate::error::{AppError, AppResult};

use super::{
    overview::compute_overview, planning::get_current_focus_with_conn, CurrentFocusWithTasks,
    ListWithCount, Overview,
};

pub type SetupStatus = lorvex_store::SetupStatus;

/// Aggregate first-paint payload. Every field the main window needs
/// before the shell can render its first frame — overview stats, the
/// lists sidebar, the DayContext timezone, layout preferences, the
/// user's current focus, and setup-status gating.
#[derive(Debug, Serialize)]
pub struct TodayBootstrap {
    /// The `get_overview` payload (stats + top-priority + recently
    /// completed + focus summary). Populates `useOverview`.
    pub overview: Overview,
    /// Visible lists + open counts. Populates `useAllLists`.
    pub lists: Vec<ListWithCount>,
    /// Preference snapshot. Keys are the literal preference names
    /// (e.g. `timezone`, `sidebar_visible_modules`); values are the
    /// stored JSON-encoded strings, same as `getPreference`'s return.
    /// Missing preferences are absent from the map. Callers decode
    /// the JSON client-side (matches the existing per-key code path).
    pub preferences: HashMap<String, String>,
    /// Fully-resolved IANA timezone name. Pre-computed in the
    /// backend so `DayContextProvider` can hydrate synchronously
    /// without waiting on its own timezone-preference query.
    pub timezone: String,
    /// Today's YYYY-MM-DD in the active timezone. Pre-computed so
    /// surfaces that key on `todayYmd` don't need to derive it from
    /// the timezone on mount.
    pub today_ymd: String,
    /// Gates onboarding surfaces. Populates `useSetupStatus`.
    pub setup_status: SetupStatus,
    /// Today's focus plan, if the user has one. Populates
    /// `useCurrentFocus`. `None` when no plan exists for today.
    pub current_focus: Option<CurrentFocusWithTasks>,
}

/// Load all preferences the first-paint path reads in a single
/// `WHERE key IN (…)` SELECT. Keeps the bootstrap snapshot self-
/// contained: every value observed here came from the same deferred
/// read transaction as the overview/lists/focus payloads.
fn load_bootstrap_preferences(conn: &rusqlite::Connection) -> AppResult<HashMap<String, String>> {
    const BOOTSTRAP_PREFERENCE_KEYS: &[&str] = &[
        PREF_TIMEZONE,
        PREF_SIDEBAR_VISIBLE_MODULES,
        PREF_SIDEBAR_HIDE_EMPTY_LISTS,
        PREF_DASHBOARD_LAYOUT,
    ];

    // `BOOTSTRAP_PREFERENCE_KEYS.len() == 4` is a compile-time
    // constant; hard-code the placeholder list so the
    // `get_today_bootstrap` first-paint hot path does not allocate
    // a `Vec<String>` + four small `String`s + a `String` join just
    // to produce the static `"?1,?2,?3,?4"` substring.
    const _: () = assert!(
        BOOTSTRAP_PREFERENCE_KEYS.len() == 4,
        "bootstrap preference key count changed; update the literal placeholder list"
    );
    let sql = "SELECT key, value FROM preferences WHERE key IN (?1,?2,?3,?4)";
    let mut stmt = conn.prepare_cached(sql).map_err(AppError::from)?;
    let params_refs: Vec<&dyn rusqlite::ToSql> = BOOTSTRAP_PREFERENCE_KEYS
        .iter()
        .map(|k| k as &dyn rusqlite::ToSql)
        .collect();
    let rows = stmt
        .query_map(rusqlite::params_from_iter(params_refs), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .map_err(AppError::from)?;

    let mut out = HashMap::with_capacity(BOOTSTRAP_PREFERENCE_KEYS.len());
    for row in rows {
        let (key, value) = row.map_err(AppError::from)?;
        out.insert(key, value);
    }
    Ok(out)
}

fn compute_today_bootstrap(conn: &rusqlite::Connection) -> AppResult<TodayBootstrap> {
    let overview = compute_overview(conn)?;
    let lists_rows = lorvex_store::repositories::list_repo::get_all_lists_with_counts(conn)
        .map_err(AppError::from)?;
    let lists: Vec<ListWithCount> = lists_rows
        .into_iter()
        .map(|r| ListWithCount {
            list: super::task_list_from_list_row(r.list),
            open_count: r.open_count,
        })
        .collect();
    let preferences = load_bootstrap_preferences(conn)?;
    let today_ymd = lorvex_workflow::timezone::today_ymd_for_conn(conn)?;
    let timezone =
        lorvex_workflow::timezone::active_timezone_name(conn)?.unwrap_or_else(|| "UTC".to_string());
    let setup_status = lorvex_store::load_setup_status(conn).map_err(AppError::from)?;
    let current_focus = get_current_focus_with_conn(conn, &today_ymd)?;

    Ok(TodayBootstrap {
        overview,
        lists,
        preferences,
        timezone,
        today_ymd,
        setup_status,
        current_focus,
    })
}

/// coalesced first-paint read. Returns every field the
/// main window shell needs before it can render. Pinned inside a
/// single `BEGIN DEFERRED` snapshot so every field reflects the same
/// point-in-time database state — a concurrent writer committing
/// mid-bootstrap cannot make the aggregate self-contradictory (e.g.
/// `current_focus` referencing a task that's missing from the lists
/// roll-up).
#[tauri::command]
pub fn get_today_bootstrap() -> Result<TodayBootstrap, String> {
    let conn = get_read_conn()?;
    with_deferred_read_transaction::<_, AppError, _>(&conn, compute_today_bootstrap)
        .map_err(String::from)
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::test_support::test_conn;

    fn seed_inbox_task(conn: &rusqlite::Connection, id: &str, status: &str) {
        // lift to canonical TaskBuilder.
        let title = format!("Task {id}");
        lorvex_store::test_support::fixtures::TaskBuilder::new(id)
            .title(&title)
            .status(status)
            .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
            .created_at("2026-04-16T00:00:00Z")
            .list_id(Some("inbox"))
            .insert(conn);
    }

    #[test]
    fn compute_today_bootstrap_populates_every_field() {
        // the whole point of the bootstrap is to cover
        // the first-paint read set in one trip. If any field falls
        // out of sync with the rest of the schema, the React shell
        // falls back to the per-field IPC that this command exists
        // to eliminate. Assert each field is populated end-to-end.
        let conn = test_conn();

        // Seed a timezone + sidebar preferences so the preference
        // snapshot is non-empty and the timezone resolver returns
        // something other than the UTC fallback.
        conn.execute(
            "INSERT INTO preferences (key, value, updated_at, version)
             VALUES ('timezone', '\"America/New_York\"', '2026-04-16T00:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
            [],
        )
        .expect("seed timezone");
        conn.execute(
            "INSERT INTO preferences (key, value, updated_at, version)
             VALUES ('sidebar_visible_modules', '\"[\\\"today\\\",\\\"upcoming\\\"]\"', '2026-04-16T00:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
            [],
        )
        .expect("seed sidebar modules");

        // One open task, one recently-completed task so the overview
        // stats + top-priority list + recently-completed list all
        // have at least one row.
        seed_inbox_task(&conn, "t-open", "open");
        conn.execute("UPDATE tasks SET priority = 1 WHERE id = 't-open'", [])
            .expect("prioritize open task");
        seed_inbox_task(&conn, "t-done", "completed");
        conn.execute(
            "UPDATE tasks SET completed_at = '2026-04-16T12:00:00Z' WHERE id = 't-done'",
            [],
        )
        .expect("mark done task completed");

        // A current-focus plan for today, so the optional
        // `current_focus` field is populated rather than None.
        let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn).expect("today ymd");
        conn.execute(
            "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
             VALUES (?1, 'brief', 'America/New_York', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-16T00:00:00Z', '2026-04-16T00:00:00Z')",
            rusqlite::params![today],
        )
        .expect("seed current focus");
        conn.execute(
            "INSERT INTO current_focus_items (date, position, task_id)
             VALUES (?1, 0, 't-open')",
            rusqlite::params![today],
        )
        .expect("seed focus item");

        let bootstrap = compute_today_bootstrap(&conn).expect("compute bootstrap");

        // Overview: open-count, top-priority, recently-completed.
        assert_eq!(bootstrap.overview.stats.open_count, 1);
        assert_eq!(bootstrap.overview.top_by_priority.len(), 1);
        assert_eq!(bootstrap.overview.recently_completed.len(), 1);

        // Lists: `test_conn` seeds the inbox list.
        assert!(
            !bootstrap.lists.is_empty(),
            "test_conn seeds the inbox list"
        );

        // Preference snapshot must include the two keys we seeded.
        assert!(bootstrap.preferences.contains_key("timezone"));
        assert!(bootstrap
            .preferences
            .contains_key("sidebar_visible_modules"));

        // Timezone + today: resolved, not the UTC fallback.
        assert_eq!(bootstrap.timezone, "America/New_York");
        assert_eq!(bootstrap.today_ymd, today);

        // Setup status: at minimum the list-count reflects the
        // seeded inbox. Actual setup_completed depends on working-
        // hours preference (not seeded here) — we only care that
        // the struct hydrates from the same snapshot.
        assert!(bootstrap.setup_status.list_count >= 1);

        // Current focus: populated because we seeded one for today.
        let focus = bootstrap
            .current_focus
            .expect("current focus populated for today");
        assert_eq!(focus.date, today);
        assert_eq!(focus.task_ids, vec!["t-open".to_string()]);
        assert_eq!(focus.tasks.len(), 1);
    }

    #[test]
    fn compute_today_bootstrap_falls_back_to_utc_without_timezone_pref() {
        // No timezone preference seeded — the resolver should hand
        // the bootstrap a safe UTC default so DayContextProvider can
        // still hydrate synchronously without blocking on a per-
        // preference follow-up query.
        let conn = test_conn();
        let bootstrap = compute_today_bootstrap(&conn).expect("compute bootstrap");
        assert_eq!(bootstrap.timezone, "UTC");
        assert!(bootstrap.current_focus.is_none());
    }
}
