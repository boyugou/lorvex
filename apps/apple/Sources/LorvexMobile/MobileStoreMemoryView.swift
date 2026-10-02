import LorvexCore
import SwiftUI

/// Full-screen Memory workspace for iPhone/iPad: every memory entry with
/// search, batch selection, and delete. New entries are drafted in the New
/// Memory sheet behind the toolbar ＋; existing ones open the editor sheet.
@MainActor
public struct MobileStoreMemoryView: View {
  @Bindable var store: MobileStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var searchQuery = ""
  @State private var isBatchSelecting = false
  @State private var batchSelectedMemoryKeys = Set<MemoryEntry.ID>()
  @State private var entryPendingDeletion: MemoryEntry?
  @State private var isConfirmingBatchDelete = false
  @State private var editingEntry: MemoryEntry?
  @State private var isComposingMemory = false

  public init(store: MobileStore) {
    self.store = store
  }

  public var body: some View {
    Group {
      if horizontalSizeClass == .regular {
        regularBody
      } else {
        compactBody
      }
    }
    .navigationTitle(MobileDestination.memory.title)
    .toolbar {
      Button {
        toggleBatchSelection()
      } label: {
        // Words, as Mail and Files write them: a glyph here would repeat the
        // Tasks tab's checklist and read as a jump to Tasks.
        Text(batchSelectionTitle)
      }
      // Never disable while batch selecting, or an emptied catalog would trap the
      // user in selection mode with no way back out. Gate on the UNFILTERED set so
      // a no-match search doesn't hide the entry point (mirrors the Lists screen).
      .disabled(!isBatchSelecting && (store.memory == nil || allMemoryEntries.isEmpty))
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileMemory.batch.toggle")

      if !isBatchSelecting {
        Button {
          isComposingMemory = true
        } label: {
          Label(newMemoryTitle, systemImage: "plus")
        }
        .lorvexToolbarHoverEffect()
        .disabled(store.isSavingMemory)
        .accessibilityIdentifier("mobileMemory.new")
      }
    }
    .task {
      if store.memory == nil {
        await store.loadMemorySnapshot()
      }
    }
    .task(id: allMemoryKeys) {
      if let selectedMemoryKey = store.selectedMemoryKey,
        !allMemoryEntries.contains(where: { $0.id == selectedMemoryKey })
      {
        store.selectMemoryEntry(nil)
      }
      pruneBatchSelection()
    }
    .refreshable {
      await store.refresh()
      await store.loadMemorySnapshot()
    }
    .searchable(
      text: $searchQuery,
      prompt: String(
        localized: "memory.search.prompt", defaultValue: "Search memory", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .mobileMemoryDeleteDialogs(
      entryPendingDeletion: $entryPendingDeletion,
      isConfirmingBatchDelete: $isConfirmingBatchDelete,
      deleteEntry: deleteMemoryEntry,
      deleteBatch: { Task { await deleteSelectedMemory() } }
    )
    .sheet(item: $editingEntry) { entry in
      MobileStoreMemoryEditorSheet(store: store, entry: entry)
    }
    .sheet(isPresented: $isComposingMemory) {
      MobileStoreMemoryComposerSheet(store: store)
    }
    #if DEBUG
      .onAppear {
        // Dev/QA only: the `lorvex://memorycomposer` screenshot hook raises the
        // New Memory sheet so it can be captured without a tap.
        if MobileMemoryDebugState.takePresentsComposerOnAppear() {
          isComposingMemory = true
        }
      }
    #endif
    .safeAreaInset(edge: .bottom) {
      if isBatchSelecting {
        MobileBatchActionBar(
          selectedCount: batchSelectedMemoryKeys.count,
          countText: String(
            localized: "memory.batch.selected_count",
            defaultValue: "\(batchSelectedMemoryKeys.count) selected",
            table: "Localizable", bundle: MobileL10n.bundle),
          deleteLabel: String(
            localized: "common.delete", defaultValue: "Delete", table: "Localizable",
            bundle: MobileL10n.bundle),
          canDelete: canDeleteSelectedMemory,
          isBusy: store.isSavingMemory,
          accessibilityID: "mobileMemory.batch.bar",
          clear: { batchSelectedMemoryKeys.removeAll() },
          delete: { isConfirmingBatchDelete = true }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .accessibilityIdentifier("mobileMemory.root")
  }

  @ViewBuilder
  private var compactBody: some View {
    regularList
  }

  private var regularBody: some View {
    MobileAdaptiveListDetail(selection: memorySelection) {
      regularList
    } detail: { id in
      if let entry = allMemoryEntries.first(where: { $0.id == id }) {
        detailPanel(for: entry)
      } else {
        placeholder
      }
    } placeholder: {
      placeholder
    }
  }

  private var regularList: some View {
    List(selection: memorySelection) {
      catalogSection
    }
    // Focusable like the Tasks list, so a selected row shows the focus
    // system's quiet fill; the accent fill of a list outside the focus system
    // hides the row's own tint and its trailing control.
    .focusable()
  }

  private var catalogSection: some View {
    Section {
      if store.memory == nil {
        MobileSkeletonRows(count: 4)
      } else if let memory = store.memory, memory.entries.isEmpty {
        // Text only: the toolbar ＋ already owns "new memory", so the row points
        // at it instead of repeating the action.
        MobileEmptyState(
          icon: "brain",
          tint: LorvexDesign.Palette.Destination.memory,
          title: String(
            localized: "memory.empty.no_entries", defaultValue: "No Memory Entries",
            table: "Localizable", bundle: MobileL10n.bundle),
          message: String(
            localized: "memory.empty.message",
            defaultValue: "Tap ＋ to save something your assistant should remember.",
            table: "Localizable", bundle: MobileL10n.bundle))
      } else if memoryEntries.isEmpty {
        MobileEmptyState.search(text: searchQuery)
      } else {
        ForEach(memoryEntries) { entry in
          catalogRow(for: entry)
          .buttonStyle(.plain)
          .lorvexRowHoverEffect()
          .swipeActions(edge: .leading, allowsFullSwipe: false) {
            memoryEditAction(entry)
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            memoryDeleteAction(entry)
          }
          .contextMenu {
            memoryEditAction(entry)
            memoryDeleteAction(entry)
          }
          .tag(entry.id)
        }
      }
    }
  }

  private func detailPanel(for entry: MemoryEntry) -> some View {
    MobileMemoryDetailPanel(
      entry: entry,
      isSaving: store.isSavingMemory,
      edit: { presentEditor(for: entry) },
      delete: { entryPendingDeletion = entry }
    )
  }

  @ViewBuilder
  private func catalogRow(for entry: MemoryEntry) -> some View {
    if isBatchSelecting {
      Button {
        toggleBatchSelection(for: entry.id)
      } label: {
        batchSelectableRow(for: entry)
      }
    } else if horizontalSizeClass == .regular {
      Button {
        store.selectMemoryEntry(entry.id)
      } label: {
        batchSelectableRow(for: entry)
      }
    } else {
      NavigationLink(value: MobileRoute.memoryEntry(entry.id)) {
        batchSelectableRow(for: entry)
      }
    }
  }

  private var placeholder: some View {
    ContentUnavailableView {
      Label(
        String(
          localized: "memory.detail.empty.title", defaultValue: "Select a Memory",
          table: "Localizable", bundle: MobileL10n.bundle), systemImage: "brain")
    } description: {
      Text(
        String(
          localized: "memory.detail.empty.description",
          defaultValue: "Choose a memory to read it.", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
  }

  private var memorySelection: Binding<MemoryEntry.ID?> {
    Binding(
      get: { store.selectedMemoryKey },
      set: { store.selectMemoryEntry($0) }
    )
  }

  private var memoryEntries: [MemoryEntry] {
    LorvexCatalogSearch.memory(allMemoryEntries, query: searchQuery)
  }

  private var allMemoryEntries: [MemoryEntry] {
    store.memory?.entries ?? []
  }

  private var allMemoryKeys: [MemoryEntry.ID] {
    allMemoryEntries.map(\.id)
  }

  private var selectedMemoryEntries: [MemoryEntry] {
    allMemoryEntries.filter { batchSelectedMemoryKeys.contains($0.id) }
  }

  private var canDeleteSelectedMemory: Bool {
    !selectedMemoryEntries.isEmpty
  }

  private var batchSelectionTitle: String {
    isBatchSelecting
      ? String(
        localized: "common.done", defaultValue: "Done", table: "Localizable",
        bundle: MobileL10n.bundle)
      : String(
        localized: "memory.batch.select", defaultValue: "Select", table: "Localizable",
        bundle: MobileL10n.bundle)
  }

  private func batchSelectableRow(for entry: MemoryEntry) -> some View {
    MobileBatchSelectableRow(
      isBatchSelecting: isBatchSelecting,
      isSelected: batchSelectedMemoryKeys.contains(entry.id),
      selectionLabel: String(
        localized: "memory.batch.select_memory", defaultValue: "Select memory",
        table: "Localizable", bundle: MobileL10n.bundle)
    ) {
      MobileMemoryCatalogRow(entry: entry)
    }
  }

  private func toggleBatchSelection() {
    withAnimation(.snappy) {
      isBatchSelecting.toggle()
      if !isBatchSelecting {
        batchSelectedMemoryKeys.removeAll()
      }
    }
  }

  private func toggleBatchSelection(for id: MemoryEntry.ID) {
    if batchSelectedMemoryKeys.contains(id) {
      batchSelectedMemoryKeys.remove(id)
    } else {
      batchSelectedMemoryKeys.insert(id)
    }
  }

  private func pruneBatchSelection() {
    let validKeys = Set(allMemoryKeys)
    batchSelectedMemoryKeys.formIntersection(validKeys)
    if allMemoryEntries.isEmpty {
      withAnimation(.snappy) {
        isBatchSelecting = false
      }
    }
  }

  private func deleteSelectedMemory() async {
    guard await store.deleteMemoryEntries(selectedMemoryEntries) else { return }
    batchSelectedMemoryKeys.removeAll()
    withAnimation(.snappy) {
      isBatchSelecting = false
    }
  }

  private func deleteMemoryEntry(_ entry: MemoryEntry) {
    Task {
      await store.deleteMemoryEntry(entry)
      entryPendingDeletion = nil
    }
  }

  private func presentEditor(for entry: MemoryEntry) {
    // The editor sheet owns its own draft seeded from `entry`; the New Memory
    // sheet's draft lives in the store, so a half-typed new entry survives
    // opening the editor for another one.
    editingEntry = entry
  }

  private func memoryEditAction(_ entry: MemoryEntry) -> some View {
    Button {
      presentEditor(for: entry)
    } label: {
      Label(
        String(
          localized: "common.edit", defaultValue: "Edit", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "pencil")
    }
    .tint(LorvexDesign.Palette.accent)
    .disabled(store.isSavingMemory)
    .accessibilityIdentifier("mobileMemory.edit.\(entry.key)")
  }

  private func memoryDeleteAction(_ entry: MemoryEntry) -> some View {
    Button(role: .destructive) {
      entryPendingDeletion = entry
    } label: {
      Label(
        String(
          localized: "common.delete", defaultValue: "Delete", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "trash")
    }
    .disabled(store.isSavingMemory)
    .accessibilityIdentifier("mobileMemory.delete.\(entry.key)")
  }

  private var newMemoryTitle: String {
    String(
      localized: "memory.new", defaultValue: "New Memory", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
