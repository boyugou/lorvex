import LorvexWidgetKitSupport
import SwiftUI

/// How old a widget's list is ("2 hr ago"), in a quiet capsule at the widget's
/// foot or header. Shown only once the content is stale; fresh content carries
/// no freshness mark.
public struct WidgetStaleAgeLabel: View {
  private let label: String

  public init(_ label: String) {
    self.label = label
  }

  public var body: some View {
    Text(label)
      .font(WidgetType.foot)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(.quaternary, in: Capsule())
  }
}
