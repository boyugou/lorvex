import LorvexCore
import SwiftUI

/// The "Repeat" control for the calendar create/edit form. Edits a
/// ``TaskRecurrenceRule`` binding through the common cases — None / Daily /
/// Weekly / Monthly / Yearly, an interval, a weekday set for weekly, and a
/// day-of-month for monthly — the same vocabulary the task recurrence editor and
/// habit cadence editor expose, not full RFC-5545 authoring.
///
/// `referenceTiming` seeds defaults when a cadence is first chosen: a
/// weekly rule starts on the event's own weekday, a monthly rule on its
/// day-of-month. Events always repeat on the schedule anchor, so there is no
/// "after completion" mode here (that is task-only).
struct CalendarEventRepeatField: View {
  @Binding var recurrence: TaskRecurrenceRule?
  @State private var automaticallyDerivedAxis: AutomaticallyDerivedAxis?
  /// A future rule this client cannot decode. It is presented as Custom rather
  /// than None so an explicit switch to None can be distinguished from leaving
  /// the unknown value untouched.
  let isOpaque: Bool
  /// The draft start in the event's storage zone, where its repeat rule runs.
  let referenceTiming: CalendarEventTiming
  let displayTimeZone: TimeZone
  /// Accessibility-id namespace, matching the form's other fields
  /// (`createCalendarEvent` / `editCalendarEvent`).
  let idPrefix: String

  private static let weekdayCodes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

