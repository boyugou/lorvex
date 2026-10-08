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

// A note may hold 50,000 characters and the parser recurses once per level of
// nesting, so the deepest notes the limit allows must build on any thread: a
// test body runs on a worker thread whose stack is far smaller than the main
// thread's.

@Test
func markdownNoteBuildsFromQuotesNestedAsDeeplyAsTheLengthLimitAllows() {
    let note = MarkdownNote(String(repeating: ">", count: 49_998) + " x")

    #expect(note.blocks == [.quote("x")])
    #expect(note.renderedBlocks.count == 1)
}

@Test
func markdownNoteBuildsFromEmphasisNestedAsDeeplyAsTheLengthLimitAllows() {
    let note = MarkdownNote(
        String(repeating: "_a ", count: 8_000) + String(repeating: "a_ ", count: 8_000))

    #expect(note.blocks.count == 1)
    #expect(note.renderedBlocks.count == 1)
    guard case .paragraph(let text) = note.blocks[0] else {
        Issue.record("expected a paragraph, got \(note.blocks[0])")
        return
    }
    #expect(text.contains("a"))
}

@Test
func markdownNoteBuildsFromListsNestedAsDeeplyAsTheLengthLimitAllows() {
    #expect(MarkdownNote(String(repeating: "- ", count: 25_000) + "x").blocks.count == 1)
    #expect(MarkdownNote(String(repeating: "1. ", count: 16_666) + "x").blocks.count == 1)
    #expect(MarkdownNote(String(repeating: "> - ", count: 12_500) + "x").blocks.count == 1)
}

@Test
func markdownNoteShowsASourceBeyondTheParseLimitVerbatim() {
    let source = String(repeating: ">", count: MarkdownNote.maxParsedScalars) + " x"
    let note = MarkdownNote(source)

    #expect(note.blocks == [.code(language: nil, text: source)])
    #expect(note.renderedBlocks == [.code(language: nil, text: source)])
}

@Test
func markdownNoteCountsCharactersNotBytesAgainstTheParseLimit() {
    // 50,000 CJK characters take 150,000 bytes, more than the limit, yet are
    // within the length a note may have and keep their markdown.
    let note = MarkdownNote("**" + String(repeating: "字", count: 50_000) + "**")

    #expect(note.blocks == [.paragraph("**" + String(repeating: "字", count: 50_000) + "**")])
}
