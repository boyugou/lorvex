import SwiftUI

/// Frames the leading circle of a task row (the completion circle, the done
/// check, the batch-selection checkbox) and the glyph column other rows line
/// up with it. The frame is 26pt at the default text size and grows with the
/// title3 style the circle is set in, so the circle stays inside its row at
/// every text size and the titles beside it keep one leading edge.
struct MobileTaskCircleFrame: ViewModifier {
  /// How far the tap target of a circle that acts (completes or reopens its
  /// task) reaches past the frame on each side, which makes it 44pt across at
  /// the default text size. The reach stays inside the gap between the circle
  /// and the title and inside the row's leading inset. The control pads its
  /// label by this much, gives it a rectangular content shape, and takes the
  /// padding back with a negative padding outside the button, so the row is
  /// laid out around the circle's own size.
  static let tapOutset: CGFloat = 9

  /// Whether the frame is square; a glyph column that only lines titles up
  /// frames its width alone.
  var isSquare = true
  @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 26

  func body(content: Content) -> some View {
    content.frame(width: side, height: isSquare ? side : nil)
  }
}

extension View {
  /// Frames a task row's leading circle, or a column lined up with it; see
  /// ``MobileTaskCircleFrame``.
  func mobileTaskCircleFrame(isSquare: Bool = true) -> some View {
    modifier(MobileTaskCircleFrame(isSquare: isSquare))
  }
}
