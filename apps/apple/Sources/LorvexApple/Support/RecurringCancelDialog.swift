import LorvexCore
import SwiftUI

extension View {
  /// Hosts the occurrence-vs-series confirmation for cancelling a recurring
  /// task. `AppStore.requestCancel(_:)` sets `pendingRecurringCancelTaskID` on
  /// the store that owns the task surface, but a `confirmationDialog` only
  /// presents on the window that mounts it. Apply this modifier at every scene
  /// root where that same store can render task actions: the main/workspace
  /// store for shared windows, and the per-window store for detached task/list
  /// windows.
  func lorvexRecurringCancelDialog(_ store: AppStore) -> some View {
    modifier(RecurringCancelDialogModifier(store: store))
  }
}

private struct RecurringCancelDialogModifier: ViewModifier {
  @Bindable var store: AppStore

  private var isPresented: Binding<Bool> {
    Binding(
      get: { store.pendingRecurringCancelTaskID != nil || store.pendingRecurringBatchCancel != nil },
      set: {
        if !$0 {
          store.pendingRecurringCancelTaskID = nil
          store.pendingRecurringBatchCancel = nil
        }
      }
    )
  }

  private var hasPendingBatch: Bool {
    store.pendingRecurringBatchCancel != nil
  }

  /// A batch with no recurring tasks: no occurrence-vs-series choice applies, so
  /// the dialog is a plain "cancel these tasks?" confirmation instead.
  private var isPlainBatch: Bool {
    store.pendingRecurringBatchCancel?.recurringTaskIDs.isEmpty == true
  }

  private var dialogTitle: String {
    if isPlainBatch {
      return String(
        localized: "batch_cancel.plain_title", defaultValue: "Cancel selected tasks?",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    if hasPendingBatch {
      return String(
        localized: "recurring_cancel.batch_title", defaultValue: "Cancel Recurring Tasks",
        table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(
      localized: "recurring_cancel.title", defaultValue: "Cancel Recurring Task",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  func body(content: Content) -> some View {
    content.confirmationDialog(
      dialogTitle,
      isPresented: isPresented,
      titleVisibility: .visible
    ) {
      if isPlainBatch {
        Button(
          String(localized: "batch_cancel.plain_confirm", defaultValue: "Cancel Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
          role: .destructive
        ) {
          Task { await store.confirmPendingRecurringBatchCancel(scope: .thisOccurrence) }
        }
      } else {
        Button(String(localized: "recurring_cancel.this_occurrence", defaultValue: "This Occurrence", table: "Localizable", bundle: LorvexL10n.bundle)) {
          if store.pendingRecurringBatchCancel != nil {
            Task { await store.confirmPendingRecurringBatchCancel(scope: .thisOccurrence) }
            return
          }
          guard let id = store.pendingRecurringCancelTaskID else { return }
          store.pendingRecurringCancelTaskID = nil
          Task { await store.cancelRecurringTask(id: id, scope: .thisOccurrence) }
        }
        Button(
          String(
            localized:
              "recurring_cancel.all_occurrences",
              defaultValue: "All Occurrences",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
          role: .destructive
        ) {
          if store.pendingRecurringBatchCancel != nil {
            Task { await store.confirmPendingRecurringBatchCancel(scope: .all) }
            return
          }
          guard let id = store.pendingRecurringCancelTaskID else { return }
          store.pendingRecurringCancelTaskID = nil
          Task { await store.cancelRecurringTask(id: id, scope: .all) }
        }
      }
      Button(
        String(localized: "recurring_cancel.keep", defaultValue: "Don't Cancel", table: "Localizable", bundle: LorvexL10n.bundle),
        role: .cancel
      ) {
        store.pendingRecurringCancelTaskID = nil
        store.pendingRecurringBatchCancel = nil
      }
    } message: {
      if isPlainBatch {
        Text(
          LocalizedStringResource(
            "batch_cancel.plain_message",
            defaultValue: "The selected tasks will be cancelled. You can reopen them individually.",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
      } else {
        if hasPendingBatch {
          Text(LocalizedStringResource(
            "recurring_cancel.batch_message",
            defaultValue: "Cancel only the selected occurrences, or end every selected repeating series?",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
        } else {
          Text(LocalizedStringResource(
            "recurring_cancel.message",
            defaultValue: "Cancel only this occurrence, or end the whole repeating series?",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
        }
      }
    }
  }
}