  private var isCustom: Bool { isOpaque || recurrence.map(Self.hasCustomPattern) == true }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      DraftSheetControlRow(
        title: String(localized: "calendar.field.repeat", defaultValue: "Repeat", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "repeat"
      ) {
        Picker(
          String(localized: "calendar.field.repeat", defaultValue: "Repeat", table: "Localizable", bundle: LorvexL10n.bundle),
          selection: choice
        ) {
          ForEach(RepeatChoice.allCases.filter { $0 != .custom || isCustom }, id: \.self) { option in
            Text(option.localizedLabel).tag(option)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("\(idPrefix).repeat")
      }

      if let rule = recurrence {
        detail(for: rule)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if isCustom {
        Text(String(
          localized: "calendar.repeat.custom.help",
          defaultValue: "Choose another repeat option to replace this pattern.",
          table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if (recurrence != nil || isOpaque),
        let zoneNote = referenceTiming.recurrenceTimeZoneNote(comparedTo: displayTimeZone)
      {
        Label(zoneNote, systemImage: "globe")
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("\(idPrefix).repeat.timeZone")
      }
    }
    .reduceMotionAnimation(.snappy(duration: 0.18), value: recurrence)
    .onChange(of: referenceTiming.startDate) { _, _ in
      guard var rule = recurrence, !Self.hasCustomPattern(rule) else { return }
      switch automaticallyDerivedAxis {
      case .weekly where rule.freq == .weekly:
        rule.byDay = [Self.weekdayCode(for: referenceTiming)]
        recurrence = rule
      case .monthly where rule.freq == .monthly:
        rule.byMonthDay = [Self.dayOfMonth(of: referenceTiming)]
        recurrence = rule
      case .weekly, .monthly, .none:
        break
      }
    }
  }

  @ViewBuilder
  private func detail(for rule: TaskRecurrenceRule) -> some View {
    DraftSheetControlRow(
      title: String(localized: "calendar.repeat.every", defaultValue: "Every", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "number"
    ) {
      Stepper(value: interval, in: 1...TaskRecurrenceEditorDraft.maximumInterval) {
        Text(interval.wrappedValue, format: .number)
          .font(LorvexDesign.Typography.secondaryText)
          .monospacedDigit()
      }
      .fixedSize()
      .accessibilityIdentifier("\(idPrefix).repeat.interval")
      .accessibilityLabel(String(
        localized: "calendar.repeat.every", defaultValue: "Every",
        table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityValue(intervalLabel(rule))
    }

    if !Self.hasCustomPattern(rule), rule.freq == .weekly {
      // Same localized weekday pills as the task recurrence + habit cadence
      // editors, so the three read identically. Empty is allowed — a weekly rule
      // with no days repeats on its anchor weekday.
      HabitWeekdayPicker(
        selection: weekdays, idPrefix: "\(idPrefix).repeat", allowsEmpty: true)
    } else if !Self.hasCustomPattern(rule), rule.freq == .monthly {
      DraftSheetControlRow(
        title: String(localized: "calendar.repeat.on_day", defaultValue: "On day", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "calendar"
      ) {
        Stepper(value: dayOfMonth, in: 1...31) {
          Text(dayOfMonth.wrappedValue, format: .number)
            .font(LorvexDesign.Typography.secondaryText)
            .monospacedDigit()
        }
        .fixedSize()
        .accessibilityIdentifier("\(idPrefix).repeat.dayOfMonth")
        .accessibilityLabel(String(
          localized: "calendar.repeat.on_day", defaultValue: "On day",
          table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityValue("\(dayOfMonth.wrappedValue)")
      }
    }

    Text(rule.localizedDisplaySummary(
      anchorDay: LorvexDateFormatters.ymdUTC.date(from: referenceTiming.startDate)))
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("\(idPrefix).repeat.summary")
  }

  private func intervalLabel(_ rule: TaskRecurrenceRule) -> String {
    rule.freq.localizedEveryInterval(max(1, rule.interval ?? 1))
  }

  // MARK: Bindings that project onto the single typed rule

  private var choice: Binding<RepeatChoice> {
    Binding(
      get: { isCustom ? .custom : RepeatChoice(frequency: recurrence?.freq) },
      set: { option in
        guard option != .custom else { return }
        guard let freq = option.frequency else {
          automaticallyDerivedAxis = nil
          recurrence = nil
          return
        }
        let replacesCustomPattern = recurrence.map(Self.hasCustomPattern) == true
        let changedPattern = recurrence?.freq != freq || replacesCustomPattern
        recurrence = Self.ruleFor(
          frequency: freq, from: recurrence, referenceTiming: referenceTiming,
          replacingCustomPattern: replacesCustomPattern)
        if changedPattern {
          switch freq {
          case .weekly: automaticallyDerivedAxis = .weekly
          case .monthly: automaticallyDerivedAxis = .monthly
          case .daily, .yearly: automaticallyDerivedAxis = nil
          }
        }
      })
  }

  private var interval: Binding<Int> {
    Binding(
      get: { max(1, recurrence?.interval ?? 1) },
      set: { newValue in
        guard var rule = recurrence else { return }
        rule.interval = max(1, newValue)
        recurrence = rule
      })
  }

  private var weekdays: Binding<Set<Int>> {
    Binding(
      get: {
        Set((recurrence?.byDay ?? []).compactMap { Self.weekdayCodes.firstIndex(of: $0) })
      },
      set: { indices in
        guard var rule = recurrence else { return }
        automaticallyDerivedAxis = nil
        let codes = indices.sorted().compactMap {
          Self.weekdayCodes.indices.contains($0) ? Self.weekdayCodes[$0] : nil
        }
        rule.byDay = codes.isEmpty ? nil : codes
        recurrence = rule
      })
  }

  private var dayOfMonth: Binding<Int> {
    Binding(
      get: { recurrence?.byMonthDay?.first ?? Self.dayOfMonth(of: referenceTiming) },
      set: { newValue in
        guard var rule = recurrence else { return }
        automaticallyDerivedAxis = nil
        rule.byMonthDay = [min(max(newValue, 1), 31)]
        // Choosing an explicit month day replaces an ordinal-weekday mode such
        // as "first Monday"; keeping both hidden constraints would produce an
        // intersection the basic editor does not display.
        rule.byDay = nil
        rule.bySetPos = nil
        rule.wkst = nil
        recurrence = rule
      })
  }

  /// Whether the rule includes a pattern the basic weekday/month-day controls
  /// cannot express. Its interval remains editable without touching the pattern.
  static func hasCustomPattern(_ rule: TaskRecurrenceRule) -> Bool {
    guard rule.anchor == .schedule, rule.byMonth?.isEmpty != false,
      rule.bySetPos?.isEmpty != false, rule.wkst?.isEmpty != false
    else { return true }
    let weekdays = rule.byDay ?? []
    let monthDays = rule.byMonthDay ?? []
    switch rule.freq {
    case .daily, .yearly:
      return !weekdays.isEmpty || !monthDays.isEmpty
    case .weekly:
      return !monthDays.isEmpty || !weekdays.allSatisfy { weekdayCodes.contains($0) }
    case .monthly:
      return !weekdays.isEmpty || monthDays.count > 1
        || monthDays.contains { !(1...31).contains($0) }
    }
  }

  /// Build a basic rule, retaining the interval and ending condition. Choosing
  /// Monthly from Custom explicitly replaces even a monthly custom pattern;
  /// re-emitting the existing frequency without that intent is a no-op.
  static func ruleFor(
    frequency: TaskRecurrenceRule.Frequency,
    from existing: TaskRecurrenceRule?,
    referenceTiming: CalendarEventTiming,
    replacingCustomPattern: Bool = false
  ) -> TaskRecurrenceRule {
    if let existing, existing.freq == frequency, !replacingCustomPattern { return existing }
    let interval = existing?.interval ?? 1
    let until = existing?.until
    let count = existing?.count
    switch frequency {
    case .weekly:
      return TaskRecurrenceRule(
        freq: .weekly, interval: interval,
        byDay: [Self.weekdayCode(for: referenceTiming)], until: until, count: count)
    case .monthly:
      return TaskRecurrenceRule(
        freq: .monthly, interval: interval,
        byMonthDay: [Self.dayOfMonth(of: referenceTiming)], until: until, count: count)
    case .daily, .yearly:
      return TaskRecurrenceRule(
        freq: frequency, interval: interval, until: until, count: count)
    }
  }

  private static func dayOfMonth(of timing: CalendarEventTiming) -> Int {
    timing.calendar.component(.day, from: timing.start)
  }

  /// The RFC-5545 weekday code ("MO"…"SU") for the start. `Calendar.weekday` is
  /// 1 = Sunday … 7 = Saturday; the code table is Monday-first, so shift by 5.
  private static func weekdayCode(for timing: CalendarEventTiming) -> String {
    let weekday = timing.calendar.component(.weekday, from: timing.start)
    return weekdayCodes[(weekday + 5) % 7]
  }
}

private enum AutomaticallyDerivedAxis {
  case weekly
  case monthly
}

/// The Repeat menu's options: a "None" sentinel plus one per supported
/// frequency, in the order users expect (None first, then increasing period).
private enum RepeatChoice: Hashable, CaseIterable {
  case custom, none, daily, weekly, monthly, yearly

  init(frequency: TaskRecurrenceRule.Frequency?) {
    switch frequency {
    case .none: self = .none
    case .some(.daily): self = .daily
    case .some(.weekly): self = .weekly
    case .some(.monthly): self = .monthly
    case .some(.yearly): self = .yearly
    }
  }

  var frequency: TaskRecurrenceRule.Frequency? {
    switch self {
    case .custom: nil
    case .none: nil
    case .daily: .daily
    case .weekly: .weekly
    case .monthly: .monthly
    case .yearly: .yearly
    }
  }

  var localizedLabel: String {
    if self == .custom {
      return String(
        localized: "calendar.repeat.custom", defaultValue: "Custom",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    if let frequency { return frequency.localizedDisplayName }
    return String(localized: "calendar.repeat.none", defaultValue: "None", table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
