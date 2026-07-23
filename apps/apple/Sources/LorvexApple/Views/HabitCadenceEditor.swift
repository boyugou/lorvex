import LorvexCore
import SwiftUI

/// Cadence editor for the create/edit habit sheets. A three-way top picker
/// (Daily / Weekly / Monthly) reveals the detail control for the chosen rhythm:
/// Weekly splits into "specific days" (a weekday picker) and "times a week" (a
/// flexible count), and Monthly picks the day of the month its reminder fires.
///
/// The store keeps four internal modes (`daily` / `weekly` / `timesPerWeek` /
/// `monthly`); this view projects the two weekly modes under the single
/// top-level "Weekly" segment so the top control stays uncluttered.
struct HabitCadenceEditor: View {
  @Bindable var store: AppStore
  let idPrefix: String

  private var mode: HabitCadenceMode { store.draftHabitCadenceMode }
  private var isWeeklyFamily: Bool { mode == .weekly || mode == .timesPerWeek }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Picker(
        String(localized: "habits.sheet.field.frequency", defaultValue: "Frequency", table: "Localizable", bundle: LorvexL10n.bundle),
        selection: topLevelBinding
      ) {
        Text(LocalizedStringResource("habits.sheet.frequency.daily", defaultValue: "Daily", table: "Localizable", bundle: LorvexL10n.bundle)).tag(HabitCadenceMode.daily)
        Text(LocalizedStringResource("habits.sheet.frequency.weekly", defaultValue: "Weekly", table: "Localizable", bundle: LorvexL10n.bundle)).tag(HabitCadenceMode.weekly)
        Text(LocalizedStringResource("habits.sheet.frequency.monthly", defaultValue: "Monthly", table: "Localizable", bundle: LorvexL10n.bundle)).tag(HabitCadenceMode.monthly)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityIdentifier("\(idPrefix).frequency")

      if isWeeklyFamily {
        Picker(
          String(localized: "habits.sheet.cadence.weekly_style", defaultValue: "Weekly style", table: "Localizable", bundle: LorvexL10n.bundle),
          selection: weeklyStyleBinding
        ) {
          Text(LocalizedStringResource("habits.sheet.cadence.specific_days", defaultValue: "Specific days", table: "Localizable", bundle: LorvexL10n.bundle)).tag(HabitCadenceMode.weekly)
          Text(LocalizedStringResource("habits.sheet.cadence.times_a_week", defaultValue: "Times per week", table: "Localizable", bundle: LorvexL10n.bundle)).tag(HabitCadenceMode.timesPerWeek)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("\(idPrefix).weeklyStyle")

        if mode == .weekly {
          HStack(alignment: .center, spacing: LorvexDesign.Spacing.xs) {
            HabitWeekdayPicker(selection: $store.draftHabitWeekdays, idPrefix: idPrefix)
            spreadEvenlyMenu
          }
        } else {
          Stepper(value: $store.draftHabitTimesPerWeek, in: 1...7) {
            Text(String(
              localized: "habits.sheet.cadence.times_per_week_label",
              defaultValue: "\(store.draftHabitTimesPerWeek) times per week",
              table: "Localizable",
              bundle: LorvexL10n.bundle))
              .font(LorvexDesign.Typography.primaryText)
          }
          .accessibilityIdentifier("\(idPrefix).timesPerWeek")
        }
      } else if mode == .monthly {
        Stepper(value: $store.draftHabitDayOfMonth, in: 1...31) {
          Text(String(
            format: String(
              localized: "habits.sheet.cadence.month_day_label",
              defaultValue: "On day %lld",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            store.draftHabitDayOfMonth))
            .font(LorvexDesign.Typography.primaryText)
        }
        .accessibilityIdentifier("\(idPrefix).dayOfMonth")
      }
    }
  }

  private var spreadEvenlyMenu: some View {
    Menu {
      ForEach(2...5, id: \.self) { n in
        Button {
          store.draftHabitWeekdays = Self.evenlyDistributedWeekdays(n)
        } label: {
          Text(String(
            format: String(
              localized: "habits.sheet.cadence.spread_n_days", defaultValue: "%lld days",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            n))
        }
      }
    } label: {
      Image(systemName: "wand.and.stars")
        .font(LorvexDesign.Typography.secondaryText)
        .frame(width: 30, height: 30)
        .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s, style: .continuous))
    }
    .menuStyle(.borderlessButton)
    .help(String(
      localized: "habits.sheet.cadence.spread_evenly", defaultValue: "Spread evenly",
      table: "Localizable",
      bundle: LorvexL10n.bundle))
    .accessibilityLabel(String(
      localized: "habits.sheet.cadence.spread_evenly", defaultValue: "Spread evenly",
      table: "Localizable",
      bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("\(idPrefix).spreadEvenly")
  }

  /// Projects the four store modes onto the three top-level segments, keeping a
  /// flexible (`timesPerWeek`) selection under "Weekly" rather than snapping it
  /// back to specific days.
  private var topLevelBinding: Binding<HabitCadenceMode> {
    Binding(
      get: {
        switch store.draftHabitCadenceMode {
        case .weekly, .timesPerWeek: return .weekly
        case .monthly: return .monthly
        case .daily: return .daily
        }
      },
      set: { newTop in
        switch newTop {
        case .weekly:
          if store.draftHabitCadenceMode != .timesPerWeek {
            store.draftHabitCadenceMode = .weekly
          }
        case .monthly:
          store.draftHabitCadenceMode = .monthly
        case .daily, .timesPerWeek:
          store.draftHabitCadenceMode = .daily
        }
      }
    )
  }

  private var weeklyStyleBinding: Binding<HabitCadenceMode> {
    Binding(
      get: { store.draftHabitCadenceMode == .timesPerWeek ? .timesPerWeek : .weekly },
      set: { store.draftHabitCadenceMode = $0 }
    )
  }

  /// `count` weekdays spread across the week, as ``WeekDay`` raw values
  /// (0 = Mon … 6 = Sun). Curated rather than computed so the result matches how
  /// people actually space habits (3 → Mon/Wed/Fri, 4 → Mon/Tue/Thu/Fri).
  static func evenlyDistributedWeekdays(_ count: Int) -> Set<Int> {
    switch max(1, min(count, 7)) {
    case 1: return [0]
    case 2: return [0, 3]
    case 3: return [0, 2, 4]
    case 4: return [0, 1, 3, 4]
    case 5: return [0, 1, 2, 3, 4]
    case 6: return [0, 1, 2, 3, 4, 5]
    default: return [0, 1, 2, 3, 4, 5, 6]
    }
  }
}

/// A row of seven toggleable weekday pills (Mon … Sun, localized) bound to a set
/// of ``WeekDay`` raw values (0 = Mon … 6 = Sun). The shared weekday control for
/// both habit cadence and task recurrence, so the two read identically.
struct HabitWeekdayPicker: View {
  @Binding var selection: Set<Int>
  let idPrefix: String
  /// When `false` (habit cadence) the last selected day can't be cleared, so a
  /// weekly habit is never "scheduled on no days". When `true` (task recurrence)
  /// an empty set is allowed — a weekly rule with no days repeats on its anchor
  /// weekday.
  var allowsEmpty: Bool = false

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<7, id: \.self) { raw in
        let isOn = selection.contains(raw)
        Button {
          toggle(raw)
        } label: {
          Text(Self.shortSymbol(raw))
            .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
              isOn
                ? AnyShapeStyle(LorvexDesign.Palette.accent)
                : AnyShapeStyle(.quaternary.opacity(0.55)),
              in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.fullSymbol(raw))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("\(idPrefix).weekday.\(raw)")
      }
    }
  }

  /// Toggle `raw`; unless `allowsEmpty`, never clear the last selected day (a
  /// weekly cadence with no days would silently mean "every day").
  private func toggle(_ raw: Int) {
    if selection.contains(raw) {
      if allowsEmpty || selection.count > 1 { selection.remove(raw) }
    } else {
      selection.insert(raw)
    }
  }

  /// Locale-aware short weekday name ("Mon"). `WeekDay` is Monday-first
  /// (Mon = 0); `Calendar.shortWeekdaySymbols` is Sunday-first, hence `(raw+1)%7`.
  static func shortSymbol(_ raw: Int) -> String {
    let symbols = Calendar.current.shortWeekdaySymbols
    let index = (raw + 1) % 7
    return symbols.indices.contains(index) ? symbols[index] : "?"
  }

  static func fullSymbol(_ raw: Int) -> String {
    let symbols = Calendar.current.weekdaySymbols
    let index = (raw + 1) % 7
    return symbols.indices.contains(index) ? symbols[index] : "?"
  }
}
