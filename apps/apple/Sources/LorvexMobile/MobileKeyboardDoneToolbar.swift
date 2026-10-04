import SwiftUI

/// A keyboard accessory with a trailing Done button that dismisses the keyboard.
///
/// `numberPad` has no return key, so a focused numeric field otherwise traps the
/// user with no way to resign first responder. Attach this to numeric fields to
/// surface a Done button in the keyboard accessory bar.
struct MobileKeyboardDoneToolbar: ViewModifier {
  @FocusState private var focused: Bool

  func body(content: Content) -> some View {
    content
      .focused($focused)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(
            String(
              localized: "common.done", defaultValue: "Done", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            focused = false
          }
        }
      }
  }
}

extension View {
  /// Adds a keyboard accessory Done button that dismisses the keyboard, so
  /// `numberPad` fields (which lack a return key) do not trap focus.
  func mobileKeyboardDoneToolbar() -> some View {
    modifier(MobileKeyboardDoneToolbar())
  }
}
