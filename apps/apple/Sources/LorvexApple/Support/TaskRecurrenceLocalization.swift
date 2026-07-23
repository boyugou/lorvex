import Foundation
import LorvexCore

/// macOS-localized presentation of recurrence rules.
///
/// `LorvexCore` is platform-neutral and ships English-only `displayName` /
/// `displaySummary` helpers (consumed as-is by surfaces that localize through
/// their own catalogs). The macOS app renders the same information through its
/// string catalog so the recurrence picker, interval unit, and the "Currently …"
/// summary read in the user's language across all supported locales.
///
/// Weekday tokens in `byDay` are RRULE codes ("MO"…"SU"); the summary renders
/// them as the locale's short weekday names (matching the weekday selector's
/// pills) via ``TaskRecurrenceRule/localizedWeekdays(_:)``.
extension TaskRecurrenceRule.Frequency {
  var localizedDisplayName: String {
    switch self {
    case .daily: String(localized: "recurrence.frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: LorvexL10n.bundle)
    case .weekly: String(localized: "recurrence.frequency.weekly", defaultValue: "Weekly", table: "Localizable", bundle: LorvexL10n.bundle)
    case .monthly: String(localized: "recurrence.frequency.monthly", defaultValue: "Monthly", table: "Localizable", bundle: LorvexL10n.bundle)
    case .yearly: String(localized: "recurrence.frequency.yearly", defaultValue: "Yearly", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var localizedIntervalUnitPlural: String {
    switch self {
    case .daily: String(localized: "recurrence.unit.days", defaultValue: "days", table: "Localizable", bundle: LorvexL10n.bundle)
    case .weekly: String(localized: "recurrence.unit.weeks", defaultValue: "weeks", table: "Localizable", bundle: LorvexL10n.bundle)
    case .monthly: String(localized: "recurrence.unit.months", defaultValue: "months", table: "Localizable", bundle: LorvexL10n.bundle)
    case .yearly: String(localized: "recurrence.unit.years", defaultValue: "years", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}

extension TaskRecurrenceRule.Anchor {
  /// Segmented-control label.
  var localizedDisplayName: String {
    switch self {
    case .schedule:
      String(localized: "recurrence.anchor.schedule", defaultValue: "Regularly", table: "Localizable", bundle: LorvexL10n.bundle)
    case .completion:
      String(
        localized: "recurrence.anchor.completion", defaultValue: "After completion",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
  }

  /// One-line explanation shown beneath the segmented control.
  var localizedHint: String {
    switch self {
    case .schedule:
      String(
        localized: "recurrence.anchor.schedule.hint",
        defaultValue: "Repeats on a fixed schedule, regardless of when you finish.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    case .completion:
      String(
        localized: "recurrence.anchor.completion.hint",
        defaultValue: "The next one is scheduled relative to when you complete this, so a late finish pushes it forward.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
  }
}

extension TaskRecurrenceRule {
  func localizedDisplaySummary(exceptions: [String] = []) -> String {
    var parts: [String] = []
    if let interval, interval > 1 {
      parts.append(String(
        format: String(localized: "recurrence.summary.interval", defaultValue: "Every %1$lld %2$@", table: "Localizable", bundle: LorvexL10n.bundle),
        interval,
        freq.localizedIntervalUnitPlural
      ))
    } else {
      parts.append(freq.localizedDisplayName)
    }
    if let byDay, !byDay.isEmpty {
      parts.append(Self.localizedWeekdays(byDay))
    }
    if let count {
      parts.append(String(
        localized: "recurrence.summary.count",
        defaultValue: "\(count) times",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
    } else if let until {
      parts.append(String(
        format: String(localized: "recurrence.summary.until", defaultValue: "until %@", table: "Localizable", bundle: LorvexL10n.bundle),
        Self.localizedUntil(until)
      ))
    }
    if anchor == .completion {
      parts.append(String(
        localized: "recurrence.summary.after_completion", defaultValue: "after completion",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
    }
    if !exceptions.isEmpty {
      parts.append(String(
        format: String(localized: "recurrence.summary.skipped", defaultValue: "%lld skipped", table: "Localizable", bundle: LorvexL10n.bundle),
        exceptions.count
      ))
    }
    return parts.joined(separator: " · ")
  }

  /// Localized short weekday names ("Mon, Wed, Fri") for a list of RRULE BYDAY
  /// codes, ordered Monday-first to match the weekday selector's pills. Unknown
  /// tokens pass through unchanged.
  private static func localizedWeekdays(_ codes: [String]) -> String {
    let order = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    // `shortWeekdaySymbols` is Sunday-first; map each RRULE code to its index.
    let symbolIndex: [String: Int] = [
      "SU": 0, "MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6,
    ]
    let symbols = Calendar.current.shortWeekdaySymbols
    let names = codes
      .sorted { (order.firstIndex(of: $0) ?? order.count) < (order.firstIndex(of: $1) ?? order.count) }
      .map { code -> String in
        guard let index = symbolIndex[code], symbols.indices.contains(index) else { return code }
        return symbols[index]
      }
    return names.joined(separator: ", ")
  }

  /// The recurrence end date for display. `until` is an ISO day or datetime
  /// string; render it in the locale's date style, falling back to the raw
  /// value for any shape that neither formatter parses.
  private static func localizedUntil(_ until: String) -> String {
    if let date = LorvexDateFormatters.ymd.date(from: until)
      ?? LorvexDateFormatters.iso8601.date(from: until) {
      return date.formatted(date: .abbreviated, time: .omitted)
    }
    return until
  }
}
