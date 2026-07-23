import SwiftUI

/// Renders a markdown string as native SwiftUI, the single rendered-markdown
/// surface across the Lorvex Apple app.
///
/// Block kinds (see ``MarkdownNote/Block``) render as: headings, paragraphs with
/// inline emphasis/bold/inline-code/links/strikethrough, bulleted and numbered
/// lists, GFM task lists (checkbox rows), fenced code blocks, block quotes, GFM
/// tables, and thematic-break dividers.
///
/// Parsing the source into a ``MarkdownNote`` is the expensive step. Callers that
/// re-render on every keystroke (an editor preview) should parse once into their
/// own `@State` and pass the parsed note via ``init(note:)`` so the
/// swift-markdown AST is not rebuilt per render. The `String` initializers parse
/// eagerly and suit one-shot rendering of stable content.
/// VoiceOver phrasing for GFM task-list rows, supplied by the caller so this
/// catalog-less rendering module stays localized by whichever surface hosts it.
/// Each format takes a single `%@` — the task item's source text.
public struct MarkdownTaskItemAccessibilityLabels: Sendable {
    public let completedFormat: String
    public let todoFormat: String

    public init(completedFormat: String = "Completed: %@", todoFormat: String = "To do: %@") {
        self.completedFormat = completedFormat
        self.todoFormat = todoFormat
    }
}

public struct MarkdownNoteView: View {
    let note: MarkdownNote
    let taskItemAccessibility: MarkdownTaskItemAccessibilityLabels

    /// Render an already-parsed note. Use this from re-rendering surfaces to keep
    /// the swift-markdown parse off the render path.
    public init(
        note: MarkdownNote,
        taskItemAccessibility: MarkdownTaskItemAccessibilityLabels = .init()
    ) {
        self.note = note
        self.taskItemAccessibility = taskItemAccessibility
    }

    public init(
        _ source: String,
        taskItemAccessibility: MarkdownTaskItemAccessibilityLabels = .init()
    ) {
        self.init(note: MarkdownNote(source), taskItemAccessibility: taskItemAccessibility)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(note.renderedBlocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownNote.RenderedBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(text)
                .font(headingFont(level: level))
        case let .paragraph(text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.secondary)
                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .orderedList(start, items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(start + offset).")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case let .taskList(items):
            taskListView(items)
        case let .table(headers, rows):
            tableView(headers: headers, rows: rows)
        case let .code(language, text):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        case let .quote(text):
            Text(text)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.tertiary)
                        .frame(width: 3)
                }
                .foregroundStyle(.secondary)
        case .divider:
            Divider()
        }
    }

}
