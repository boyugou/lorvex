import SwiftUI

/// Left-to-right flow layout that wraps subviews onto new rows when they exceed
/// the proposed width. Used to render removable token chips in the task editor.
struct MobileWrapLayout: Layout {
  var spacing: CGFloat = 6
  var lineSpacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    let rows = layoutRows(maxWidth: maxWidth, subviews: subviews)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
    return CGSize(
      width: proposal.width ?? width,
      height: height
    )
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) {
    let rows = layoutRows(maxWidth: bounds.width, subviews: subviews)
    var y = bounds.minY
    for row in rows {
      var x = bounds.minX
      for item in row.items {
        let size = subviews[item.index].sizeThatFits(.unspecified)
        subviews[item.index].place(
          at: CGPoint(x: x, y: y),
          anchor: .topLeading,
          proposal: ProposedViewSize(size)
        )
        x += size.width + spacing
      }
      y += row.height + lineSpacing
    }
  }

  private struct Row {
    var items: [(index: Int, width: CGFloat)] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let projected = current.items.isEmpty ? size.width : current.width + spacing + size.width
      if !current.items.isEmpty, projected > maxWidth {
        rows.append(current)
        current = Row()
      }
      let lead = current.items.isEmpty ? 0 : spacing
      current.width += lead + size.width
      current.height = max(current.height, size.height)
      current.items.append((index: index, width: size.width))
    }
    if !current.items.isEmpty { rows.append(current) }
    return rows
  }
}
