import SwiftUI

extension View {
  /// Gives a view that reacts only to a click a path for the keyboard. The view
  /// takes a focus stop, which Full Keyboard Access reaches with Tab and marks
  /// with a focus ring, and Return or Space runs `action`, as a click does.
  ///
  /// A bare `onTapGesture` has neither, so a person who cannot use a pointer
  /// could not reach the row, pill, or card at all. VoiceOver is separate: a
  /// focus stop gives it no action, so the view still needs its own
  /// `accessibilityAction`.
  func lorvexKeyboardActivation(_ action: @escaping () -> Void) -> some View {
    focusable(true)
      .onKeyPress(.return) {
        action()
        return .handled
      }
      .onKeyPress(.space) {
        action()
        return .handled
      }
  }

  /// Runs `action` when Delete or Forward Delete is pressed while the view
  /// holds the keyboard focus, as ⌫ does on a row of a task list. The view
  /// needs a focus stop of its own (``lorvexKeyboardActivation(_:)`` gives
  /// one). The action must ask before it removes anything: the key press is
  /// consumed, so it never reaches a Delete command higher in the hierarchy.
  func lorvexDeleteKey(_ action: @escaping () -> Void) -> some View {
    self
      .onKeyPress(.delete) {
        action()
        return .handled
      }
      .onKeyPress(.deleteForward) {
        action()
        return .handled
      }
  }
}
