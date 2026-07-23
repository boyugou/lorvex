import LorvexCore
import SwiftUI

struct MobileListCatalogRow: View {
  let list: LorvexList
  var showsChevron = true
  /// The inline progress bar reads as clutter in a dense overview (the open
  /// count already signals workload); the standalone Lists catalog keeps it.
  var showsProgress = true

  private var tileTint: Color { Color(lorvexHex: list.color) ?? LorvexDesign.Palette.accent }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(icon: list.icon, fallback: "tray.fill", tint: tileTint, size: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(list.name)
          .font(.body)
          .lineLimit(1)
        if let description = list.description, !description.isEmpty {
          Text(description)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if showsProgress, let fraction = list.progressFraction {
          HStack(spacing: LorvexDesign.Spacing.s) {
            ProgressView(value: fraction)
              .progressViewStyle(.linear)
              .tint(tileTint)
              .frame(maxWidth: 120)
              .accessibilityHidden(true)
            Text("\(list.completedCount)/\(list.progressDenominator)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
        }
      }
      Spacer(minLength: LorvexDesign.Spacing.s)
      Text("\(list.openCount)")
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityLabel(
          String(
            localized: "today.metrics.open_tasks.a11y",
            defaultValue: "\(list.openCount) open tasks",
            table: "Localizable", bundle: MobileL10n.bundle))
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.footnote)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityElement(children: .combine)
    .accessibilityValue(completionAccessibilityValue)
  }

  /// Speaks the completion fraction VoiceOver would otherwise miss: the visual
  /// progress bar and the "N/M" caption are both `accessibilityHidden`, so the
  /// combined row exposes the same information here. Empty when the row shows no
  /// progress.
  private var completionAccessibilityValue: Text {
    guard showsProgress, list.progressFraction != nil else { return Text(verbatim: "") }
    return Text(
      String(
        format: String(
          localized: "lists.completion.a11y", defaultValue: "%1$lld of %2$lld completed",
          table: "Localizable", bundle: MobileL10n.bundle),
        Int64(list.completedCount), Int64(list.progressDenominator)))
  }
}
