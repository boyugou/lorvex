import LorvexCore
import SwiftUI

/// The habit cadence editor, shared by the create and edit sheets. Binds to a
/// ``MobileHabitDraft``'s cadence fields; ``MobileHabitDraft/cadenceInput`` turns
/// the selections into the typed cadence the core's create/update habit calls
/// take. Mirrors the macOS `HabitCadenceEditor` (Daily / Weekly / Monthly, with
/// weekly split into specific-days vs. a per-week count).
struct MobileHabitCadenceSection: View {
  @Binding var draft: MobileHabitDraft
  let idPrefix: String

  var body: some View {
    Section(String(localized: "habits.section.cadence", defaultValue: "Cadence", table: "Localizable", bundle: MobileL10n.bundle)) {
      Picker(
        String(localized: "habits.detail.frequency", defaultValue: "Frequency", table: "Localizable", bundle: MobileL10n.bundle),
        selection: $draft.cadenceMode.animation(.snappy)
      ) {
        Text(String(localized: "habits.frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: MobileL10n.bundle)).tag(MobileHabitCadenceMode.daily)
        Text(String(localized: "habits.frequency.weekly", defaultValue: "Weekly", table: "Localizable", bundle: MobileL10n.bundle)).tag(MobileHabitCadenceMode.weekly)
        Text(String(localized: "habits.frequency.monthly", defaultValue: "Monthly", table: "Localizable", bundle: MobileL10n.bundle)).tag(MobileHabitCadenceMode.monthly)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("\(idPrefix).cadence.mode")

      switch draft.cadenceMode {
      case .daily:
        EmptyView()
      case .weekly:
        weeklyControls
      case .monthly:
        Stepper(value: $draft.dayOfMonth, in: 1...31) {
          Text(
            String(
              format: String(localized: "habits.cadence.day_of_month_value", defaultValue: "Day %lld", table: "Localizable", bundle: MobileL10n.bundle),
              draft.dayOfMonth))
        }
        .accessibilityIdentifier("\(idPrefix).cadence.dayOfMonth")
      }
    }
  }

  @ViewBuilder
  private var weeklyControls: some View {
    Picker(
      String(localized: "habits.cadence.repeat_by", defaultValue: "Repeat by", table: "Localizable", bundle: MobileL10n.bundle),
      selection: $draft.weeklyStyle.animation(.snappy)
    ) {
      Text(String(localized: "habits.cadence.specific_days", defaultValue: "Specific days", table: "Localizable", bundle: MobileL10n.bundle))
        .tag(MobileHabitWeeklyStyle.specificDays)
      Text(String(localized: "habits.cadence.times_a_week", defaultValue: "Times per week", table: "Localizable", bundle: MobileL10n.bundle))
        .tag(MobileHabitWeeklyStyle.timesPerWeek)
    }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("\(idPrefix).cadence.weeklyStyle")

    switch draft.weeklyStyle {
    case .specificDays:
      MobileWeekdayPicker(
        selection: $draft.weekdays, idPrefix: "\(idPrefix).cadence", allowsEmpty: false)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    case .timesPerWeek:
      Stepper(value: $draft.timesPerWeek, in: 1...7) {
        Text(
          String(
            format: String(localized: "habits.cadence.times_per_week_value", defaultValue: "%lld× per week", table: "Localizable", bundle: MobileL10n.bundle),
            draft.timesPerWeek))
      }
      .accessibilityIdentifier("\(idPrefix).cadence.timesPerWeek")
    }
  }
}

/// A Monday-first row of seven toggleable weekday pills. `selection` holds the
/// selected weekdays as Monday-first ints (0=Mon … 6=Sun). Habit cadence passes
/// `allowsEmpty: false` so its last day stays selected; task recurrence permits
/// an empty set because the core can infer the weekday from the task's anchor.
struct MobileWeekdayPicker: View {
  @Binding var selection: Set<Int>
  let idPrefix: String
  let allowsEmpty: Bool

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<7, id: \.self) { day in
        pill(for: day)
      }
    }
    .padding(.vertical, 2)
  }

  private func pill(for day: Int) -> some View {
    let isOn = selection.contains(day)
    return Button {
      toggle(day)
    } label: {
      Text(Self.shortSymbol(day))
        .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(pillBackground(isOn: isOn), in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("\(idPrefix).weekday\(day)")
    .accessibilityLabel(Self.fullSymbol(day))
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }

  private func pillBackground(isOn: Bool) -> AnyShapeStyle {
    isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary)
  }

  private func toggle(_ day: Int) {
    withAnimation(.snappy) {
      if selection.contains(day) {
        if allowsEmpty || selection.count > 1 { selection.remove(day) }
      } else {
        selection.insert(day)
      }
    }
  }

  /// The very-short localized symbol for a Monday-first weekday index. The
  /// system's `veryShortWeekdaySymbols` is Sunday-first, so shift by one.
  private static func shortSymbol(_ mondayFirst: Int) -> String {
    let symbols = Calendar.current.veryShortWeekdaySymbols
    return symbols[(mondayFirst + 1) % 7]
  }

  private static func fullSymbol(_ mondayFirst: Int) -> String {
    let symbols = Calendar.current.weekdaySymbols
    return symbols[(mondayFirst + 1) % 7]
  }
}
