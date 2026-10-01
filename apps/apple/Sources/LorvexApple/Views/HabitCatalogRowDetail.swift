import LorvexCore
import SwiftUI

/// The quantitative detail for a habit, shown in the habit inspector: today's
/// progress meter, the requirement and lifetime-count pills, and the next
/// milestone. The current and best streaks and the 30-day rate belong to the
/// stats line above the completion heatmap in `HabitDetailInspector`, so no
/// pill repeats them.
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
        caption: progressCaption,
        tint: progressColor
      )

      LorvexFlowLayout(spacing: LorvexDesign.Spacing.s, lineSpacing: LorvexDesign.Spacing.s) {
        LorvexChip(
          HabitDisplayText.requirementSummary(habit),
          systemImage: "calendar",
          tint: LorvexDesign.Palette.neutral
        )
        LorvexChip(
          String(
            format: String(localized: "habits.row.total_metric", defaultValue: "%lld logged", table: "Localizable", bundle: LorvexL10n.bundle),
            habit.totalCompletions
          ),
          systemImage: "checkmark.seal",
          tint: LorvexDesign.Palette.neutral
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

  /// What the period still asks for, beside the bar: how many completions
  /// remain ("2 to go"), or that the period is done ("Done today", "Done this
  /// week"). The bar already shows the share, so the words say the state.
  private var progressCaption: String {
    guard progress.isComplete else {
      return String(
        format: String(localized: "habits.meter.remaining", defaultValue: "%lld to go", table: "Localizable", bundle: LorvexL10n.bundle),
        max(progress.required - progress.completed, 1))
    }
    switch HabitPeriodProgress.period(for: habit) {
    case .day:
      return String(localized: "habits.meter.done.day", defaultValue: "Done today", table: "Localizable", bundle: LorvexL10n.bundle)
    case .week:
      return String(localized: "habits.meter.done.week", defaultValue: "Done this week", table: "Localizable", bundle: LorvexL10n.bundle)
    case .month:
      return String(localized: "habits.meter.done.month", defaultValue: "Done this month", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  private var progressColor: Color {
    progress.isComplete ? LorvexDesign.Palette.done : LorvexHabitPalette.baseColor(for: habit)
  }
}

private struct HabitRowProgressMeter: View {
  let completed: Int
  let target: Int
  let caption: String
  let tint: Color

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      LorvexProgressBar(value: Double(completed) / Double(max(target, 1)), tint: tint)
      Text(caption)
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
