import LorvexCore
import SwiftUI

extension View {
  /// Asks which part of a repeating task a cancel reaches: only the occurrence
  /// in front of the person, or the whole series. A bare cancel of a repeating
  /// task spawns its next occurrence, so the choice is the person's to make.
  ///
  /// On the iPhone a confirmation dialog is a popover whose arrow points at the
  /// view that carries the modifier, so attach this to the control that raised
  /// the request, not to a whole screen.
  ///
  /// - Parameters:
  ///   - isPresented: Whether the dialog shows. The dialog clears it when it
  ///     closes.
  ///   - cancel: Runs with the chosen scope when a scope button is tapped.
  func mobileRecurringCancelDialog(
    isPresented: Binding<Bool>,
    cancel: @escaping (RecurringTaskCancelScope) -> Void
  ) -> some View {
    confirmationDialog(
      String(
        localized: "recurring_cancel.title", defaultValue: "Cancel Recurring Task",
        table: "Localizable", bundle: MobileL10n.bundle),
      isPresented: isPresented,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "recurring_cancel.this_occurrence", defaultValue: "This Occurrence",
          table: "Localizable", bundle: MobileL10n.bundle)
      ) {
        cancel(.thisOccurrence)
      }
      Button(
        String(
          localized: "recurring_cancel.all_occurrences", defaultValue: "All Occurrences",
          table: "Localizable", bundle: MobileL10n.bundle),
        role: .destructive
      ) {
        cancel(.all)
      }
      Button(
        String(
          localized: "recurring_cancel.keep", defaultValue: "Don’t Cancel", table: "Localizable",
          bundle: MobileL10n.bundle), role: .cancel
      ) {}
    } message: {
      Text(
        String(
          localized: "recurring_cancel.message",
          defaultValue: "Cancel only this occurrence, or end the whole repeating series?",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }
}
