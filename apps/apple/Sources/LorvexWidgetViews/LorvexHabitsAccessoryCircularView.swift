import LorvexWidgetKitSupport
import SwiftUI
import WidgetKit

/// A circular accessory (Lock Screen / watch-style) widget showing how many of
/// today's habits are complete as a gauge arc — habits met (`completedToday >=
/// target`) over the total. Renders a "no habits tracked" glyph instead of the
/// gauge when `habits` is empty, rather than a misleading 0-of-1 ratio.
public struct HabitsAccessoryCircularView: View {
  let habits: [WidgetSnapshot.HabitSummary]

  public init(habits: [WidgetSnapshot.HabitSummary]) {
    self.habits = habits
  }

  public var body: some View {
    if habits.isEmpty {
      // Without this branch the gauge below (denominator floored to 1 to
      // avoid a divide-by-zero) reads "0 of 1 habits done" — a specific,
      // wrong claim when no habit is tracked at all, not just an empty state.
      Image(systemName: "repeat")
        .widgetAccentable()
        .accessibilityLabel(
          String(
            localized: "widget.empty.no_habits",
            defaultValue: "No habits tracked yet.",
            table: "Localizable",
            bundle: WidgetL10n.bundle))
    } else {
      let done = habits.filter(\.isDoneToday).count
      let total = habits.count
      Gauge(value: Double(done), in: 0...Double(total)) {
        EmptyView()
      } currentValueLabel: {
        Text("\(done)")
          .font(.system(.body, design: .rounded).weight(.bold))
      }
      .gaugeStyle(.accessoryCircular)
      .widgetAccentable()
      .accessibilityLabel(
        String(
          localized: "widget.habits.circular.a11y",
          defaultValue: "\(done) of \(total) habits done",
          table: "Localizable",
          bundle: WidgetL10n.bundle))
    }
  }
}
