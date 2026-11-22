import LorvexCore
import SwiftUI

/// A task opened from a journal entry owns its editor. The main window and a
/// separate Review window can both keep their original navigation and drafts.
struct ReviewTaskSheet: View {
  struct Selection: Identifiable {
    let id: LorvexTask.ID
    let store: AppStore

    @MainActor init(id: LorvexTask.ID, from parent: AppStore, undoManager: UndoManager?) {
      self.id = id
      store = parent.makeDetachedWindowStore()
      store.lists = parent.lists
      store.today = parent.today
      if let undoManager { store.reviewUndoDestination = (parent, ReviewTaskUndo(journal: undoManager)) }
    }
  }

  let selection: Selection
  @Environment(\.dismiss) private var dismiss
  @State private var loading = true
  @State private var closing = false

  private var store: AppStore { selection.store }

  var body: some View {
    Group {
      if loading || closing {
        ProgressView()
      } else if store.selectedTask != nil {
        TaskDetailView(store: store)
      } else {
        HStack {
          Button(String(localized: "common.try_again", defaultValue: "Try Again",
            table: "Localizable", bundle: LorvexL10n.bundle)) { Task { await load() } }
          Button(String(localized: "common.close", defaultValue: "Close",
            table: "Localizable", bundle: LorvexL10n.bundle)) { closeEditor() }
        }
      }
    }
    .frame(minWidth: 360, idealWidth: 470, maxWidth: .infinity,
      minHeight: 340, idealHeight: 580, maxHeight: .infinity)
    .accessibilityIdentifier("reviews.daily.taskDetail")
    .focusedSceneValue(\.lorvexTaskCommandContext,
      LorvexTaskCommandContext(store: store, selectionSurface: nil))
    .lorvexRecurringCancelDialog(store)
    .lorvexPermanentDeleteDialog(store)
    .lorvexErrorAlert(store)
    .task {
      store.startDetachedWindowObserversIfNeeded()
      await load()
    }
    .onChange(of: store.selectedTaskHasUnsavedEditorState) { wasDirty, dirty in
      if wasDirty && !dirty { Task { await store.resumeDeferredDetachedWindowReloadIfPossible() } }
    }
    .onChange(of: store.selectedTaskID) { previous, current in
      guard previous != nil, current == nil else { return }
      closing = true
      Task {
        await store.waitForLeftBehindDraftWrites()
        if store.selectedTaskID == nil && store.errorMessage == nil { closeEditor() }
        closing = false
      }
    }
    .onExitCommand {
      guard !closing else { return }
      if store.selectedTaskID != nil { store.selectedTaskID = nil } else { closeEditor() }
    }
    .onDisappear {
      store.reviewUndoDestination?.history.finish()
      store.stopDetachedWindowObservers()
      store.selectedTaskID = nil
      // Keep this editor alive until a write started by closing the window finishes.
      Task { await store.waitForLeftBehindDraftWrites() }
    }
  }

  private func closeEditor() {
    store.reviewUndoDestination?.history.finish()
    dismiss()
  }

  private func load() async {
    loading = true
    await store.loadDetachedTaskWindow(taskID: selection.id)
    loading = false
  }
}
