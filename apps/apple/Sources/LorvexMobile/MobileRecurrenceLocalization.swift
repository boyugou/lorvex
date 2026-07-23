import Foundation
import LorvexCore

/// iOS/iPadOS/visionOS-localized presentation of recurrence rules, mirroring the
/// macOS `TaskRecurrenceLocalization`.
///
/// `LorvexCore` ships English-only `displayName` / `displaySummary` helpers so
/// platform-neutral code stays presentation-free; each surface renders them
/// through its own string catalog. Mobile routes through `MobileL10n` here so the
/// recurrence picker, the interval stepper, and the "Currently …" summary read in
/// the user's language. The interval unit is a CLDR plural ("day"/"days" and
/// their per-language forms) rather than an English `+"s"`, so number agreement
/// is correct in every locale.
///
extension TaskRecurrenceRule.Frequency {
  var mobileLocalizedDisplayName: String {
    switch self {
    case .daily:
      String(
        localized: "recurrence.frequency.daily", defaultValue: "Daily", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .weekly:
      String(
        localized: "recurrence.frequency.weekly", defaultValue: "Weekly", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .monthly:
      String(
        localized: "recurrence.frequency.monthly", defaultValue: "Monthly", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .yearly:
      String(
        localized: "recurrence.frequency.yearly", defaultValue: "Yearly", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  /// A localized "Every N days" phrase whose CLDR plural variations carry the
  /// whole clause, so both the number and the noun agree for `count` ("Every 1
  /// day" vs "Every 3 days") in every language. The full phrase — not just the
  /// unit — is the plural because the xcstrings compiler requires each plural
  /// variation to reference the count.
  func mobileLocalizedEveryInterval(_ count: Int) -> String {
    switch self {
    case .daily:
      return String(
        localized: "recurrence.stepper.every_days", defaultValue: "Every \(count) days",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .weekly:
      return String(
        localized: "recurrence.stepper.every_weeks", defaultValue: "Every \(count) weeks",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .monthly:
      return String(
        localized: "recurrence.stepper.every_months", defaultValue: "Every \(count) months",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .yearly:
      return String(
        localized: "recurrence.stepper.every_years", defaultValue: "Every \(count) years",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

extension TaskRecurrenceRule.Anchor {
  var mobileLocalizedDisplayName: String {
    switch self {
    case .schedule:
      String(
        localized: "recurrence.anchor.schedule", defaultValue: "Regularly",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .completion:
      String(
        localized: "recurrence.anchor.completion", defaultValue: "After completion",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  var mobileLocalizedHint: String {
    switch self {
    case .schedule:
      String(
        localized: "recurrence.anchor.schedule.hint",
        defaultValue: "Repeats on a fixed schedule, regardless of when you finish.",
        table: "Localizable", bundle: MobileL10n.bundle)
    case .completion:
      String(
        localized: "recurrence.anchor.completion.hint",
        defaultValue: "The next one is scheduled relative to when you complete this, so a late finish pushes it forward.",
        table: "Localizable", bundle: MobileL10n.bundle)
    }
  }
}

extension TaskRecurrenceRule {
  /// The localized one-line summary shown beneath the recurrence toggle, e.g.
  /// "Every 2 weeks · MO, WE · 10 times". Mirrors the core `displaySummary`
  /// structure but renders every literal through `MobileL10n`.
  func mobileLocalizedDisplaySummary(exceptions: [String] = []) -> String {
    var parts: [String] = []
    if let interval, interval > 1 {
      parts.append(freq.mobileLocalizedEveryInterval(interval))
    } else {
      parts.append(freq.mobileLocalizedDisplayName)
    }
    if let byDay, !byDay.isEmpty {
      parts.append(Self.mobileLocalizedWeekdays(byDay))
    }
    if let count {
      parts.append(
        String(
          localized: "recurrence.summary.count", defaultValue: "\(count) times",
          table: "Localizable", bundle: MobileL10n.bundle))
    } else if let until {
      parts.append(
        String(
          format: String(
            localized: "recurrence.summary.until", defaultValue: "until %@", table: "Localizable",
            bundle: MobileL10n.bundle),
          Self.mobileLocalizedUntil(until)))
    }
    if anchor == .completion {
      parts.append(
        String(
          localized: "recurrence.summary.after_completion", defaultValue: "after completion",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
    if !exceptions.isEmpty {
      parts.append(
        String(
          format: String(
            localized: "recurrence.summary.skipped", defaultValue: "%lld skipped",
            table: "Localizable", bundle: MobileL10n.bundle),
          exceptions.count))
    }
    return parts.joined(separator: " · ")
  }

  /// The recurrence end date for display. `until` is an ISO day or datetime
  /// string; render it in the locale's date style, falling back to the raw value
  /// for any shape that neither formatter parses.
  private static func mobileLocalizedUntil(_ until: String) -> String {
    if let date = LorvexDateFormatters.ymd.date(from: until)
      ?? LorvexDateFormatters.iso8601.date(from: until) {
      let formatter = DateFormatter()
      formatter.locale = MobileL10n.locale
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      return formatter.string(from: date)
    }
    return until
  }

  private static func mobileLocalizedWeekdays(_ codes: [String]) -> String {
    var localizedCalendar = Calendar.current
    localizedCalendar.locale = MobileL10n.locale
    let symbols = localizedCalendar.shortWeekdaySymbols
    let symbolIndex: [String: Int] = [
      "SU": 0, "MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6,
    ]
    return codes.map { token in
      let code = String(token.suffix(2))
      guard let index = symbolIndex[code], symbols.indices.contains(index) else { return token }
      let prefix = token.dropLast(min(2, token.count))
      return prefix.isEmpty ? symbols[index] : "\(prefix) \(symbols[index])"
    }.joined(separator: ", ")
  }
}
