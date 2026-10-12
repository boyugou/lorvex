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

  /// Moves the keyboard focus between rows that each hold a focus stop
  /// (``lorvexKeyboardActivation(_:)``): ↑ and ↓ focus the neighboring row in
  /// `order`, Home and End the first and last, and none wraps. The row
  /// registers `id` with `focus`, so the surface holds one `@FocusState` for
  /// the whole list. SwiftUI scrolls the newly focused row into view.
  func lorvexArrowKeyFocus(
    id: String, order: [String], focus: FocusState<String?>.Binding
  ) -> some View {
    func move(_ step: WorkspaceTaskArrowKeyStep) -> KeyPress.Result {
      guard
        let target = WorkspaceTaskArrowKeyMovement.target(for: step, anchor: id, orderedIDs: order)
      else { return .handled }
      focus.wrappedValue = target
      return .handled
    }
    return focused(focus, equals: id)
      .onKeyPress(.upArrow) { move(.previous) }
      .onKeyPress(.downArrow) { move(.next) }
      .onKeyPress(.home) { move(.first) }
      .onKeyPress(.end) { move(.last) }
  }
}
