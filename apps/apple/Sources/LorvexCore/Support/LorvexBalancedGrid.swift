import SwiftUI

/// A grid of equal columns that spreads its items evenly over its rows, so no
/// row is left with a lone item while the rows above are full: four items
/// where three fit make two rows of two, and five where four fit make a row of
/// three over a row of two.
///
/// As many columns fit as the width holds at `minimumColumnWidth` apart by
/// `columnSpacing`, and the grid uses only as many of them as the balanced
/// rows need. Those columns share the width, each at most
/// `maximumColumnWidth`, from the leading edge: with an unbounded maximum
/// (`.infinity`) a short row spreads across the whole width, as four habits
/// do in a wide card, and with a bounded one it keeps to the leading edge.
/// Each item is offered its column's width, and a row is as tall as its
/// tallest item, which sits at the top of its cell. Items keep their order, so
/// they stay where they are from day to day.
public struct LorvexBalancedGrid: Layout {
  public var minimumColumnWidth: CGFloat
  public var maximumColumnWidth: CGFloat
  public var columnSpacing: CGFloat
  public var rowSpacing: CGFloat

  public init(
    minimumColumnWidth: CGFloat, maximumColumnWidth: CGFloat, columnSpacing: CGFloat,
    rowSpacing: CGFloat
  ) {
    self.minimumColumnWidth = minimumColumnWidth
    self.maximumColumnWidth = max(maximumColumnWidth, minimumColumnWidth)
    self.columnSpacing = columnSpacing
    self.rowSpacing = rowSpacing
  }

  /// How many columns `itemCount` items take when a row holds `capacity`:
  /// the fewest rows that hold them all, filled as evenly as they can be.
  public static func columnCount(itemCount: Int, capacity: Int) -> Int {
    let capacity = max(capacity, 1)
    guard itemCount > capacity else { return max(itemCount, 1) }
    let rows = (itemCount + capacity - 1) / capacity
    return (itemCount + rows - 1) / rows
  }

  /// The columns `itemCount` items take in a row of `width`: how many the
  /// balanced rows use (``columnCount(itemCount:capacity:)`` of as many as fit
  /// at `minimumColumnWidth`), and each one's width, the share of `width`
  /// those columns take, at most `maximumColumnWidth`.
  public static func columns(
    itemCount: Int, width: CGFloat, minimumColumnWidth: CGFloat, maximumColumnWidth: CGFloat,
    columnSpacing: CGFloat
  ) -> (count: Int, width: CGFloat) {
    let capacity = max(1, Int(((width + columnSpacing) / (minimumColumnWidth + columnSpacing)).rounded(.down)))
    let count = columnCount(itemCount: itemCount, capacity: capacity)
    let share = (width - CGFloat(count - 1) * columnSpacing) / CGFloat(count)
    return (count, min(maximumColumnWidth, max(share, 0)))
  }

  /// The rows `subviews` fill at `width`: each row's items and its height.
  private func rows(_ subviews: Subviews, width: CGFloat) -> (columnWidth: CGFloat, rows: [(range: Range<Int>, height: CGFloat)]) {
    let (perRow, columnWidth) = Self.columns(
      itemCount: subviews.count, width: width, minimumColumnWidth: minimumColumnWidth,
      maximumColumnWidth: maximumColumnWidth, columnSpacing: columnSpacing)
    var rows: [(range: Range<Int>, height: CGFloat)] = []
    var start = 0
    while start < subviews.count {
      let range = start..<min(start + perRow, subviews.count)
      let height = range.map {
        subviews[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
      }.max() ?? 0
      rows.append((range, height))
      start = range.upperBound
    }
    return (columnWidth, rows)
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard !subviews.isEmpty else { return .zero }
    // Without a width to fill, the grid takes one row at the narrowest columns.
    let width =
      proposal.width
      ?? CGFloat(subviews.count) * (minimumColumnWidth + columnSpacing) - columnSpacing
    let layout = rows(subviews, width: width)
    let height =
      layout.rows.map(\.height).reduce(0, +) + CGFloat(max(layout.rows.count - 1, 0)) * rowSpacing
    return CGSize(width: width, height: height)
  }

  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let layout = rows(subviews, width: bounds.width)
    var y = bounds.minY
    for row in layout.rows {
      for (column, index) in row.range.enumerated() {
        subviews[index].place(
          at: CGPoint(x: bounds.minX + CGFloat(column) * (layout.columnWidth + columnSpacing), y: y),
          anchor: .topLeading,
          proposal: ProposedViewSize(width: layout.columnWidth, height: row.height))
      }
      y += row.height + rowSpacing
    }
  }
}
