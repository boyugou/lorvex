import LorvexCore
import SwiftUI

/// Full-screen Memory workspace for iPhone/iPad. Exposes key/content drafting,
/// all memory entries, and delete affordances.
@MainActor
public struct MobileStoreMemoryView: View {
  @Bindable var store: MobileStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var searchQuery = ""
  @State private var isBatchSelecting = false
  @State private var batchSelectedMemoryKeys = Set<MemoryEntry.ID>()
  @State private var entryPendingDeletion: MemoryEntry?
  @State private var isConfirmingBatchDelete = false
  @State private var isPresentingMemoryEditor = false
  @FocusState private var focusedField: Field?

  private enum Field {
    case key
    case content
  }

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
        Label(batchSelectionTitle, systemImage: batchSelectionIcon)
      }
      // Never disable while batch selecting, or an emptied catalog would trap the
      // user in selection mode with no way back out.
      .disabled(!isBatchSelecting && (store.memory == nil || memoryEntries.isEmpty))
      .accessibilityIdentifier("mobileMemory.batch.toggle")
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
      await store.refreshResettingCloudSyncPacing()
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
    .sheet(isPresented: $isPresentingMemoryEditor) {
      MobileStoreMemoryEditorSheet(store: store, isPresented: $isPresentingMemoryEditor)
        .lorvexSpatialBackground()
    }
    .safeAreaInset(edge: .bottom) {
      if isBatchSelecting {
        MobileBatchActionBar(
          selectedCount: batchSelectedMemoryKeys.count,
          countText: String(
            format: String(
              localized: "memory.batch.selected_count", defaultValue: "%lld selected",
              table: "Localizable", bundle: MobileL10n.bundle),
            batchSelectedMemoryKeys.count),
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
      if !isBatchSelecting {
        draftSection
      }
      catalogSection
    }
  }

  private var draftSection: some View {
    Section(memoryDraftSectionTitle) {
      VStack(alignment: .leading, spacing: 5) {
        Text(
          String(
            localized: "memory.field.key", defaultValue: "Key", table: "Localizable",
            bundle: MobileL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        TextField("", text: $store.memoryKeyDraft)
          .autocorrectionDisabled()
          .focused($focusedField, equals: .key)
          .submitLabel(.next)
          .onSubmit { focusedField = .content }
          .accessibilityLabel(
            String(
              localized: "memory.field.key", defaultValue: "Key", table: "Localizable",
              bundle: MobileL10n.bundle)
          )
          .accessibilityIdentifier("mobileMemory.key")
      }
      VStack(alignment: .leading, spacing: 5) {
        Text(
          String(
            localized: "memory.field.content", defaultValue: "Content", table: "Localizable",
            bundle: MobileL10n.bundle)
        )
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        TextField("", text: $store.memoryContentDraft, axis: .vertical)
          .lineLimit(3...8)
          .focused($focusedField, equals: .content)
          .submitLabel(.done)
          .onSubmit { submitMemoryDraft() }
          .accessibilityLabel(
            String(
              localized: "memory.field.content", defaultValue: "Content", table: "Localizable",
              bundle: MobileL10n.bundle)
          )
          .accessibilityIdentifier("mobileMemory.content")
      }
      Button {
        submitMemoryDraft()
      } label: {
        Label(
          store.isSavingMemory
            ? String(
              localized: "memory.saving", defaultValue: "Saving Memory", table: "Localizable",
              bundle: MobileL10n.bundle)
            : String(
              localized: "memory.save", defaultValue: "Save Memory", table: "Localizable",
              bundle: MobileL10n.bundle),
          systemImage: "brain")
      }
      .disabled(!store.canSaveMemoryDraft)
      .accessibilityIdentifier("mobileMemory.save")
      if store.memoryEditingKey != nil {
        Button(
          String(
            localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
            bundle: MobileL10n.bundle), role: .cancel
        ) {
          store.clearMemoryDraft()
        }
        .accessibilityIdentifier("mobileMemory.cancelEdit")
      }
    }
  }

  private var catalogSection: some View {
    Section(
      String(
        localized: "destination.memory", defaultValue: "Memory", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      if store.memory == nil {
        MobileSkeletonRows(count: 4)
      } else if let memory = store.memory, memory.entries.isEmpty {
        // Bounded inline empty-state (matches the rest of the app) — a
        // ContentUnavailableView in a List Section inflates the row height.
        MobileEmptyState(
          icon: "brain",
          tint: .purple,
          title: String(
            localized: "memory.empty.no_entries", defaultValue: "No Memory Entries",
            table: "Localizable", bundle: MobileL10n.bundle)
        )
      } else if memoryEntries.isEmpty {
        ContentUnavailableView.search(text: searchQuery)
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
      NavigationLink {
        MobileStoreMemoryDetailDestination(
          store: store,
          initialEntryID: entry.id,
          edit: presentEditor(for:)
        )
      } label: {
        batchSelectableRow(for: entry)
      }
    }
  }

  private var placeholder: some View {
    ContentUnavailableView {
      Label(
        String(
          localized: "memory.detail.empty.title", defaultValue: "Select Memory",
          table: "Localizable", bundle: MobileL10n.bundle), systemImage: "brain")
    } description: {
      Text(
        String(
          localized: "memory.detail.empty.description",
          defaultValue: "Choose a memory entry to inspect its content.", table: "Localizable",
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

  private var batchSelectionIcon: String {
    isBatchSelecting ? "checkmark.circle" : "checkmark.circle.badge.plus"
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

  private func prepareDraft(from entry: MemoryEntry) {
    store.beginEditingMemory(entry)
  }

  private func presentEditor(for entry: MemoryEntry) {
    prepareDraft(from: entry)
    isPresentingMemoryEditor = true
  }

  private func submitMemoryDraft() {
    Task {
      await store.saveMemoryDraft()
    }
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
    .tint(.blue)
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

  private var memoryDraftSectionTitle: String {
    store.memoryEditingKey == nil
      ? String(
        localized: "memory.section.save", defaultValue: "Save Memory", table: "Localizable",
        bundle: MobileL10n.bundle)
      : String(
        localized: "memory.section.edit", defaultValue: "Edit Memory", table: "Localizable",
        bundle: MobileL10n.bundle)
  }
}
