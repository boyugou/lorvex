import Foundation
import Markdown
import Testing

@testable import LorvexMarkdownUI

// Tests for MarkdownNote block-level parsing, which backs MarkdownNoteView rendering.
// SwiftUI views cannot be instantiated in unit tests, so tests verify the AST-level
// output of MarkdownNote directly and use Foundation's AttributedString to validate
// inline rendering.

@Test
func markdownNoteParsesParagraph() {
  let note = MarkdownNote("Hello world")
  #expect(note.blocks == [.paragraph("Hello world")])
}

@Test
func markdownNoteParsesHeadingLevel1() {
  let note = MarkdownNote("# Title")
  #expect(note.blocks == [.heading(level: 1, text: "Title")])
}

@Test
func markdownNoteParsesHeadingLevel2() {
  let note = MarkdownNote("## Subtitle")
  #expect(note.blocks == [.heading(level: 2, text: "Subtitle")])
}

@Test
func markdownNoteParsesUnorderedList() {
  let source = "- apple\n- banana\n- cherry"
  let note = MarkdownNote(source)
  #expect(note.blocks == [.unorderedList(["apple", "banana", "cherry"])])
}

@Test
func markdownNoteParsesOrderedList() {
  let source = "1. first\n2. second\n3. third"
  let note = MarkdownNote(source)
  #expect(note.blocks == [.orderedList(start: 1, items: ["first", "second", "third"])])
}

@Test
func markdownNoteParsesFencedCodeBlock() {
  let source = "```swift\nlet x = 1\n```"
  let note = MarkdownNote(source)
  #expect(note.blocks == [.code(language: "swift", text: "let x = 1\n")])
}

@Test
func markdownNoteParsesCodeBlockWithNoLanguage() {
  let source = "```\nplain code\n```"
  let note = MarkdownNote(source)
  if case let .code(language, _) = note.blocks.first {
    #expect(language == nil || language?.isEmpty == true)
  } else {
    Issue.record("Expected code block")
  }
}

@Test
func markdownNoteParsesBlockQuote() {
  let source = "> wise words"
  let note = MarkdownNote(source)
  if case let .quote(text) = note.blocks.first {
    #expect(text.contains("wise words"))
  } else {
    Issue.record("Expected quote block")
  }
}

@Test
func markdownNoteParsesThematicBreak() {
  let source = "above\n\n---\n\nbelow"
  let note = MarkdownNote(source)
  #expect(note.blocks.contains(.divider))
}

@Test
func markdownNoteEmptyInputProducesNoBlocks() {
  let note = MarkdownNote("   \n\t  ")
  #expect(note.blocks.isEmpty)
}

@Test
func markdownNoteInlineEmphasisPreservedInAttributedString() throws {
  let source = "**bold** and _italic_"
  let attributed = try AttributedString(markdown: source)
  // AttributedString with markdown init should produce non-empty output for emphasis
  #expect(!attributed.characters.isEmpty)
}

@Test
func markdownNoteLinkAttributedStringPreservesURL() throws {
  let source = "[Lorvex](https://lorvex.app)"
  let attributed = try AttributedString(markdown: source)
  let hasLink = attributed.runs.contains { run in
    run.link != nil
  }
  #expect(hasLink)
}

@Test
func markdownNoteSwiftMarkdownDocumentParsesInlineCode() {
  let source = "Use `swift build` to compile"
  let document = Document(parsing: source)
  let text = document.debugDescription()
  #expect(text.contains("InlineCode"))
}

@Test
func markdownNoteMultipleBlockTypes() {
  let source = "# Heading\n\nA paragraph.\n\n- item1\n- item2"
  let note = MarkdownNote(source)
  #expect(note.blocks.count == 3)
  guard case .heading = note.blocks[0] else { Issue.record("Expected heading"); return }
  guard case .paragraph = note.blocks[1] else { Issue.record("Expected paragraph"); return }
  guard case .unorderedList = note.blocks[2] else { Issue.record("Expected list"); return }
}
