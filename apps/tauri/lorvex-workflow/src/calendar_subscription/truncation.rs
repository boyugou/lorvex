//! Mid-stream truncation detection for already-downloaded ICS bodies.
//!
//! Two orthogonal checks, each catching a different truncation shape
//! the `END:VEVENT`-gated parser would otherwise skip silently:
//!
//! 1. The body (after trimming trailing whitespace / CRLF) must end
//!    with `END:VCALENDAR`. A well-formed feed always emits this
//!    terminator last, so a missing one is a strong truncation signal
//!    even when no VEVENT boundaries are unbalanced.
//!
//! 2. The number of `BEGIN:VEVENT` lines must equal the number of
//!    `END:VEVENT` lines. A partially-delivered final VEVENT would
//!    leave an open `BEGIN:VEVENT` that the parser discards on the
//!    next `BEGIN:VEVENT` reset.
//!
//! Shared between the Tauri fetch layer (which runs the check on
//! freshly-downloaded bodies before handing them to the parser) and
//! the parse layer (which re-runs the `UnbalancedVeventCount` half as
//! defense-in-depth for in-memory test / offline-import callers).

/// User-facing message for a truncated feed. Deliberately short and
/// suggestive of a transient condition — the scheduler will retry on
/// the next poll cycle, and we don't want to scare the user into
/// thinking the feed is permanently broken.
pub const ICS_TRUNCATION_MESSAGE: &str = "Feed truncated mid-stream — will retry";

/// Why a fetched ICS body was classified as truncated.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum IcsTruncationReason {
    /// The body does not end with `END:VCALENDAR` (possibly followed
    /// by trailing whitespace / CRLF). A feed that terminates cleanly
    /// always ends with this marker, so a missing one means the
    /// connection dropped before the calendar wrapper closed.
    MissingCalendarTerminator,
    /// The count of `BEGIN:VEVENT` lines does not equal the count of
    /// `END:VEVENT` lines. A VEVENT that opens without closing points
    /// at mid-event truncation — the parser's `END:VEVENT` gate would
    /// silently drop the unfinished block otherwise.
    UnbalancedVeventCount { begins: usize, ends: usize },
}

impl std::fmt::Display for IcsTruncationReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            IcsTruncationReason::MissingCalendarTerminator => {
                write!(f, "missing END:VCALENDAR terminator")
            }
            IcsTruncationReason::UnbalancedVeventCount { begins, ends } => write!(
                f,
                "unbalanced VEVENT markers ({begins} BEGIN:VEVENT vs {ends} END:VEVENT)"
            ),
        }
    }
}

/// Inspect an already-downloaded ICS body and decide whether it shows
/// the signatures of mid-stream truncation. Runs AFTER the
/// `BEGIN:VCALENDAR` presence check, so the body has already been
/// confirmed to look like an iCalendar file — we're only
/// disambiguating "legitimate feed" from "prefix of a feed".
pub fn detect_ics_truncation(body: &str) -> Result<(), IcsTruncationReason> {
    // Count BEGIN/END:VEVENT per-line so a property value that happens
    // to contain the literal string (`DESCRIPTION:see END:VEVENT note`)
    // can't game the check. We match the line after trimming leading
    // continuation-fold whitespace, so an unfolded line is handled the
    // same as a freshly-emitted one.
    let mut begins: usize = 0;
    let mut ends: usize = 0;
    for line in body.lines() {
        let trimmed = line.trim();
        if trimmed.eq_ignore_ascii_case("BEGIN:VEVENT") {
            begins += 1;
        } else if trimmed.eq_ignore_ascii_case("END:VEVENT") {
            ends += 1;
        }
    }
    if begins != ends {
        return Err(IcsTruncationReason::UnbalancedVeventCount { begins, ends });
    }

    // A feed that terminates cleanly ends with `END:VCALENDAR`
    // (case-insensitive), possibly with trailing whitespace / CRLF.
    // An empty body would have failed the earlier `BEGIN:VCALENDAR`
    // check so we never see one here.
    let tail = body.trim_end();
    let ends_with_calendar_marker = tail
        .rsplit(['\n', '\r'])
        .next()
        .is_some_and(|last| last.trim().eq_ignore_ascii_case("END:VCALENDAR"));
    if !ends_with_calendar_marker {
        return Err(IcsTruncationReason::MissingCalendarTerminator);
    }

    Ok(())
}
