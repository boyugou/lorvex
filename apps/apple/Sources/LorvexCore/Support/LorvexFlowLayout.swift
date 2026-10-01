import SwiftUI

/// A wrapping flow layout: lays children left-to-right and wraps to a new line
/// when the next child would overflow the proposed width. Children keep their
/// ideal size (no compression), so labels never truncate — when space is tight
/// the row reflows onto additional lines instead. Used by action-button rows,
/// chip groups, and the task detail's sentence, which must stay fully legible
/// at any pane width.
///
/// A child whose ideal width is wider than a whole line is offered exactly the
/// line's width instead and gets its rows to itself: a child that can wrap (a
/// `Text` under `.fixedSize(horizontal: false, vertical: true)`) wraps inside
/// the line rather than running past its edge, and the children after it
/// continue below its last line rather than beside its first. A child that
/// cannot get narrower still overflows.
///
/// By default the layout is as wide as its longest line. With `fillsWidth` it
/// claims the whole offered width, so a short row stays at the leading edge
/// instead of being centred by a parent that centres narrower children.
///
/// Build each child from an explicit `HStack { Image(systemName:); Text(_) }`,
/// never a bare `Label`: a `Label` placed by a custom `Layout` collapses to its
/// icon (it still reports the title's width, so the cell looks padded but the
/// text never draws). Every call site follows this.
public struct LorvexFlowLayout: Layout {
  public var spacing: CGFloat
  public var lineSpacing: CGFloat
  public var fillsWidth: Bool

  public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8, fillsWidth: Bool = false) {
    self.spacing = spacing
    self.lineSpacing = lineSpacing
    self.fillsWidth = fillsWidth
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void)
    -> CGSize
  {
    let maxWidth = proposal.width ?? .infinity
    var rowWidth: CGFloat = 0
    var rowHeight: CGFloat = 0
    var totalHeight: CGFloat = 0
    var totalWidth: CGFloat = 0
    var rowIsFull = false

    for subview in subviews {
      let fit = Fit(subview, lineWidth: maxWidth)
      let size = fit.size
      if rowWidth > 0, rowIsFull || fit.fillsLine || rowWidth + spacing + size.width > maxWidth {
        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight + lineSpacing
        rowWidth = size.width
        rowHeight = size.height
      } else {
        rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
        rowHeight = max(rowHeight, size.height)
      }
      rowIsFull = fit.fillsLine
    }
    totalWidth = max(totalWidth, rowWidth)
    totalHeight += rowHeight
    let width = fillsWidth && maxWidth.isFinite ? maxWidth : totalWidth
    return CGSize(width: width, height: totalHeight)
  }

  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) {
    let maxX = bounds.maxX
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0
    var rowIsFull = false

    for subview in subviews {
      let fit = Fit(subview, lineWidth: bounds.width)
      if x > bounds.minX, rowIsFull || fit.fillsLine || x + fit.size.width > maxX {
        x = bounds.minX
        y += rowHeight + lineSpacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: fit.proposal)
      x += fit.size.width + spacing
      rowHeight = max(rowHeight, fit.size.height)
      rowIsFull = fit.fillsLine
    }
  }

  /// How one child sits on a line `lineWidth` wide: at its ideal size under an
  /// unspecified proposal, or, when that is wider than the line, at the size
  /// it settles on when offered the line's width, with its rows to itself.
  private struct Fit {
    let size: CGSize
    let proposal: ProposedViewSize
    /// Whether the child is wider than a line at its ideal size, so it takes
    /// its rows alone.
    let fillsLine: Bool

    init(_ subview: LayoutSubview, lineWidth: CGFloat) {
      let ideal = subview.sizeThatFits(.unspecified)
      if ideal.width > lineWidth {
        proposal = ProposedViewSize(width: lineWidth, height: nil)
        size = subview.sizeThatFits(proposal)
        fillsLine = true
      } else {
        proposal = .unspecified
        size = ideal
        fillsLine = false
      }
    }
  }
}
