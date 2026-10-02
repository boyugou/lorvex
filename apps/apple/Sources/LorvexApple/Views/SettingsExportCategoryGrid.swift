import LorvexCore
import SwiftUI

/// The export categories in Settings › Data as one grid of checkboxes: a
/// column per group, its name on top and its categories stacked under it, the
/// columns spread across the row's width (``ExportCategoryGridLayout``). The
/// checkboxes are plain text, like every settings control. Each carries the
/// identifier `dataExport.category.<rawValue>`.
struct SettingsExportCategoryGrid: View {
  @Binding var selection: Set<LorvexDataExportCategory>

  var body: some View {
    ExportCategoryGridLayout {
      ForEach(LorvexDataExportCategory.Group.allCases) { group in
        Text(group.localizedName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .accessibilityAddTraits(.isHeader)
          .layoutValue(key: ExportCategoryGridLayout.IsGroupName.self, value: true)
        ForEach(group.categories) { category in
          Toggle(category.localizedDisplayName, isOn: isOn(category))
            .toggleStyle(.checkbox)
            .lineLimit(1)
            .accessibilityIdentifier("dataExport.category.\(category.rawValue)")
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("dataExport.categories")
  }

  private func isOn(_ category: LorvexDataExportCategory) -> Binding<Bool> {
    Binding(
      get: { selection.contains(category) },
      set: { isOn in
        if isOn {
          selection.insert(category)
        } else {
          selection.remove(category)
        }
      })
  }
}

/// Lays out group names, each followed by its cells, as one column per group:
/// the name on top and the cells stacked under it.
///
/// A column is as wide as its widest name or cell. The columns span the
/// proposed width: the first starts at the leading edge, the last ends at the
/// trailing edge, and the gutters between them are equal. When the columns
/// don't fit side by side with at least `columnSpacing` between them, they
/// wrap into rows of fewer columns that share their column edges, rows
/// `groupSpacing` apart; one column that is still too wide is narrowed to the
/// width, and its one-line views truncate. Every name takes the tallest
/// name's height and every cell the tallest cell's, so the cells at the same
/// depth in neighboring columns share a line.
struct ExportCategoryGridLayout: Layout {
  /// Marks a subview as a group name; every other subview is a cell of the
  /// group named before it.
  struct IsGroupName: LayoutValueKey {
    static let defaultValue = false
  }

  var columnSpacing = LorvexDesign.Spacing.l
  var nameSpacing = LorvexDesign.Spacing.s
  var rowSpacing = LorvexDesign.Spacing.sm
  var groupSpacing = LorvexDesign.Spacing.m

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let arrangement = arrange(width: proposal.width, subviews: subviews)
    return CGSize(width: arrangement.width, height: arrangement.height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let arrangement = arrange(width: bounds.width, subviews: subviews)
    for item in arrangement.items {
      subviews[item.index].place(
        at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + item.y),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: item.width, height: item.height))
    }
  }

  private struct Item {
    let index: Int
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
  }

  private struct Arrangement {
    let width: CGFloat
    let height: CGFloat
    let items: [Item]
  }

  private func arrange(width proposedWidth: CGFloat?, subviews: Subviews) -> Arrangement {
    var groups: [(name: Int?, cells: [Int])] = []
    for index in subviews.indices {
      if subviews[index][IsGroupName.self] {
        groups.append((index, []))
      } else if groups.isEmpty {
        groups.append((nil, [index]))
      } else {
        groups[groups.count - 1].cells.append(index)
      }
    }
    guard !groups.isEmpty else { return Arrangement(width: proposedWidth ?? 0, height: 0, items: []) }

    let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
    let groupWidths = groups.map { group in
      ([group.name].compactMap { $0 } + group.cells).map { ideal[$0].width }.max() ?? 0
    }
    let nameHeight = groups.compactMap(\.name).map { ideal[$0].height }.max() ?? 0
    let cellHeight = groups.flatMap(\.cells).map { ideal[$0].height }.max() ?? 0

    // The widest column at each position when the groups run `count` to a row.
    func columnWidths(count: Int) -> [CGFloat] {
      (0..<count).map { column in
        stride(from: column, to: groups.count, by: count).map { groupWidths[$0] }.max() ?? 0
      }
    }
    func spannedWidth(_ widths: [CGFloat]) -> CGFloat {
      widths.reduce(0, +) + CGFloat(widths.count - 1) * columnSpacing
    }

    let idealWidth = spannedWidth(groupWidths)
    let width = proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth
    var perRow = groups.count
    while perRow > 1, spannedWidth(columnWidths(count: perRow)) > width {
      perRow -= 1
    }
    var widths = columnWidths(count: perRow)
    if perRow == 1 { widths = [min(widths[0], width)] }
    let gutter =
      perRow > 1
      ? (width - widths.reduce(0, +)) / CGFloat(perRow - 1)
      : 0
    var columnX: [CGFloat] = []
    var x: CGFloat = 0
    for columnWidth in widths {
      columnX.append(x)
      x += columnWidth + gutter
    }

    var items: [Item] = []
    var y: CGFloat = 0
    for rowStart in stride(from: 0, to: groups.count, by: perRow) {
      if rowStart > 0 { y += groupSpacing }
      let row = groups[rowStart..<min(rowStart + perRow, groups.count)]
      let hasNames = row.contains { $0.name != nil }
      let cellsTop = hasNames ? nameHeight + nameSpacing : 0
      var rowHeight: CGFloat = hasNames ? nameHeight : 0
      for (column, group) in row.enumerated() {
        if let name = group.name {
          items.append(
            Item(index: name, x: columnX[column], y: y, width: widths[column], height: nameHeight))
        }
        for (depth, cell) in group.cells.enumerated() {
          let cellY = cellsTop + CGFloat(depth) * (cellHeight + rowSpacing)
          items.append(
            Item(
              index: cell, x: columnX[column], y: y + cellY, width: widths[column],
              height: cellHeight))
          rowHeight = max(rowHeight, cellY + cellHeight)
        }
      }
      y += rowHeight
    }
    return Arrangement(width: width, height: y, items: items)
  }
}
