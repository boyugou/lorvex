import LorvexCore
import SwiftUI

extension View {
  /// Hosts the irreversible "Delete Permanently…" confirmation for a task.
  /// `AppStore.requestPermanentDelete(_:)` stages the task on the store; a
  /// `confirmationDialog` only presents on the window that mounts it, so apply
  /// this at every scene root where that store renders task actions (mirrors
  /// `lorvexRecurringCancelDialog(_:)`).
  func lorvexPermanentDeleteDialog(_ store: AppStore) -> some View {
    modifier(PermanentDeleteDialogModifier(store: store))
  }
}

private struct PermanentDeleteDialogModifier: ViewModifier {
  @Bindable var store: AppStore

  private var isPresented: Binding<Bool> {
    Binding(
      get: { store.pendingPermanentDeleteTask != nil },
      set: { if !$0 { store.pendingPermanentDeleteTask = nil } }
    )
  }

  func body(content: Content) -> some View {
    content.confirmationDialog(
      store.pendingPermanentDeleteTask.map {
        String(
          format: String(
            localized: "task.permanent_delete.title", defaultValue: "Delete “%@” permanently?",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          $0.title)
      } ?? "",
      isPresented: isPresented,
      titleVisibility: .visible,
      presenting: store.pendingPermanentDeleteTask
    ) { _ in
      Button(
        String(localized: "task.permanent_delete.confirm", defaultValue: "Delete Permanently", table: "Localizable", bundle: LorvexL10n.bundle),
        role: .destructive
      ) {
        Task { await store.confirmPermanentDelete() }
      }
      Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {
        store.pendingPermanentDeleteTask = nil
      }
    } message: { _ in
      Text(LocalizedStringResource(
        "task.permanent_delete.message",
        defaultValue: "The task and its checklist items, reminders, and links are deleted and can’t be restored. A copy of its last state stays in the activity log until retention removes it, and iCloud keeps an encrypted copy until you delete Lorvex’s iCloud data.",
        table: "Localizable",
        bundle: LorvexL10n.bundle))
    }
  }
}
