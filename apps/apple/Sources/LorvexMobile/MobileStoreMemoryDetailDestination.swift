import LorvexCore
import SwiftUI

@MainActor
struct MobileStoreMemoryDetailDestination: View {
  @Bindable var store: MobileStore
  let initialEntryID: MemoryEntry.ID
  let edit: (MemoryEntry) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var entryPendingDeletion: MemoryEntry?
  @State private var unusedBatchConfirmation = false

  var body: some View {
    Group {
      if let entry = currentEntry {
        MobileMemoryDetailPanel(
          entry: entry,
          isSaving: store.isSavingMemory,
          edit: { edit(entry) },
          delete: { entryPendingDeletion = entry }
        )
      } else {
        ContentUnavailableView(
          MobileDestination.memory.title,
          systemImage: "brain",
          description: Text(
            String(
              localized: "error.item_gone", defaultValue: "That item no longer exists.",
              table: "Localizable",
              bundle: MobileL10n.bundle))
        )
      }
    }
    .navigationTitle(currentEntry?.key ?? MobileDestination.memory.title)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      if currentEntry?.id == initialEntryID {
        store.selectMemoryEntry(initialEntryID)
      }
    }
    .onChange(of: currentEntry?.id) { _, id in
      if id == nil { dismiss() }
    }
    .mobileMemoryDeleteDialogs(
      entryPendingDeletion: $entryPendingDeletion,
      isConfirmingBatchDelete: $unusedBatchConfirmation,
      deleteEntry: deleteEntry,
      deleteBatch: {}
    )
  }

  private var currentEntry: MemoryEntry? {
    let entries = store.memory?.entries ?? []
    if let exact = entries.first(where: { $0.id == initialEntryID }) {
      return exact
    }
    guard let selectedMemoryKey = store.selectedMemoryKey else { return nil }
    return entries.first(where: { $0.id == selectedMemoryKey })
  }

  private func deleteEntry(_ entry: MemoryEntry) {
    Task {
      if await store.deleteMemoryEntry(entry) {
        dismiss()
      }
    }
  }
}
