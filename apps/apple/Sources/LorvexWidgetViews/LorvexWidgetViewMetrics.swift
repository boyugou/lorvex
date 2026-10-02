import LorvexWidgetKitSupport
import SwiftUI

/// Per-family layout facts for the Today widget's views.
///
/// The Home Screen and desktop families draw inside WidgetKit's content
/// margins, which differ by platform and context (StandBy, the Mac desktop),
/// so their own padding is zero; only the Lock Screen's rectangular family,
/// which WidgetKit gives no margins, insets its content.
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
        family: family, showsBriefing: false, horizontalPadding: 0, verticalPadding: 0)
    case .systemMedium:
      // No briefing line on medium: the lead block, two rows, and the foot
      // line fill its 158pt canvas. Large has the room and keeps it.
      LorvexWidgetViewMetrics(
        family: family, showsBriefing: false, horizontalPadding: 0, verticalPadding: 0)
    case .systemLarge:
      LorvexWidgetViewMetrics(
        family: family, showsBriefing: true, horizontalPadding: 0, verticalPadding: 0)
    }
  }
}
