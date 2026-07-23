//! Tiny format primitives shared across the per-domain render modules,
//! plus the TTY-aware color/styling facade.
//!
//! Color and bold/underline emphasis is opt-in by stdout being a TTY.
//! When the CLI's output is piped into a file, captured by snapshot
//! tests, redirected through `jq`, or the user sets `NO_COLOR=1` /
//! `--no-color`, all `style_*` helpers fall through to plain text.
//! This lets the human-format paths read like a styled report on an
//! interactive terminal while the JSON paths and snapshot fixtures stay
//! byte-identical to the un-styled baseline.

use console::Style;

/// Format a boolean as `"yes"` / `"no"`. Used by the doctor / status
/// reports and consumed externally by `commands/setup.rs`.
pub(crate) const fn yes_no(value: bool) -> &'static str {
    if value {
        "yes"
    } else {
        "no"
    }
}

/// Style a task / habit priority cell. `None` priority renders as the
/// dimmed literal `"-"` (it sorts last in the canonical key but is
/// surfaced as visually de-emphasized in interactive output).
pub(crate) fn style_priority(priority: Option<i64>) -> String {
    match priority {
        Some(1) => Style::new().red().bold().apply_to("P1").to_string(),
        Some(2) => Style::new().yellow().apply_to("P2").to_string(),
        Some(3) => Style::new().cyan().apply_to("P3").to_string(),
        Some(4) => Style::new().dim().apply_to("P4").to_string(),
        Some(other) => format!("P{other}"),
        None => Style::new().dim().apply_to("-").to_string(),
    }
}

/// Style a section header (e.g. "Focus tasks:", "Lorvex Lists"). Bold +
/// underlined on a TTY, plain otherwise.
pub(crate) fn style_section_header(title: &str) -> String {
    Style::new().bold().underlined().apply_to(title).to_string()
}

/// Style a top-level CLI banner line ("Lorvex Tasks", "Lorvex Habits
/// (2026-04-10)"). Bold only — banners already stand out structurally
/// and the underline reads as noise.
pub(crate) fn style_banner(title: &str) -> String {
    Style::new().bold().apply_to(title).to_string()
}

/// Render a surface-specific empty-list hint as a dimmed,
/// arrow-prefixed line ending in `\n`. Replaces the flat literal
/// `" - none\n"` emitted by every empty collection
/// renderer (tags, memory, tasks, lists, habits, calendar, …) with a
/// short action-oriented suggestion such as
/// `" ↳ Tag tasks with --tag <name> to surface them here."`.
///
/// Two layout invariants:
///   * Indentation matches the data rows (two leading spaces) so the
///     hint sits in the same column as the list items it replaces.
///   * The trailing newline is included so callers can `push_str` it
///     in lieu of the previous `" - none\n"` without an extra writeln.
///
/// Colour is opt-in via the TTY-aware `console::Style::dim`; piped
/// output, snapshot fixtures, and `NO_COLOR=1` environments still
/// receive the plain ASCII fallback verbatim.
pub(crate) fn style_empty_hint(hint: &str) -> String {
    let line = format!("  ↳ {hint}");
    format!("{}\n", Style::new().dim().apply_to(line))
}

/// Render a CLI error's "next action" hint. Used by the top-level
/// error reporter in `main.rs` to print a short, ANSI-dim follow-up
/// suggestion under the error chain so a user landing on a typed
/// failure sees an actionable next step ("→ Try: `lorvex tasks ls`
/// to inspect available IDs.") instead of a bare error line.
///
/// The leading arrow + dim styling matches the empty-hint affordance
/// in [`style_empty_hint`]; piping / `NO_COLOR` strips the styling
/// while keeping the prose. The output excludes a trailing newline
/// so the caller controls line breaks.
pub(crate) fn style_next_action(hint: &str) -> String {
    Style::new()
        .dim()
        .apply_to(format!("→ Try: {hint}"))
        .to_string()
}

/// Probe the terminal width at render entry. Returns `Some(cols)` when
/// stdout is a TTY backed by a real terminal; `None` when piped,
/// snapshot-captured, redirected, or otherwise headless — in which
/// case callers should disable any width-driven truncation so the
/// canonical un-truncated form lands in files / fixtures / pipes.
///
/// We deliberately probe once per render rather than per-row: the
/// terminal size doesn't change mid-render (resizing during stdout
/// flush is a non-event), and crossing the syscall once keeps the
/// hot inner loops free of probe overhead.
pub(crate) fn probe_terminal_cols() -> Option<u16> {
    crossterm::terminal::size().ok().map(|(cols, _rows)| cols)
}

/// Truncate `s` so its column-width does not exceed `max`. If
/// `max` is `None` (non-TTY render path) or already fits, returns the
/// input unchanged. Otherwise replaces the trailing overrun with `…`
/// so the user sees a visible cue that the row was clipped.
///
/// The width metric is a naive byte count via `chars().count()` —
/// adequate for the ASCII-dominated rows the dep-tree renderer emits
/// (ids, statuses, list slugs, English titles). Wider East Asian or
/// emoji titles will under-clip slightly; correctness here means "row
/// fits the visible terminal", not "row is byte-exact at the limit",
/// so over-conservatism on the truncation side is the right error.
pub(crate) fn truncate_to_cols(s: &str, max: Option<u16>) -> String {
    let Some(max) = max else { return s.to_string() };
    let max = max as usize;
    if max == 0 {
        return String::new();
    }
    let char_count = s.chars().count();
    if char_count <= max {
        return s.to_string();
    }
    // Reserve one column for the ellipsis.
    let keep = max.saturating_sub(1);
    let mut out: String = s.chars().take(keep).collect();
    out.push('…');
    out
}
