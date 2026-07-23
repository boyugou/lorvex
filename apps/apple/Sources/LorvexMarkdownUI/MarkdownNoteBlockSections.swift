import SwiftUI

extension MarkdownNoteView {
    @ViewBuilder
    func taskListView(_ items: [MarkdownNote.RenderedTaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(item.isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                    Text(item.text)
                        .strikethrough(item.isChecked, color: .secondary)
                        .foregroundStyle(item.isChecked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(
                    format: item.isChecked
                        ? taskItemAccessibility.completedFormat
                        : taskItemAccessibility.todoFormat,
                    item.source))
            }
        }
    }

    @ViewBuilder
    func tableView(headers: [AttributedString], rows: [[AttributedString]]) -> some View {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(cells: headers, columnCount: columnCount, isHeader: true)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    tableRow(cells: row, columnCount: columnCount, isHeader: false)
                }
            }
            .padding(8)
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func tableRow(cells: [AttributedString], columnCount: Int, isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<columnCount, id: \.self) { column in
                Text(column < cells.count ? cells[column] : AttributedString())
                    .font(isHeader ? .body.weight(.semibold) : .body)
                    .frame(minWidth: 88, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.semibold)
        case 2: .title3.weight(.semibold)
        default: .headline
        }
    }
}
