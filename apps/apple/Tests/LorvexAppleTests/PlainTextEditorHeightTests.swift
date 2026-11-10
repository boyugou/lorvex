import AppKit
import Testing

@testable import LorvexApple

/// The inspector's notes editor is as tall as its text, so a long note shows
/// whole instead of hiding below an edge that has no scroll bar.
@MainActor
@Suite("Plain text editor height")
struct PlainTextEditorHeightTests {
  private func textView(width: CGFloat, text: String) -> NSTextView {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
    view.font = .systemFont(ofSize: 14)
    view.textContainerInset = NSSize(width: 0, height: 2)
    view.isVerticallyResizable = true
    view.textContainer?.widthTracksTextView = true
    view.string = text
    return view
  }

  @Test("the measured height follows the number of lines and the width")
  func heightFollowsTheText() {
    let oneLine = plainTextEditorContentHeight(of: textView(width: 300, text: "One line"))
    let tenLines = plainTextEditorContentHeight(
      of: textView(width: 300, text: Array(repeating: "A line", count: 10).joined(separator: "\n")))
    #expect(oneLine > 0)
    #expect(tenLines > oneLine * 8)

    let paragraph = String(repeating: "Buckeye Link opens registration on Tuesday. ", count: 12)
    let wide = plainTextEditorContentHeight(of: textView(width: 600, text: paragraph))
    let narrow = plainTextEditorContentHeight(of: textView(width: 200, text: paragraph))
    #expect(narrow > wide)
  }

  @Test("a text view with no width yet reports no height")
  func noWidthNoHeight() {
    #expect(plainTextEditorContentHeight(of: textView(width: 0, text: "Text")) == 0)
  }

  @Test("a growing editor is as tall as its text, within its minimum and maximum")
  func fittedHeightIsClamped() {
    #expect(LorvexPlainTextEditor.fittedHeight(contentHeight: 0, minHeight: 104, maxHeight: nil) == 104)
    #expect(LorvexPlainTextEditor.fittedHeight(contentHeight: 40, minHeight: 104, maxHeight: nil) == 104)
    #expect(LorvexPlainTextEditor.fittedHeight(contentHeight: 420, minHeight: 104, maxHeight: nil) == 420)
    #expect(LorvexPlainTextEditor.fittedHeight(contentHeight: 420, minHeight: 104, maxHeight: 300) == 300)
  }

  @Test("the task inspector's notes grow with their text")
  func inspectorNotesGrow() throws {
    let source = try String(
      contentsOfFile: "Sources/LorvexApple/Views/TaskDetailNotesSection.swift", encoding: .utf8)
    #expect(source.contains("growsWithContent: true"))
  }
}
