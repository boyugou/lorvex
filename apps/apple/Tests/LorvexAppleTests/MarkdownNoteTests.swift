import Foundation
import Testing

@testable import LorvexMarkdownUI

@Test
func markdownNoteParsesCommonTaskNoteBlocks() {
    let note = MarkdownNote(
        """
        ## Plan

        Ship **native** detail rendering.

        - Parse notes
        - Render SwiftUI

        ```swift
        let app = "Lorvex"
        ```

        > Keep MCP semantics intact.
        """
    )

    #expect(note.blocks == [
        .heading(level: 2, text: "Plan"),
        .paragraph("Ship **native** detail rendering."),
        .unorderedList(["Parse notes", "Render SwiftUI"]),
        .code(language: "swift", text: "let app = \"Lorvex\"\n"),
        .quote("Keep MCP semantics intact.")
    ])
}

@Test
func markdownNoteParsesOrderedListsAndDividers() {
    let note = MarkdownNote(
        """
        3. First
        4. Second

        ---
        """
    )

    #expect(note.blocks == [
        .orderedList(start: 3, items: ["First", "Second"]),
        .divider
    ])
}

@Test
func markdownNoteDropsEmptyInput() {
    let note = MarkdownNote(" \n\t ")

    #expect(note.blocks.isEmpty)
}

@Test
func markdownNotePreservesInlineMarkupSource() {
    // Inline-bearing blocks carry their markdown source so the renderer can style
    // bold/links/strikethrough — they are no longer flattened to plain text.
    let note = MarkdownNote("See **bold**, ~~old~~, and [docs](https://x.com).")
    #expect(note.blocks == [
        .paragraph("See **bold**, ~~old~~, and [docs](https://x.com).")
    ])
}

@Test
func markdownNoteKeepsMarkdownImagesAsText() {
    let source = "![legacy](lorvex-image://00000000-0000-0000-0000-000000000000)"
    let note = MarkdownNote(source)
    #expect(note.blocks == [.paragraph(source)])
}

@Test
func markdownNoteParsesGFMTaskList() {
    let note = MarkdownNote(
        """
        - [ ] Draft outline
        - [x] Collect ~~links~~
        - [X] Review
        """
    )

    #expect(note.blocks == [
        .taskList([
            .init(isChecked: false, text: "Draft outline"),
            .init(isChecked: true, text: "Collect ~~links~~"),
            .init(isChecked: true, text: "Review"),
        ])
    ])
}

@Test
func markdownNotePlainBulletStaysUnorderedListNotTaskList() {
    // A list with no checkboxes must remain a plain bulleted list.
    let note = MarkdownNote(
        """
        - One
        - Two
        """
    )
    #expect(note.blocks == [.unorderedList(["One", "Two"])])
}

@Test
func markdownNoteParsesGFMTable() {
    let note = MarkdownNote(
        """
        | Name | Status |
        | ---- | ------ |
        | Ship | **done** |
        | Plan | open |
        """
    )

    #expect(note.blocks == [
        .table(
            headers: ["Name", "Status"],
            rows: [["Ship", "**done**"], ["Plan", "open"]]
        )
    ])
}

/// Concatenated text of every run carrying `target` presentation intent.
private func text(_ attributed: AttributedString, with target: InlinePresentationIntent) -> String {
    attributed.runs
        .filter { ($0.inlinePresentationIntent ?? []).contains(target) }
        .map { String(attributed[$0.range].characters) }
        .joined()
}

@Test
func inlineMarkdownAppliesPresentationIntents() {
    let s = MarkdownInline.attributedString("a **bold** _italic_ ~~struck~~ `code`")
    #expect(text(s, with: .stronglyEmphasized) == "bold")
    #expect(text(s, with: .emphasized) == "italic")
    #expect(text(s, with: .strikethrough) == "struck")
    #expect(text(s, with: .code) == "code")
    #expect(String(s.characters) == "a bold italic struck code")
}

@Test
func inlineMarkdownStrikethroughDoesNotLeakToPlainDuplicates() {
    // Regression: only the `~~done~~` span is struck, not the later plain "done".
    let s = MarkdownInline.attributedString("~~done~~ done again")
    #expect(text(s, with: .strikethrough) == "done")
    #expect(String(s.characters) == "done done again")
}

@Test
func inlineMarkdownPreservesLinkURL() {
    let s = MarkdownInline.attributedString("see [docs](https://lorvex.app/x)")
    let linked = s.runs.first { $0.link != nil }
    #expect(linked.map { String(s[$0.range].characters) } == "docs")
    #expect(s.runs.contains { $0.link?.absoluteString == "https://lorvex.app/x" })
}

@Test
func inlineMarkdownPlainTextHasNoIntents() {
    let s = MarkdownInline.attributedString("just plain words")
    #expect(s.runs.allSatisfy { ($0.inlinePresentationIntent ?? []).isEmpty })
    #expect(String(s.characters) == "just plain words")
}
