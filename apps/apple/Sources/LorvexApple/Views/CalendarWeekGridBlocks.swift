import SwiftUI

/// Scroll-anchor identity for `CalendarWeekGridView`. The grid scrolls this
/// anchor into view on first show so early events are not hidden above the
/// default working-hours region.
enum WeekGridScrollAnchor: Hashable {
  case hour(Int)
}

/// Tags every hour row in the gutter with its scroll-anchor identity so any
/// `scrollTo(WeekGridScrollAnchor.hour:)` lands on its target — the initial
/// working-hours scroll on appear and the re-scroll on week navigation alike.
/// Tagging only the anchor hour would leave every other target a silent no-op.
struct WeekGridAnchorModifier: ViewModifier {
  let hour: Int
  func body(content: Content) -> some View {
    content.id(WeekGridScrollAnchor.hour(hour))
  }
}
