import LorvexCore
import SwiftUI

/// A memory entry's pushed detail screen: the `MobileRoute.memoryEntry`
/// destination a compact Memory list row opens. Resolves the entry live from
/// the store so a peer's edit shows through, keeps following the entry when an
/// edit renames its key (the store's selection tracks the new key), and pops
/// itself once the entry it was showing is deleted. Loads the memory snapshot
/// itself when it is the first Memory screen on the stack.
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
      if store.memory == nil {
        List {
          MobileDetailSkeleton()
        }
      } else if let entry = currentEntry {
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
          description: Text(UserFacingError.Copy.standard.itemNoLongerExists)
        )
      }
    }
    // The entry's own title is the headline of the content; the generic
    // navigation title stays small so it does not compete with it.
    .navigationTitle(MobileDestination.memory.title)
    .toolbarTitleDisplayMode(.inline)
    .task {
      if store.memory == nil {
        await store.loadMemorySnapshot()
      }
    }
    .onChange(of: currentEntry?.id, initial: true) { previous, id in
      if let id, id == initialEntryID {
        store.selectMemoryEntry(id)
      }
      if previous != nil, id == nil {
        dismiss()
      }
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
