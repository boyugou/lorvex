import LorvexCore
import SwiftUI

/// A habit's standing against its next milestone waypoint, rendered as the app's
/// native progress bar. Milestones are celebration waypoints, never gates — an
/// ongoing habit keeps climbing the ladder past every one — so the framing is
/// "how close to the next rung," not "how much is left to finish."
///
/// Two styles share one vocabulary:
/// - `.compact` — a single slim line (flag · bar · "Next at 14 days") for the
///   momentum card, where the streak line
///   already carries the current reading, so this adds only the missing
///   "progress toward the next waypoint."
/// - `.detail` — a labeled block (the next milestone named in its unit,
///   "14-day streak", over a bar) for the habit inspector. The inspector's
///   stats line already states the current streak and its chips the lifetime
///   count, so the block names only the rung the habit is climbing toward.
///
/// Both bars fill from zero toward the next value (`fractionOfNext`), because
/// the next value is the only number drawn beside them.
struct HabitMilestoneProgressView: View {
  enum Style { case compact, detail }

  let milestone: HabitMilestoneInfo
  /// The habit's cadence wire string, used to label a streak reading in its own
  /// unit (days / weeks / months). Ignored for the `count` metric.
  let frequencyType: String
  let tint: Color
  var style: Style = .compact

  var body: some View {
    switch style {
    case .compact: compact
    case .detail: detail
    }
  }

  private var valueLabel: String {
    HabitDisplayText.milestoneValueLabel(
      metric: milestone.metric, value: milestone.value, frequencyType: frequencyType)
  }

  /// The rung the habit is climbing toward, named like a reading ("14-day
  /// streak").
  private var nextRungLabel: String {
    HabitDisplayText.milestoneValueLabel(
      metric: milestone.metric, value: milestone.nextMilestone, frequencyType: frequencyType)
  }

  private var accessibilityText: String {
    String(
      format: String(
        localized: "habits.milestone.progress_a11y",
        defaultValue: "%1$@, next milestone: %2$@",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      valueLabel, nextRungLabel)
  }

  private var compact: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "flag.checkered")
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(tint)
      LorvexProgressBar(value: milestone.fractionOfNext, tint: tint, height: 5)
      Text(
        HabitDisplayText.milestoneNextLabel(
          metric: milestone.metric, next: milestone.nextMilestone, frequencyType: frequencyType)
      )
      .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
      .foregroundStyle(.secondary)
      .fixedSize()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("habit.milestone.progress")
  }

  private var detail: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        Image(systemName: "flag.checkered")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(tint)
        Text(
          String(
            localized: "habits.milestone.next_label", defaultValue: "Next milestone",
            table: "Localizable",
            bundle: LorvexL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .foregroundStyle(.primary)
        Spacer(minLength: LorvexDesign.Spacing.s)
        Text(nextRungLabel)
          .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      LorvexProgressBar(value: milestone.fractionOfNext, tint: tint, height: 6)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("habit.milestone.progress")
  }
}
