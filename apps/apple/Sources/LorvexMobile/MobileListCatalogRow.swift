import LorvexCore
import SwiftUI

/// A list's row on the Tasks home: its tile, name, and description, with the
/// open-task count at the trailing edge while the list has open tasks, as the
/// Mac sidebar badges a list. The name and the description each wrap onto a
/// second line rather than truncating, so a large text size still shows which
/// list a row is.
struct MobileListCatalogRow: View {
  let list: LorvexList

  private var tileTint: Color { Color(lorvexHex: list.color) ?? LorvexDesign.Palette.accent }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(icon: list.icon, fallback: "tray.fill", tint: tileTint, size: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(list.displayName)
          .font(.body)
          .lineLimit(2)
        if let description = list.description, !description.isEmpty {
          Text(description)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: LorvexDesign.Spacing.s)
      if list.openCount > 0 {
        Text("\(list.openCount)")
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            String(
              localized: "today.metrics.open_tasks.a11y",
              defaultValue: "\(list.openCount) open tasks",
              table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityElement(children: .combine)
  }
}
