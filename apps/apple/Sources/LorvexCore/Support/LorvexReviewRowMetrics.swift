import SwiftUI

/// Metrics of the review rows that a touch completes or opens, which differ
/// by how the page is used.
///
/// Under a pointer a row of one line of text is a comfortable target, so its
/// vertical padding stays small and a review reads as a page of lines. Under a
/// finger the same row, about 26 pt tall, is smaller than a fingertip needs,
/// and a tap near its edge lands on the row beside it. On iOS the padding
/// lifts a one-line row to about 40 pt, which with the few points between rows
/// is close to the 44 pt pitch of a list row.
enum LorvexReviewRowMetrics {
  /// The vertical padding around a row's content: `pointerPadding` on macOS,
  /// 10 pt on iOS (a row of one 20 pt line is then 40 pt tall).
  static func rowPadding(_ pointerPadding: CGFloat) -> CGFloat {
    #if os(iOS)
      return max(pointerPadding, 10)
    #else
      return pointerPadding
    #endif
  }

  /// How far a completion circle's tap target reaches past its glyph on every
  /// side: 12 pt on iOS, which makes the 17 pt glyph a target about 41 pt
  /// across, and 6 pt under a pointer.
  static var circleOutset: CGFloat {
    #if os(iOS)
      return 12
    #else
      return 6
    #endif
  }
}
