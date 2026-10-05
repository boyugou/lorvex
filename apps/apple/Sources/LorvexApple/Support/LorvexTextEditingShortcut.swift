import AppKit

/// A shortcut that is both a menu command and a text-editing key.
///
/// AppKit offers a key equivalent to the main menu before the focused text view
/// sees it. The Task menu binds Cancel Task to ⌘⌫, which is also "delete to the
/// beginning of the line" in every text field, so without this a person who
/// clears a title, a note, or the quick-add line with ⌘⌫ would cancel whichever
/// task is selected instead.
@MainActor
enum LorvexTextEditingShortcut {
  /// The virtual key code of the Delete (backspace) key.
  private static let deleteKeyCode: UInt16 = 51

  /// Whether `event` is a press of ⌘⌫ with no other modifier.
  static func isCommandDelete(_ event: NSEvent?) -> Bool {
    guard let event, event.type == .keyDown else { return false }
    return event.keyCode == deleteKeyCode
      && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
  }

  /// Gives ⌘⌫ to the text being edited when a menu action bound to it was
  /// triggered by that key press while an editable text view (a text field's
  /// editor or a text editor) is the key window's first responder: the text
  /// deletes to the beginning of its line, as it would without the menu item.
  ///
  /// - Returns: `true` when the key went to the text, so the menu action must do
  ///   nothing. `false` for a click on the menu item, for any other key, and
  ///   whenever focus is not in editable text.
  static func yieldCommandDelete(
    event: NSEvent? = NSApp.currentEvent, window: NSWindow? = NSApp.keyWindow
  ) -> Bool {
    guard isCommandDelete(event),
      let text = window?.firstResponder as? NSTextView, text.isEditable
    else { return false }
    text.deleteToBeginningOfLine(nil)
    return true
  }
}
