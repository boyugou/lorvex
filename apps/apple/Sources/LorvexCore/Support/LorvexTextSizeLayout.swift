import SwiftUI

extension DynamicTypeSize {
  /// Whether a row that sets a time in a fixed-width column beside wrapping
  /// text (a timeline row, an assistant change) stacks the time above the text
  /// instead. From the second-largest standard size up, a phone-width row
  /// cannot hold the column, the text, and a trailing value side by side
  /// without cutting the text to a few words a line. Below that size the
  /// column widens with the text so a time such as "12:40 PM" stays whole.
  public var stacksTimeColumn: Bool { self >= .xxLarge }
}

extension View {
  /// Limits the text to `lines` lines at the standard text sizes and lifts the
  /// limit at the accessibility sizes, where a few lines hold only a few words.
  /// The modifier reads the text size itself, so the view applying it needs no
  /// `@Environment` of its own and an `Equatable` row keeps its synthesized
  /// conformance.
  public func lineLimitUnlessAccessibilitySize(_ lines: Int) -> some View {
    modifier(AccessibleLineLimit(lines: lines))
  }
}

private struct AccessibleLineLimit: ViewModifier {
  let lines: Int
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    content.lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : lines)
  }
}
