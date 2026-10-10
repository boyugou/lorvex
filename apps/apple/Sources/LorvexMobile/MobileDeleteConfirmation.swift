import SwiftUI

extension View {
  /// Asks before a deletion: a dialog with a destructive confirm button and a
  /// Cancel, raised from this view.
  ///
  /// On the iPhone a confirmation dialog is a popover whose arrow points at the
  /// view that carries the modifier, so attach this to the control or row that
  /// raised the request. Attached to a whole screen, the popover opens at an
  /// arbitrary spot away from what the person tapped.
  ///
  /// A swipe action that raises the dialog must not carry the `destructive`
  /// role (see ``SwiftUI/View/mobileDestructiveSwipeStyle()``): that role
  /// collapses the row at the tap, and a dialog attached to the row closes
  /// with it.
  ///
  /// - Parameters:
  ///   - isPresented: Whether the dialog shows. The dialog clears it when it
  ///     closes.
  ///   - title: The question, read only while the dialog shows.
  ///   - message: A line under the question, such as what the deletion takes
  ///     with it.
  ///   - confirmTitle: The confirm button's name; "Delete" when omitted.
  ///   - delete: Runs when the confirm button is tapped.
  func mobileDeleteConfirmation(
    isPresented: Binding<Bool>,
    title: @autoclosure @escaping () -> String,
    message: String? = nil,
    confirmTitle: String? = nil,
    delete: @escaping () -> Void
  ) -> some View {
    modifier(
      MobileDeleteConfirmationModifier(
        isPresented: isPresented, title: title, message: message, confirmTitle: confirmTitle,
        delete: delete))
  }

  /// Asks before deleting `item`, from the row that shows it. The dialog
  /// shows while `pending` holds `item`, so every row of a list can carry the
  /// modifier over one shared `pending` and only the row being deleted
  /// presents. See ``SwiftUI/View/mobileDeleteConfirmation(isPresented:title:message:confirmTitle:delete:)``
  /// for how the dialog is placed and what each parameter does.
  func mobileDeleteConfirmation<Item: Identifiable & Sendable>(
    of item: Item,
    pending: Binding<Item?>,
    title: @autoclosure @escaping () -> String,
    message: String? = nil,
    confirmTitle: String? = nil,
    delete: @escaping (Item) -> Void
  ) -> some View {
    mobileDeleteConfirmation(
      isPresented: pending.isHolding(item), title: title(), message: message,
      confirmTitle: confirmTitle, delete: { delete(item) })
  }
}

extension Binding {
  /// A flag over an optional item: on while the optional holds `item`.
  /// Turning it on stores `item`; turning it off clears the optional only if
  /// it still holds `item`, so a row closing its own dialog cannot clear the
  /// request of another row.
  func isHolding<Item: Identifiable & Sendable>(_ item: Item) -> Binding<Bool>
  where Value == Item? {
    Binding<Bool>(
      get: { wrappedValue?.id == item.id },
      set: { isOn in
        if isOn {
          wrappedValue = item
        } else if wrappedValue?.id == item.id {
          wrappedValue = nil
        }
      })
  }
}

private struct MobileDeleteConfirmationModifier: ViewModifier {
  @Binding var isPresented: Bool
  let title: () -> String
  let message: String?
  let confirmTitle: String?
  let delete: () -> Void

  func body(content: Content) -> some View {
    content.confirmationDialog(
      isPresented ? title() : "",
      isPresented: $isPresented,
      titleVisibility: .visible
    ) {
      Button(confirmTitle ?? Self.deleteTitle, role: .destructive, action: delete)
      Button(Self.cancelTitle, role: .cancel) {}
    } message: {
      if let message { Text(message) }
    }
  }

  private static var deleteTitle: String {
    String(
      localized: "common.delete", defaultValue: "Delete", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  private static var cancelTitle: String {
    String(
      localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
