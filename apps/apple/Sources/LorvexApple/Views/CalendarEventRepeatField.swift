import LorvexCore
import SwiftUI

/// The "Repeat" control for the calendar create/edit form. Edits a
/// ``TaskRecurrenceRule`` binding through the common cases — None / Daily /
/// Weekly / Monthly / Yearly, an interval, a weekday set for weekly, and a
/// day-of-month for monthly — the same vocabulary the task recurrence editor and
/// habit cadence editor expose, not full RFC-5545 authoring.
///
/// `referenceDate` seeds sensible defaults when a cadence is first chosen: a
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
  /// The draft event's start date, used to seed the initial weekday / month-day.
  let referenceDate: Date
  /// Accessibility-id namespace, matching the form's other fields
  /// (`createCalendarEvent` / `editCalendarEvent`).
  let idPrefix: String

  private static let weekdayCodes = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

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
          ForEach(RepeatChoice.allCases.filter { $0 != .custom || isOpaque }, id: \.self) { option in
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
    }
    .animation(.snappy(duration: 0.18), value: recurrence)
    .onChange(of: referenceDate) { _, newDate in
      guard var rule = recurrence else { return }
      switch automaticallyDerivedAxis {
      case .weekly where rule.freq == .weekly:
        rule.byDay = [Self.weekdayCode(for: newDate)]
        recurrence = rule
      case .monthly where rule.freq == .monthly:
        rule.byMonthDay = [Self.dayOfMonth(of: newDate)]
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
        Text(intervalLabel(rule))
          .font(LorvexDesign.Typography.secondaryText)
          .monospacedDigit()
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityIdentifier("\(idPrefix).repeat.interval")
      .accessibilityValue(intervalLabel(rule))
    }

    if rule.freq == .weekly {
      // Same localized weekday pills as the task recurrence + habit cadence
      // editors, so the three read identically. Empty is allowed — a weekly rule
      // with no days repeats on its anchor weekday.
      HabitWeekdayPicker(
        selection: weekdays, idPrefix: "\(idPrefix).repeat", allowsEmpty: true)
    } else if rule.freq == .monthly {
      DraftSheetControlRow(
        title: String(localized: "calendar.repeat.on_day", defaultValue: "On day", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "calendar"
      ) {
        Stepper(value: dayOfMonth, in: 1...31) {
          Text("\(dayOfMonth.wrappedValue)")
            .font(LorvexDesign.Typography.secondaryText)
            .monospacedDigit()
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("\(idPrefix).repeat.dayOfMonth")
        .accessibilityValue("\(dayOfMonth.wrappedValue)")
      }
    }

    Text(rule.localizedDisplaySummary())
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("\(idPrefix).repeat.summary")
  }

  private func intervalLabel(_ rule: TaskRecurrenceRule) -> String {
    String(
      format: String(localized: "recurrence.summary.interval", defaultValue: "Every %1$lld %2$@", table: "Localizable", bundle: LorvexL10n.bundle),
      max(1, rule.interval ?? 1),
      rule.freq.localizedIntervalUnitPlural)
  }

  // MARK: Bindings that project onto the single typed rule

  private var choice: Binding<RepeatChoice> {
    Binding(
      get: { isOpaque && recurrence == nil ? .custom : RepeatChoice(frequency: recurrence?.freq) },
      set: { option in
        guard option != .custom else { return }
        guard let freq = option.frequency else {
          automaticallyDerivedAxis = nil
          recurrence = nil
          return
        }
        let changedFrequency = recurrence?.freq != freq
        recurrence = Self.ruleFor(
          frequency: freq, from: recurrence, referenceDate: referenceDate)
        if changedFrequency {
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
      get: { recurrence?.byMonthDay?.first ?? Self.dayOfMonth(of: referenceDate) },
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

  /// Build a fresh rule for `frequency`, preserving the existing interval and
  /// seeding weekly/monthly detail from the reference date.
  static func ruleFor(
    frequency: TaskRecurrenceRule.Frequency,
    from existing: TaskRecurrenceRule?,
    referenceDate: Date
  ) -> TaskRecurrenceRule {
    if let existing, existing.freq == frequency { return existing }
    let interval = existing?.interval ?? 1
    let until = existing?.until
    let count = existing?.count
    switch frequency {
    case .weekly:
      return TaskRecurrenceRule(
        freq: .weekly, interval: interval,
        byDay: [Self.weekdayCode(for: referenceDate)], until: until, count: count)
    case .monthly:
      return TaskRecurrenceRule(
        freq: .monthly, interval: interval,
        byMonthDay: [Self.dayOfMonth(of: referenceDate)], until: until, count: count)
    case .daily, .yearly:
      return TaskRecurrenceRule(
        freq: frequency, interval: interval, until: until, count: count)
    }
  }

  private static func dayOfMonth(of date: Date) -> Int {
    Calendar.current.component(.day, from: date)
  }

  /// The RFC-5545 weekday code ("MO"…"SU") for `date`. `Calendar.weekday` is
  /// 1 = Sunday … 7 = Saturday; the code table is Monday-first, so shift by 5.
  private static func weekdayCode(for date: Date) -> String {
    let weekday = Calendar.current.component(.weekday, from: date)
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
