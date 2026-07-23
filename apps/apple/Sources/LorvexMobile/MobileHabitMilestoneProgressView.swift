import LorvexCore
import SwiftUI

/// A habit's standing against its next milestone waypoint, rendered natively.
/// Milestones are celebration waypoints, never gates — an ongoing habit keeps
/// climbing the ladder past every one — so the framing is "how close to the next
/// rung," not "how much is left to finish." Mirrors the macOS
/// `HabitMilestoneProgressView`.
///
/// Two styles share one vocabulary:
/// - `.compact` — a slim line (flag · metric reading · bar · next value) for a
///   catalog row, where the trailing completion ring already carries today's
///   count, so this adds the current streak/total plus progress to the next rung.
/// - `.detail` — a labeled block (current reading per metric · next value · bar)
///   for the habit detail panel, which has room to state the full standing.
struct MobileHabitMilestoneProgressView: View {
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
    MobileHabitDisplayText.milestoneValueLabel(
      metric: milestone.metric, value: milestone.value, frequencyType: frequencyType)
  }

  private var accessibilityText: String {
    String(
      format: String(localized: "habits.milestone.progress_a11y", defaultValue: "%1$@, next milestone %2$lld", table: "Localizable", bundle: MobileL10n.bundle),
      valueLabel, milestone.nextMilestone)
  }

  private var compact: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "flag.checkered")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
      Text(valueLabel)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .layoutPriority(1)
      MobileMilestoneBar(value: milestone.progressToNext, tint: tint, height: 5)
        .frame(minWidth: 24)
      Text("\(milestone.nextMilestone)")
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("mobileHabits.milestone.progress")
  }

  private var detail: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Image(systemName: "flag.checkered")
          .foregroundStyle(tint)
        Text(valueLabel)
          .font(LorvexDesign.Typography.secondaryText.weight(.medium))
          .foregroundStyle(.primary)
        Spacer(minLength: LorvexDesign.Spacing.s)
        Text(
          String(
            format: String(localized: "habits.milestone.next", defaultValue: "Next %lld", table: "Localizable", bundle: MobileL10n.bundle),
            milestone.nextMilestone)
        )
        .font(LorvexDesign.Typography.secondaryText.monospacedDigit())
        .foregroundStyle(.secondary)
      }
      MobileMilestoneBar(value: milestone.progressToNext, tint: tint, height: 6)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier("mobileHabits.milestone.progress")
  }
}

/// A soft capsule rail filled to a fraction with the tint's gradient — the
/// mobile determinate track for milestone progress, matching the macOS
/// `LorvexProgressBar` family.
private struct MobileMilestoneBar: View {
  let value: Double
  var tint: Color = LorvexDesign.Palette.accent
  var height: CGFloat = 6

  private var fraction: Double { min(max(value, 0), 1) }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(tint.opacity(0.16))
        Capsule()
          .fill(tint.gradient)
          .frame(width: proxy.size.width * fraction)
      }
    }
    .frame(height: height)
    .animation(.easeInOut(duration: 0.28), value: fraction)
  }
}
