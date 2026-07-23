import LorvexCore
import SwiftUI

extension View {
  /// Hosts the occurrence-vs-series confirmation for cancelling a recurring
  /// task on the mobile surface. `MobileStore.requestCancelTask(_:)` sets
  /// `pendingRecurringCancelTaskID`; a `confirmationDialog` only presents on
  /// the view that mounts it, so this is applied once at the shell root.
  /// Mirrors the macOS `lorvexRecurringCancelDialog(_:)`.
  func mobileRecurringCancelDialog(_ store: MobileStore) -> some View {
    modifier(MobileRecurringCancelDialogModifier(store: store))
  }
}

private struct MobileRecurringCancelDialogModifier: ViewModifier {
  @Bindable var store: MobileStore

  private var isPresented: Binding<Bool> {
    Binding(
      get: { store.pendingRecurringCancelTaskID != nil },
      set: { if !$0 { store.pendingRecurringCancelTaskID = nil } }
    )
  }

  func body(content: Content) -> some View {
    content.confirmationDialog(
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
        guard let id = store.pendingRecurringCancelTaskID else { return }
        Task { await store.cancelRecurringTask(id: id, scope: .thisOccurrence) }
      }
      Button(
        String(
          localized: "recurring_cancel.all_occurrences", defaultValue: "All Occurrences",
          table: "Localizable", bundle: MobileL10n.bundle),
        role: .destructive
      ) {
        guard let id = store.pendingRecurringCancelTaskID else { return }
        Task { await store.cancelRecurringTask(id: id, scope: .all) }
      }
      Button(
        String(
          localized: "recurring_cancel.keep", defaultValue: "Don't Cancel", table: "Localizable",
          bundle: MobileL10n.bundle), role: .cancel
      ) {
        store.pendingRecurringCancelTaskID = nil
      }
    } message: {
      Text(
        String(
          localized: "recurring_cancel.message",
          defaultValue: "Cancel only this occurrence, or end the whole repeating series?",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }
}
