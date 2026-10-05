import AppKit
import Foundation
import Testing

@testable import LorvexApple

/// ⌘⌫ is both the Task menu's Cancel Task and the text-editing key that deletes
/// to the beginning of the line; the menu must hand it to text being edited.
@Suite("Text editing keeps ⌘⌫")
@MainActor
struct LorvexTextEditingShortcutTests {
  private static let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  private static func key(
    _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, type: NSEvent.EventType = .keyDown
  ) -> NSEvent? {
    NSEvent.keyEvent(
      with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
      context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}",
      isARepeat: false, keyCode: keyCode)
  }

  /// A window whose first responder is a text view holding `text`, caret at the end.
  private static func editor(_ text: String, isEditable: Bool = true) -> (NSWindow, NSTextView) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.titled],
      backing: .buffered, defer: true)
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
    view.isEditable = isEditable
    view.string = text
    window.contentView?.addSubview(view)
    window.makeFirstResponder(view)
    view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    return (window, view)
  }

  @Test("only ⌘⌫ pressed alone is the shortcut")
  func recognizesCommandDeleteOnly() {
    #expect(LorvexTextEditingShortcut.isCommandDelete(Self.key(51, .command)))
    #expect(!LorvexTextEditingShortcut.isCommandDelete(Self.key(51, [])))
    #expect(!LorvexTextEditingShortcut.isCommandDelete(Self.key(51, [.command, .shift])))
    #expect(!LorvexTextEditingShortcut.isCommandDelete(Self.key(51, [.command, .option])))
    #expect(!LorvexTextEditingShortcut.isCommandDelete(Self.key(117, .command)))
    #expect(!LorvexTextEditingShortcut.isCommandDelete(Self.key(51, .command, type: .keyUp)))
    #expect(!LorvexTextEditingShortcut.isCommandDelete(nil))
  }

  @Test("while text is edited, ⌘⌫ deletes to the beginning of the line and the menu action stands down")
  func editingTextKeepsCommandDelete() {
    let (window, view) = Self.editor("alpha beta")
    #expect(LorvexTextEditingShortcut.yieldCommandDelete(event: Self.key(51, .command), window: window))
    #expect(view.string.isEmpty)
  }

  @Test("read-only text, other keys, menu clicks, and focus outside text leave the command to the menu")
  func everythingElseStaysWithTheMenu() {
    let (readOnlyWindow, readOnly) = Self.editor("alpha", isEditable: false)
    #expect(!LorvexTextEditingShortcut.yieldCommandDelete(event: Self.key(51, .command), window: readOnlyWindow))
    #expect(readOnly.string == "alpha")

    let (window, view) = Self.editor("alpha")
    #expect(!LorvexTextEditingShortcut.yieldCommandDelete(event: Self.key(51, [.command, .shift]), window: window))
    // Choosing the menu item with the pointer carries no key event.
    #expect(!LorvexTextEditingShortcut.yieldCommandDelete(event: nil, window: window))
    #expect(view.string == "alpha")

    let bare = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 120, height: 60), styleMask: [.titled],
      backing: .buffered, defer: true)
    #expect(!LorvexTextEditingShortcut.yieldCommandDelete(event: Self.key(51, .command), window: bare))
    #expect(!LorvexTextEditingShortcut.yieldCommandDelete(event: Self.key(51, .command), window: nil))
  }

  @Test("the Task menu asks the text first before it cancels a task")
  func cancelTaskYieldsToText() throws {
    let source = try String(
      contentsOf: Self.packageRoot.appendingPathComponent("Sources/LorvexApple/App/LorvexAppCommands.swift"),
      encoding: .utf8)
    #expect(source.contains("if command == .cancel, LorvexTextEditingShortcut.yieldCommandDelete() { return }"))
  }
}
