import LorvexCore
import SwiftUI

struct HabitHeatmapStatsLine: View {
  let habitID: LorvexHabit.ID
  let stats: HabitStats?
  /// The habit's `frequency_type`, so the streak values read in the cadence's
  /// own unit (weeks for weekly/custom, months for monthly) rather than days.
  var frequencyType: String = "daily"

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.l) {
      HabitHeatmapStat(
        title: String(localized: "habit.streak.current", defaultValue: "Current", table: "Localizable", bundle: LorvexL10n.bundle),
        value: stats.map { lorvexHabitStreakLabel($0.currentStreak, frequencyType: frequencyType) } ?? "—",
        systemImage: "flame.fill",
        tint: (stats?.currentStreak ?? 0) > 0 ? .orange : .secondary
      )
      HabitHeatmapStat(
        title: String(localized: "habit.streak.best", defaultValue: "Best", table: "Localizable", bundle: LorvexL10n.bundle),
        value: stats.map { lorvexHabitStreakLabel($0.bestStreak, frequencyType: frequencyType) } ?? "—",
        systemImage: "trophy.fill",
        tint: .secondary
      )
      HabitHeatmapStat(
        title: String(localized: "habits.stats.thirty_day_rate", defaultValue: "30-day rate", table: "Localizable", bundle: LorvexL10n.bundle),
        value: stats.map {
          $0.completionRate30d.formatted(.percent.precision(.fractionLength(0)))
        } ?? "—",
        systemImage: "chart.bar.fill",
        tint: .secondary
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("habit.heatmap.stats.\(habitID)")
  }

  private var accessibilityLabel: String {
    guard let stats else {
      return String(localized: "habit.heatmap.a11y.loading", defaultValue: "Habit history loading", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    let rate = stats.completionRate30d.formatted(.percent.precision(.fractionLength(0)))
    return String(
      format: String(
        localized: "habit.heatmap.a11y.summary",
        defaultValue: "Current streak %1$lld days, best streak %2$lld days, 30-day completion rate %3$@",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      stats.currentStreak, stats.bestStreak, rate
    )
  }
}

private struct HabitHeatmapStat: View {
  let title: String
  let value: String
  let systemImage: String
  let tint: Color

  var body: some View {
    // Icon on the left, vertically centered, with the label and value stacked
    // to its right and left-aligned — so the icon lines up with both lines.
    HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(tint)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
        Text(value)
          .font(LorvexDesign.Typography.secondaryText.weight(.semibold))
          .monospacedDigit()
      }
    }
  }
}
