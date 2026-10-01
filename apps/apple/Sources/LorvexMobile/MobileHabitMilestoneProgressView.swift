import LorvexCore
import SwiftUI

/// A habit's standing against its next milestone waypoint, rendered natively.
/// Milestones are celebration waypoints, never gates — an ongoing habit keeps
/// climbing the ladder past every one — so the framing is "how close to the next
/// rung," not "how much is left to finish." Mirrors the macOS
/// `HabitMilestoneProgressView`.
///
/// Two styles share one vocabulary:
/// - `.compact` — a slim line (flag · metric reading · next value in the
///   reading's unit, "Next at 14 days") for a catalog row, where the trailing
///   completion ring already carries today's count, so this adds the current
///   streak or total and the rung it is climbing toward.
///   It carries no bar: the two readings already state the fraction, and a bar
///   sized from whatever width the text left over made neighbouring rows in one
///   list look arbitrarily different. In a column too narrow for both readings
///   the next value drops, and in one too narrow for the reading alone (at
///   accessibility text sizes) the reading wraps, so a label never truncates
///   and the line never grows wider than its row.
/// - `.detail` — a labeled block (the next milestone named in its unit,
///   "14-day streak", over a bar) for the habit detail panel. The panel's
///   momentum card already states the current streak and its facts line the
///   lifetime count, so the block names only the rung the habit is climbing
///   toward, and its bar fills from zero toward it (`fractionOfNext`). The
///   label and the rung share a line while both fit whole; in a narrower line
///   (at accessibility text sizes) the rung moves under the label, so neither
///   breaks inside a word.
struct MobileHabitMilestoneProgressView: View {
  enum Style { case compact, detail }

  let milestone: HabitMilestoneInfo
  /// The habit's cadence wire string, used to label a streak reading in its own
  /// unit (days / weeks / months). Ignored for the `count` metric.
  let frequencyType: String
  let tint: Color
  var style: Style = .compact
  /// Per-habit suffix so simultaneously-visible catalog rows get distinct
  /// accessibility identifiers instead of all sharing one.
  var accessibilityIDSuffix: String? = nil

  var body: some View {
    switch style {
    case .compact: compact
    case .detail: detail
    }
  }

  private var milestoneAccessibilityIdentifier: String {
    accessibilityIDSuffix.map { "mobileHabits.milestone.progress.\($0)" }
      ?? "mobileHabits.milestone.progress"
  }

  private var valueLabel: String {
    MobileHabitDisplayText.milestoneValueLabel(
      metric: milestone.metric, value: milestone.value, frequencyType: frequencyType)
  }

  /// The rung the habit is climbing toward, named like a reading ("14-day
  /// streak").
  private var nextRungLabel: String {
    MobileHabitDisplayText.milestoneValueLabel(
      metric: milestone.metric, value: milestone.nextMilestone, frequencyType: frequencyType)
  }

  private var accessibilityText: String {
    String(
      format: String(localized: "habits.milestone.progress_a11y", defaultValue: "%1$@, next milestone: %2$@", table: "Localizable", bundle: MobileL10n.bundle),
      valueLabel, nextRungLabel)
  }

  private var compact: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        compactFlag
        compactValue(wraps: false)
        Text(verbatim: "·").foregroundStyle(.tertiary).accessibilityHidden(true)
        compactNext
      }
      // `ViewThatFits` also shows its last candidate when none fits, so this
      // one's reading wraps rather than pushing the row past the screen edge.
      HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
        compactFlag
        compactValue(wraps: true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier(milestoneAccessibilityIdentifier)
  }

  private var compactFlag: some View {
    Image(systemName: "flag.checkered")
      .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
      .foregroundStyle(tint)
  }

  private func compactValue(wraps: Bool) -> some View {
    Text(valueLabel)
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      .foregroundStyle(.secondary)
      .lineLimit(wraps ? nil : 1)
      .fixedSize(horizontal: !wraps, vertical: true)
  }

  private var compactNext: some View {
    Text(
      MobileHabitDisplayText.milestoneNextLabel(
        metric: milestone.metric, next: milestone.nextMilestone, frequencyType: frequencyType)
    )
    .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .fixedSize()
  }

  private var detail: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          detailFlag
          detailLabel
            .lineLimit(1)
          Spacer(minLength: LorvexDesign.Spacing.s)
          detailRung
            .lineLimit(1)
        }
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          detailFlag
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
            detailLabel
            detailRung
          }
          .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
      }
      MobileMilestoneBar(value: milestone.fractionOfNext, tint: tint, height: 6)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .accessibilityIdentifier(milestoneAccessibilityIdentifier)
  }

  private var detailFlag: some View {
    Image(systemName: "flag.checkered")
      .foregroundStyle(tint)
  }

  private var detailLabel: some View {
    Text(
      String(localized: "habits.milestone.next_label", defaultValue: "Next milestone", table: "Localizable", bundle: MobileL10n.bundle)
    )
    .font(LorvexDesign.Typography.secondaryText.weight(.medium))
    .foregroundStyle(.primary)
  }

  private var detailRung: some View {
    Text(nextRungLabel)
      .font(LorvexDesign.Typography.secondaryText.monospacedDigit())
      .foregroundStyle(.secondary)
  }
}

/// A soft capsule rail filled to a fraction with the tint's gradient — the
/// mobile determinate track for milestone progress, matching the macOS
/// `LorvexProgressBar` family.
private struct MobileMilestoneBar: View {
  let value: Double
  var tint: Color = LorvexDesign.Palette.accent
  var height: CGFloat = 6
  @Environment(\.colorScheme) private var colorScheme

  private var fraction: Double { min(max(value, 0), 1) }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(tint.opacity(LorvexDesign.Palette.trackOpacity(for: colorScheme)))
        Capsule()
          .fill(tint.gradient)
          .frame(width: proxy.size.width * fraction)
      }
    }
    .frame(height: height)
    .animation(.easeInOut(duration: 0.28), value: fraction)
  }
}
