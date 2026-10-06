import AppKit
import Observation
import SwiftUI
import Testing

@testable import LorvexApple

@MainActor @Observable
private final class TextBox {
  var text: String
  init(_ text: String = "") { self.text = text }
}

private struct SingleLineField: View {
  @Bindable var box: TextBox

  var body: some View {
    TextField("Add", text: $box.text)
      .textFieldStyle(.plain)
      .lorvexSingleLine($box.text)
  }
}

/// Puts `content` in a window that is never shown, so its view updates run.
/// The caller keeps the window alive for as long as the content is needed.
@MainActor
private func hosted(_ content: some View) -> NSWindow {
  let host = NSHostingView(rootView: content.frame(width: 600, height: 120))
  host.frame = NSRect(x: 0, y: 0, width: 600, height: 120)
  let window = NSWindow(
    contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
  window.contentView = host
  host.layoutSubtreeIfNeeded()
  return window
}

/// Waits for `condition` to hold, up to a few seconds, so the checks that follow
/// read a settled view even when the machine is busy.
@MainActor
private func settle(until condition: () -> Bool) async {
  for _ in 0..<80 {
    if condition() { return }
    try? await Task.sleep(for: .milliseconds(50))
  }
}

/// A macOS single-line field keeps the line breaks of a multi-line paste and
/// draws a clipped second line; `lorvexSingleLine` rewrites the text it is
/// bound to with each break read as a space, so the field shows what the
/// capture reads. The text changes here from outside the field, which reaches
/// the modifier the way a paste does, without a first responder: tests that
/// each drive a window's first responder disturb one another when they run
/// together.
@MainActor
struct SingleLineTextTests {
  @Test func textWithLineBreaksIsRewrittenAsOneLine() async {
    let box = TextBox()
    let window = hosted(SingleLineField(box: box))
    defer { window.contentView = nil }

    box.text = "Call the caterer\nabout the quote\r\ntomorrow 3pm"
    let expected = "Call the caterer about the quote tomorrow 3pm"
    await settle { box.text == expected }

    #expect(box.text == expected)
  }

  @Test func aBreakInTheMiddleOfExistingTextJoinsToo() async {
    let box = TextBox("Buy and eggs")
    let window = hosted(SingleLineField(box: box))
    defer { window.contentView = nil }

    box.text = "Buy\nmilk\n and eggs"
    await settle { box.text == "Buy milk and eggs" }

    #expect(box.text == "Buy milk and eggs")
  }

  @Test func textWithoutABreakIsNeverRewritten() async throws {
    let box = TextBox()
    let window = hosted(SingleLineField(box: box))
    defer { window.contentView = nil }

    box.text = "Buy milk  and\teggs "
    try await Task.sleep(for: .milliseconds(400))

    #expect(box.text == "Buy milk  and\teggs ")
  }

  @Test func theQuickCaptureFieldKeepsItsLineOnOneLine() async throws {
    let store = AppStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    let model = QuickCaptureModel(store: store)
    let window = hosted(QuickCaptureCard(model: model))
    defer { window.contentView = nil }

    model.text = "Call the caterer\nabout the quote\ntomorrow 3pm"
    let expected = "Call the caterer about the quote tomorrow 3pm"
    await settle { model.text == expected }

    #expect(model.text == expected)
    #expect(model.preview().title == "Call the caterer about the quote")
  }
}
