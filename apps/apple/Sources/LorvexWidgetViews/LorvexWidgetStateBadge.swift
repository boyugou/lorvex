import LorvexWidgetKitSupport
import SwiftUI

// The old "Live / Ready / Saved" `StateBadge` was removed from every widget — it
// read as debug chrome. Freshness now shows only as the subtle stale capsule
// below, once content is actually old.

public struct WidgetStaleAgeLabel: View {
  private let label: String

  public init(_ label: String) {
    self.label = label
  }

  public var body: some View {
    Text(label)
      .font(.caption2.weight(.medium))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(.quaternary, in: Capsule())
  }
}
