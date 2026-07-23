import SwiftUI

/// A wrapping flow layout: lays children left-to-right and wraps to a new line
/// when the next child would overflow the proposed width. Children keep their
/// ideal size (no compression), so labels never truncate — when space is tight
/// the row reflows onto additional lines instead. Used by action-button rows
/// and chip groups that must stay fully legible at any pane width.
///
/// Build each child from an explicit `HStack { Image(systemName:); Text(_) }`,
/// never a bare `Label`: a `Label` placed by a custom `Layout` collapses to its
/// icon (it still reports the title's width, so the cell looks padded but the
/// text never draws). Every call site follows this.
public struct LorvexFlowLayout: Layout {
  public var spacing: CGFloat
  public var lineSpacing: CGFloat

  public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
    self.spacing = spacing
    self.lineSpacing = lineSpacing
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void)
    -> CGSize
  {
    let maxWidth = proposal.width ?? .infinity
    var rowWidth: CGFloat = 0
    var rowHeight: CGFloat = 0
    var totalHeight: CGFloat = 0
    var totalWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight + lineSpacing
        rowWidth = size.width
        rowHeight = size.height
      } else {
        rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
        rowHeight = max(rowHeight, size.height)
      }
    }
    totalWidth = max(totalWidth, rowWidth)
    totalHeight += rowHeight
    return CGSize(width: totalWidth, height: totalHeight)
  }

  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) {
    let maxX = bounds.maxX
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > maxX {
        x = bounds.minX
        y += rowHeight + lineSpacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
