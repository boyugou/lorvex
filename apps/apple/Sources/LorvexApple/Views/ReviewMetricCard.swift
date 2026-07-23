import LorvexCore
import SwiftUI

/// A glanceable stat tile for the weekly review: a tinted icon, a large
/// tokenized number, and a caption label on a soft tinted card. Reads as a
/// dashboard of the week at a glance rather than a list of label/value rows.
struct ReviewMetricCard: View {
  let title: String
  /// Stable, locale-independent identifier suffix for the card's accessibility
  /// identifier (e.g. `completed`). Kept separate from `title`, which is a
  /// localized display string and would make the identifier locale-dependent.
  let metricKey: String
  let value: Int
  let systemImage: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.sectionHeader)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(tint)

      Text(value, format: .number)
        .font(LorvexDesign.Typography.sectionHeader.monospacedDigit())
        .foregroundStyle(.primary)
        .contentTransition(.numericText())

      Text(title)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(LorvexDesign.Spacing.m)
    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(reviewMetricAccessibilityLabel(title: title, value: value))
    .accessibilityIdentifier("review.metric.\(metricKey)")
  }
}
