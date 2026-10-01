import LorvexWidgetKitSupport
import SwiftUI

public struct LorvexWidgetViewMetrics: Equatable, Sendable {
  public let family: WidgetFamilyKind
  public let showsBriefing: Bool
  public let horizontalPadding: Double
  public let verticalPadding: Double

  /// Task rows this family renders, taken from the canonical per-family cap on
  /// ``WidgetFamilyKind/maxTaskRows`` (0 for the accessory glance families).
  public var maxVisibleRows: Int { family.maxTaskRows }

  public static func metrics(for family: WidgetFamilyKind) -> LorvexWidgetViewMetrics {
    switch family {
    case .accessoryInline, .accessoryCircular:
      LorvexWidgetViewMetrics(
        family: family, showsBriefing: false, horizontalPadding: 0, verticalPadding: 0)
    case .accessoryRectangular:
      LorvexWidgetViewMetrics(
        family: family, showsBriefing: false, horizontalPadding: 8, verticalPadding: 6)
    case .systemSmall:
      LorvexWidgetViewMetrics(
        family: family, showsBriefing: false, horizontalPadding: 12, verticalPadding: 12)
    case .systemMedium:
      // No briefing line on medium: the lead block, two rows, and the foot
      // line fill its 158pt canvas. Large has the room and keeps it.
      LorvexWidgetViewMetrics(
        family: family, showsBriefing: false, horizontalPadding: 14, verticalPadding: 10)
    case .systemLarge:
      LorvexWidgetViewMetrics(
        family: family, showsBriefing: true, horizontalPadding: 16, verticalPadding: 14)
    }
  }
}
