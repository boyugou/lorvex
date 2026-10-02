import Foundation

/// The words a recurrence rule is shown in, shared by every surface.
///
/// A rule reads the same on the Mac, iPhone, and iPad: the frequency picker's
/// names ("Daily"), the interval ("Every week", "Every 3 weeks"), the cadence a
/// task field or capture preview shows ("Every week · Mon, Wed"), and the
/// editor's full summary ("Every 2 weeks · Mon, Wed · 10 times · after
/// completion"). The words come from LorvexCore's catalog, so one translation
/// serves each surface; weekdays are named through ``LorvexRecurrenceWeekdays``.
public extension TaskRecurrenceRule.Frequency {
  /// The frequency picker's name for this frequency ("Daily", "Weekly").
  var localizedDisplayName: String {
    switch self {
    case .daily:
      String(localized: "recurrence.frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: CoreL10n.bundle)
    case .weekly:
      String(localized: "recurrence.frequency.weekly", defaultValue: "Weekly", table: "Localizable", bundle: CoreL10n.bundle)
    case .monthly:
      String(localized: "recurrence.frequency.monthly", defaultValue: "Monthly", table: "Localizable", bundle: CoreL10n.bundle)
    case .yearly:
      String(localized: "recurrence.frequency.yearly", defaultValue: "Yearly", table: "Localizable", bundle: CoreL10n.bundle)
    }
  }

  /// The repeat interval as a phrase: "Every week" for one period, "Every 3
  /// weeks" for more. The interval stepper, the Repeat menu, and every rule
  /// summary say the interval through this one phrase.
  ///
  /// Exactly one period has its own entry without a number, because a plural
  /// form cannot single it out: Russian's "one" form also covers 21 and 31.
  /// Each longer interval is one plural entry, so every language words the
  /// number, the unit, and their agreement as a whole.
  func localizedEveryInterval(_ count: Int) -> String {
    switch (self, count) {
    case (.daily, 1):
      String(localized: "recurrence.every_day", defaultValue: "Every day", table: "Localizable", bundle: CoreL10n.bundle)
    case (.daily, _):
      String(
        localized: "recurrence.every_n_days", defaultValue: "Every \(count) days",
        table: "Localizable", bundle: CoreL10n.bundle)
    case (.weekly, 1):
      String(localized: "recurrence.every_week", defaultValue: "Every week", table: "Localizable", bundle: CoreL10n.bundle)
    case (.weekly, _):
      String(
        localized: "recurrence.every_n_weeks", defaultValue: "Every \(count) weeks",
        table: "Localizable", bundle: CoreL10n.bundle)
    case (.monthly, 1):
      String(localized: "recurrence.every_month", defaultValue: "Every month", table: "Localizable", bundle: CoreL10n.bundle)
    case (.monthly, _):
      String(
        localized: "recurrence.every_n_months", defaultValue: "Every \(count) months",
        table: "Localizable", bundle: CoreL10n.bundle)
    case (.yearly, 1):
      String(localized: "recurrence.every_year", defaultValue: "Every year", table: "Localizable", bundle: CoreL10n.bundle)
    case (.yearly, _):
      String(
        localized: "recurrence.every_n_years", defaultValue: "Every \(count) years",
        table: "Localizable", bundle: CoreL10n.bundle)
    }
  }
}

public extension TaskRecurrenceRule.Anchor {
  /// The anchor's name in the editor's segmented control.
  var localizedDisplayName: String {
    switch self {
    case .schedule:
      String(localized: "recurrence.anchor.schedule", defaultValue: "Regularly", table: "Localizable", bundle: CoreL10n.bundle)
    case .completion:
      String(
        localized: "recurrence.anchor.completion", defaultValue: "After completion",
        table: "Localizable", bundle: CoreL10n.bundle)
    }
  }

  /// One line explaining the anchor, shown beneath the segmented control.
  var localizedHint: String {
    switch self {
    case .schedule:
      String(
        localized: "recurrence.anchor.schedule.hint",
        defaultValue: "Repeats on a fixed schedule, regardless of when you finish.",
        table: "Localizable", bundle: CoreL10n.bundle)
    case .completion:
      String(
        localized: "recurrence.anchor.completion.hint",
        defaultValue: "The next one is scheduled relative to when you complete this, so a late finish pushes it forward.",
        table: "Localizable", bundle: CoreL10n.bundle)
    }
  }
}

public extension TaskRecurrenceRule {
  /// The rule's cadence alone: the interval, then the weekdays ("Every week ·
  /// Mon, Wed", "Every 3 months", "Every month · last Fri"). Long enough to be
  /// unambiguous and short enough for one row, so the task detail field, the
  /// iPhone task sentence, and the capture previews show it as is; how the rule
  /// ends, its anchor, and skipped dates stay in
  /// ``localizedDisplaySummary(exceptions:)``. A stored interval below one
  /// reads as one period.
  var localizedCadence: String {
    let every = freq.localizedEveryInterval(max(1, interval ?? 1))
    guard let byDay, !byDay.isEmpty else { return every }
    return "\(every) · \(LorvexRecurrenceWeekdays.summary(byDay))"
  }

  /// The full one-line rule the repeat editors show: the cadence, then how the
  /// rule ends, its anchor, and how many dates were skipped ("Every 2 weeks ·
  /// Mon, Wed · 10 times · 1 skipped"). `exceptions` are the skipped dates.
  func localizedDisplaySummary(exceptions: [String] = []) -> String {
    var parts = [localizedCadence]
    if let count {
      parts.append(
        String(
          localized: "recurrence.summary.count", defaultValue: "\(count) times",
          table: "Localizable", bundle: CoreL10n.bundle))
    } else if let until {
      parts.append(
        String(
          format: String(
            localized: "recurrence.summary.until", defaultValue: "until %@",
            table: "Localizable", bundle: CoreL10n.bundle),
          Self.localizedUntil(until)))
    }
    if anchor == .completion {
      parts.append(
        String(
          localized: "recurrence.summary.after_completion", defaultValue: "after completion",
          table: "Localizable", bundle: CoreL10n.bundle))
    }
    if !exceptions.isEmpty {
      parts.append(
        String(
          localized: "recurrence.summary.skipped", defaultValue: "\(exceptions.count) skipped",
          table: "Localizable", bundle: CoreL10n.bundle))
    }
    return parts.joined(separator: " · ")
  }

  /// The rule's end date in the locale's medium date style. `until` is a
  /// stored day (`yyyy-MM-dd`, read in the device's zone so it shows as the
  /// same day) or, defensively, an ISO datetime; any other shape is shown as
  /// written.
  private static func localizedUntil(_ until: String) -> String {
    if let date = LorvexDateFormatters.ymd.date(from: until)
      ?? LorvexDateFormatters.iso8601.date(from: until) {
      return LorvexDateFormatters.string(date, dateStyle: .medium, timeZone: .autoupdatingCurrent)
    }
    return until
  }
}
