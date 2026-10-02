import LorvexCore
import SwiftUI

/// The habit inspector's By Weekday panel: how the habit's check-ins fall
/// across the week (``HabitWeekdayRhythm``), as one bar per weekday from the
/// first day of the user's week (``LorvexWeekdayOrder``), with a line naming
/// the strongest and the weakest days.
///
/// A bar's height is the share of that weekday's plan met in the window, the
/// last twelve weeks or the time since the first check-in; the header says
/// which. The bars of the strongest weekdays (all of them, when several tie)
/// are drawn in the full habit color, the others lighter, and every bar in
/// full color when the week is even. A weekday the habit is not planned on
/// shows a short dash in place of a bar. Each bar names its weekday, count,
/// and share in a help tag. The line names up to three tied weekdays at each
/// end; more than that is a pattern rather than a day, and goes unnamed.
/// Until two weeks of history exist the panel says so instead of drawing bars
/// that would read as a pattern.
struct HabitWeekdayPanel: View {
  let habit: LorvexHabit
  let rhythm: HabitWeekdayRhythm

  private var identity: Color { LorvexHabitPalette.baseColor(for: habit) }

  private static let barAreaHeight: CGFloat = 64

  var body: some View {
    InspectorPanel(accessibilityIdentifier: "habit.detail.weekdays.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          Label(
            String(localized: "habit_detail.weekdays.title", defaultValue: "By Weekday", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "chart.bar.xaxis"
          )
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(1)
          Spacer(minLength: LorvexDesign.Spacing.s)
          if rhythm.hasEnoughHistory, let window = windowLabel {
            Text(window)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        if rhythm.hasEnoughHistory {
          bars
          Text(insight)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("habit.detail.weekdays.insight")
        } else {
          Text(LocalizedStringResource(
            "habit_detail.weekdays.empty",
            defaultValue: "Your weekly pattern shows here after two weeks of check-ins.",
            table: "Localizable", bundle: LorvexL10n.bundle))
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var bars: some View {
    HStack(alignment: .bottom, spacing: LorvexDesign.Spacing.s) {
      ForEach(Self.inWeekOrder(rhythm.days), id: \.weekday) { day in
        VStack(spacing: LorvexDesign.Spacing.xs) {
          bar(for: day)
            .frame(height: Self.barAreaHeight, alignment: .bottom)
          Text(Self.narrowSymbol(day.weekday))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(
              rhythm.strongestDays.contains(day.weekday) ? AnyShapeStyle(identity) : AnyShapeStyle(.secondary))
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .help(helpText(for: day))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.fullSymbol(day.weekday))
        .accessibilityValue(helpText(for: day))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("habit.detail.weekdays.bars")
  }

  @ViewBuilder
  private func bar(for day: HabitWeekdayRhythm.Day) -> some View {
    if let share = day.share {
      let isStrongest = rhythm.strongestDays.contains(day.weekday)
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        UnevenRoundedRectangle(
          topLeadingRadius: LorvexDesign.Radius.s / 2, topTrailingRadius: LorvexDesign.Radius.s / 2,
          style: .continuous
        )
        .fill(identity.opacity(isStrongest || rhythm.strongestDays.isEmpty ? 1 : 0.55))
        // An empty weekday keeps a sliver, so it reads as a day with no
        // check-ins rather than a missing bar.
        .frame(height: max(Self.barAreaHeight * share, 3))
      }
      .frame(maxWidth: 28)
      .background(alignment: .bottom) {
        UnevenRoundedRectangle(
          topLeadingRadius: LorvexDesign.Radius.s / 2, topTrailingRadius: LorvexDesign.Radius.s / 2,
          style: .continuous
        )
        .fill(.quaternary.opacity(0.5))
      }
    } else {
      VStack {
        Spacer(minLength: 0)
        Capsule()
          .fill(.quaternary)
          .frame(width: 10, height: 2)
      }
    }
  }

  /// "Last 12 weeks", or "Since Sep 3" for a habit checked in for less than
  /// that.
  private var windowLabel: String? {
    guard let start = rhythm.windowStart else { return nil }
    if rhythm.windowDays >= HabitWeekdayRhythm.maximumWindowDays {
      let weeks = HabitWeekdayRhythm.maximumWindowDays / 7
      return String(
        localized: "habit_detail.weekdays.window.weeks", defaultValue: "Last \(weeks) weeks",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(
      format: String(localized: "habit_detail.weekdays.window.since", defaultValue: "Since %@", table: "Localizable", bundle: LorvexL10n.bundle),
      start.formatted(.dateTime.month(.abbreviated).day()))
  }

  /// "Strongest on Monday and Wednesday, weakest on Friday.", one end alone
  /// when the other is too many days to name, or that the week is even.
  private var insight: String {
    switch (Self.names(rhythm.strongestDays), Self.names(rhythm.weakestDays)) {
    case let (strongest?, weakest?):
      String(
        format: String(
          localized: "habit_detail.weekdays.insight",
          defaultValue: "Strongest on %1$@, weakest on %2$@.",
          table: "Localizable", bundle: LorvexL10n.bundle),
        strongest, weakest)
    case let (strongest?, nil):
      String(
        format: String(
          localized: "habit_detail.weekdays.insight.strongest", defaultValue: "Strongest on %@.",
          table: "Localizable", bundle: LorvexL10n.bundle),
        strongest)
    case let (nil, weakest?):
      String(
        format: String(
          localized: "habit_detail.weekdays.insight.weakest", defaultValue: "Weakest on %@.",
          table: "Localizable", bundle: LorvexL10n.bundle),
        weakest)
    case (nil, nil):
      String(localized: "habit_detail.weekdays.even", defaultValue: "About even across the week.", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// Weekdays (Monday-first indices) as a list of full names in the order of
  /// the user's week ("Monday and Wednesday"); nil for none, or for more than
  /// three.
  private static func names(_ weekdays: [Int]) -> String? {
    guard (1...3).contains(weekdays.count) else { return nil }
    return LorvexWeekdayOrder.sorted(weekdays).map(fullSymbol).formatted(.list(type: .and))
  }

  /// The rhythm's days from the first day of the user's week.
  private static func inWeekOrder(_ days: [HabitWeekdayRhythm.Day]) -> [HabitWeekdayRhythm.Day] {
    let order = LorvexWeekdayOrder.mondayFirstIndices()
    return days.sorted { (order.firstIndex(of: $0.weekday) ?? 7) < (order.firstIndex(of: $1.weekday) ?? 7) }
  }

  /// "Tuesday · 9 of 12 days · 75%", or that the habit is not planned that day.
  private func helpText(for day: HabitWeekdayRhythm.Day) -> String {
    guard let share = day.share else {
      return String(
        format: String(localized: "habit_detail.weekdays.unscheduled", defaultValue: "%@ · Not planned", table: "Localizable", bundle: LorvexL10n.bundle),
        Self.fullSymbol(day.weekday))
    }
    let weekday = Self.fullSymbol(day.weekday)
    let percent = share.formatted(.percent.precision(.fractionLength(0)))
    return String(
      localized: "habit_detail.weekdays.share",
      defaultValue: "\(weekday) · \(day.daysWithCheckIns) of \(day.occurrences) days · \(percent)",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// A Monday-first weekday (0 = Monday) as the calendar's narrow standalone
  /// symbol ("T", "二").
  private static func narrowSymbol(_ weekday: Int) -> String {
    symbol(weekday, from: Calendar.current.veryShortStandaloneWeekdaySymbols)
  }

  /// A Monday-first weekday (0 = Monday) as its full standalone name
  /// ("Tuesday", "星期二").
  private static func fullSymbol(_ weekday: Int) -> String {
    symbol(weekday, from: Calendar.current.standaloneWeekdaySymbols)
  }

  private static func symbol(_ weekday: Int, from symbols: [String]) -> String {
    let index = (weekday + 1) % 7
    return symbols.indices.contains(index) ? symbols[index] : ""
  }
}
