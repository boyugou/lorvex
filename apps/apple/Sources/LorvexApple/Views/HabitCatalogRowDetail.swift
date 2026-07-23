import LorvexCore
import SwiftUI

/// The quantitative detail for a habit, shown in the habit inspector: today's
/// progress meter plus the frequency / total / 30-day-rate pills. Paired with
/// the completion heatmap in `HabitDetailInspector`.
struct HabitCatalogRowDetail: View {
  let habit: LorvexHabit
  /// Recent completion day strings (from the habit's stats), so the meter can
  /// fill toward the current period's plan for weekly/monthly habits rather than
  /// just today's count.
  var recentCompletions: [String] = []

  private var progress: HabitPeriodProgress.Value {
    HabitPeriodProgress.current(habit: habit, recentCompletions: recentCompletions)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      HabitRowProgressMeter(
        completed: min(progress.completed, progress.required),
        target: progress.required,
        tint: progressColor
      )

      LorvexFlowLayout(spacing: LorvexDesign.Spacing.s, lineSpacing: LorvexDesign.Spacing.s) {
        HabitMetricPill(
          title: HabitDisplayText.requirementSummary(habit),
          systemImage: "calendar",
          tint: .secondary
        )
        HabitMetricPill(
          title: String(
            format: String(localized: "habits.row.total_metric", defaultValue: "%lld logged", table: "Localizable", bundle: LorvexL10n.bundle),
            habit.totalCompletions
          ),
          systemImage: "checkmark.seal",
          tint: .secondary
        )
        HabitMetricPill(
          title: String(
            format: String(localized: "habits.row.rate_metric", defaultValue: "30d %@", table: "Localizable", bundle: LorvexL10n.bundle),
            habit.completionRate30d.formatted(.percent.precision(.fractionLength(0)))
          ),
          systemImage: "chart.line.uptrend.xyaxis",
          tint: .secondary
        )
      }

      if let milestone = habit.milestone {
        HabitMilestoneProgressView(
          milestone: milestone,
          frequencyType: habit.frequencyType,
          tint: LorvexHabitPalette.baseColor(for: habit),
          style: .detail)
      }
    }
  }

  private var progressColor: Color {
    progress.isComplete ? .green : .accentColor
  }
}

private struct HabitRowProgressMeter: View {
  let completed: Int
  let target: Int
  let tint: Color

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      LorvexProgressBar(value: Double(completed) / Double(max(target, 1)), tint: tint)
      Text("\(completed)/\(target)")
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
        .foregroundStyle(.secondary)
        .fixedSize()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      String(
        format: String(
          localized: "habits.row.progress_meter_a11y",
          defaultValue: "Progress: %lld of %lld",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        completed,
        target
      )
    )
    .accessibilityIdentifier("habit.progress.meter")
  }
}

private struct HabitMetricPill: View {
  let title: String
  let systemImage: String
  let tint: Color

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(tint)
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .background(.quaternary.opacity(0.55), in: Capsule())
  }
}
