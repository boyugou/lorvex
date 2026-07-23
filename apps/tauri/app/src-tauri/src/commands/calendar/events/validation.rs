#[allow(clippy::needless_pass_by_value, dead_code)] // mirrors Tauri command IPC ownership contract
/// thin wrapper around the canonical
/// `lorvex_domain::validation::normalize_task_recurrence`. The
/// previous implementation hand-rolled FREQ / INTERVAL / BYDAY /
/// COUNT / UNTIL / BYMONTHDAY validation, drifting from the MCP /
/// CLI / sync-apply truth in three ways: (a) it rejected RFC 5545
/// `UNTIL` shapes (`YYYYMMDD`, `YYYYMMDDTHHMMSSZ`) accepted by the
/// canonical validator (#2929-CL10), (b) it accepted unknown keys
/// instead of rejecting them, (c) it leniently round-tripped
/// `bymonthday` lowercase. A user creating a calendar event via the
/// desktop UI and another via MCP could therefore get different
/// validation answers for the same recurrence input, with sync
/// apply (which uses the canonical rules) silently rejecting the
/// app-accepted rule on the peer.
///
/// Delegates to the domain-level calendar recurrence normalizer so
/// Tauri, MCP, CLI, and sync apply enforce one recurrence contract.
pub(crate) fn normalize_calendar_recurrence(raw: Option<String>) -> Result<Option<String>, String> {
    lorvex_domain::validation::normalize_calendar_recurrence(raw.as_deref())
        .map_err(|e| String::from(crate::error::AppError::from(e)))
}

pub(crate) fn parse_calendar_date(value: &str, field: &str) -> Result<chrono::NaiveDate, String> {
    chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| format!("{field} must be YYYY-MM-DD"))
}
