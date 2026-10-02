import LorvexCore
import SwiftUI

/// The habit inspector's Progress panel: the current and best streaks, the
/// check-ins logged in all, and the share of the last 30 days done, as two
/// rows of two readings, with the next milestone beneath.
///
/// Streaks read in the habit's own unit (days, weeks, or months). The current
/// streak's flame takes the habit's color while the streak runs. The readings
/// come from the habit's stats, which the catalog loads for its cards, so the
/// panel fills before the inspector's own detail arrives; a habit without
/// stats yet shows dashes.
struct HabitProgressPanel: View {
  let habit: LorvexHabit
  let stats: HabitStats?

  private var identity: Color { LorvexHabitPalette.baseColor(for: habit) }

  var body: some View {
    InspectorPanel(accessibilityIdentifier: "habit.detail.progress.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        Label(
          String(localized: "habit_detail.progress.title", defaultValue: "Progress", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "chart.line.uptrend.xyaxis"
        )
        .font(LorvexDesign.Typography.primaryEmphasis)

        Grid(alignment: .leading, horizontalSpacing: LorvexDesign.Spacing.m, verticalSpacing: LorvexDesign.Spacing.m) {
          GridRow {
            reading(
              title: String(localized: "habit_detail.stat.current", defaultValue: "Current streak", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "flame.fill",
              iconTint: (stats?.currentStreak ?? 0) > 0 ? AnyShapeStyle(identity) : AnyShapeStyle(.tertiary),
              value: stats.map { lorvexHabitStreakLabel($0.currentStreak, frequencyType: habit.frequencyType) })
            reading(
              title: String(localized: "habit_detail.stat.best", defaultValue: "Best streak", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "trophy.fill",
              iconTint: AnyShapeStyle(.tertiary),
              value: stats.map { lorvexHabitStreakLabel($0.bestStreak, frequencyType: habit.frequencyType) })
          }
          GridRow {
            reading(
              title: String(localized: "habit_detail.stat.total", defaultValue: "Check-ins", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "checkmark.seal.fill",
              iconTint: AnyShapeStyle(.tertiary),
              value: stats.map { $0.totalCompletions.formatted() })
            reading(
              title: String(localized: "habit_detail.stat.rate", defaultValue: "Last 30 days", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "chart.bar.fill",
              iconTint: AnyShapeStyle(.tertiary),
              value: stats.map { $0.completionRate30d.formatted(.percent.precision(.fractionLength(0))) })
          }
        }

        if let milestone = habit.milestone {
          Divider()
          HabitMilestoneProgressView(
            milestone: milestone, frequencyType: habit.frequencyType, tint: identity, style: .detail)
        }
      }
    }
  }

  /// One reading: an icon and its name in small secondary text, over its
  /// value in large figures; a dash until the stats load.
  private func reading(title: String, systemImage: String, iconTint: AnyShapeStyle, value: String?)
    -> some View
  {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Label {
        Text(title)
          .foregroundStyle(.secondary)
      } icon: {
        Image(systemName: systemImage)
          .foregroundStyle(iconTint)
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .lineLimit(1)
      Text(value ?? "—")
        .font(LorvexDesign.Typography.sectionHeader.monospacedDigit())
        .foregroundStyle(value == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .contentTransition(.numericText())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(value ?? "")
  }
}
