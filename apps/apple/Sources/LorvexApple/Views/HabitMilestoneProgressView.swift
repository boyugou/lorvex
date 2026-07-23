import LorvexCore
import SwiftUI

/// A habit's standing against its next milestone waypoint, rendered as the app's
/// native progress bar. Milestones are celebration waypoints, never gates — an
/// ongoing habit keeps climbing the ladder past every one — so the framing is
/// "how close to the next rung," not "how much is left to finish."
///
/// Two styles share one vocabulary:
/// - `.compact` — a single slim line (flag · bar · next value) for the momentum
///   card, where the streak chip already carries the current metric reading, so
///   this adds only the missing "progress toward the next waypoint."
/// - `.detail` — a labeled block (current reading per metric · bar · next value)
///   for the habit inspector, which has room to state the full standing.
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

  private var accessibilityText: String {
    String(
      format: String(
        localized: "habits.milestone.progress_a11y",
        defaultValue: "%1$@, next milestone %2$lld",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      valueLabel, milestone.nextMilestone)
  }

  private var compact: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "flag.checkered")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(tint)
      LorvexProgressBar(value: milestone.progressToNext, tint: tint, height: 5)
      Text("\(milestone.nextMilestone)")
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
        .foregroundStyle(.secondary)
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
        Text(valueLabel)
          .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
          .foregroundStyle(.primary)
        Spacer(minLength: LorvexDesign.Spacing.s)
        Text(
          String(
            format: String(
              localized: "habits.milestone.next", defaultValue: "Next %lld",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            milestone.nextMilestone)
        )
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
        .foregroundStyle(.secondary)
      }
      LorvexProgressBar(value: milestone.progressToNext, tint: tint, height: 6)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("habit.milestone.progress")
  }
}
