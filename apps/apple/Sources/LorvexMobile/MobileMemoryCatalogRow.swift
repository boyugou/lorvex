import LorvexCore
import SwiftUI

/// A memory note in the catalog: the note's name and the first two lines of
/// its content, with no leading tile, since every note is the same kind and a
/// tile would only repeat the screen's title on each row. The name wraps onto a second line rather
/// than truncating, so a large text size still shows which note a row is.
struct MobileMemoryCatalogRow: View {
  let entry: MemoryEntry

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      VStack(alignment: .leading, spacing: 2) {
        Text(userContent: entry.displayTitle)
          .font(LorvexDesign.Typography.primaryText)
          .lineLimit(2)
        Text(userContent: entry.content)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: LorvexDesign.Spacing.s)
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(memoryEntryAccessibilityLabel(entry))
    .accessibilityIdentifier("mobileMemory.catalogRow.\(entry.key)")
  }
}
