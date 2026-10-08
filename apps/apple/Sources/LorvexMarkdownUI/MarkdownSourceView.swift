import SwiftUI

/// Renders markdown source as ``MarkdownNoteView`` does, and parses and lays it
/// out again only when the source or the task-item labels change.
///
/// A view that redraws often for other reasons (a task's detail beside the
/// editor of its notes, which redraws on every keystroke) would otherwise parse
/// the same source on each pass, and the parse takes time in proportion to the
/// source's length. Its content is compared by value, so a redraw with the same
/// inputs skips both the parse and the rendering of every block.
public struct MarkdownSourceView: View {
    let source: String
    let taskItemAccessibility: MarkdownTaskItemAccessibilityLabels

    public init(
        _ source: String,
        taskItemAccessibility: MarkdownTaskItemAccessibilityLabels = .init()
    ) {
        self.source = source
        self.taskItemAccessibility = taskItemAccessibility
    }

    public var body: some View {
        Content(source: source, taskItemAccessibility: taskItemAccessibility).equatable()
    }

    /// The part that parses: SwiftUI evaluates its `body` only when an input differs.
    struct Content: View, Equatable {
        let source: String
        let taskItemAccessibility: MarkdownTaskItemAccessibilityLabels

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.source == rhs.source && lhs.taskItemAccessibility == rhs.taskItemAccessibility
        }

        var body: some View {
            MarkdownNoteView(source, taskItemAccessibility: taskItemAccessibility)
        }
    }
}
