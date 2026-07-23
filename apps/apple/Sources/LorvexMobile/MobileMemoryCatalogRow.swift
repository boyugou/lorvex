import LorvexCore
import SwiftUI

struct MobileMemoryCatalogRow: View {
  let entry: MemoryEntry

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(symbol: "sparkles", tint: .purple, size: 30)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.key)
          .font(.body)
          .lineLimit(1)
        Text(entry.content)
          .font(.footnote)
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
