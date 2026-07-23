import LorvexCore
import SwiftUI

/// Full-screen Lists workspace for iPhone/iPad. Shows all user lists and
/// provides navigation to each list's detail view plus a create affordance.
@MainActor
public struct MobileStoreListsView: View {
  @Bindable var store: MobileStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var isShowingCreateList = false
  @State private var editingList: LorvexList?
  @State private var searchQuery = ""
  @State private var isBatchSelecting = false
  @State private var batchSelectedListIDs = Set<LorvexList.ID>()

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
    .navigationTitle(MobileDestination.lists.title)
    .navigationDestination(for: MobileRoute.self) { route in
      MobileStoreRouteView(route: route, store: store)
    }
    .navigationDestination(
      isPresented: Binding(
        get: { store.pendingListRoute != nil },
        set: { if !$0 { store.pendingListRoute = nil } }
      )
    ) {
      if let route = store.pendingListRoute {
        MobileStoreRouteView(route: route, store: store)
      }
    }
    .toolbar {
      Button {
        toggleBatchSelection()
      } label: {
        Label(batchSelectionTitle, systemImage: batchSelectionIcon)
      }
      .disabled(store.lists == nil || displayedLists.isEmpty)
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileLists.batch.toggle")

      Button {
        isShowingCreateList = true
      } label: {
        Label(
          String(
            localized: "lists.new", defaultValue: "New List", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus")
      }
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileLists.toolbarCreate")
    }
    .task {
      if store.lists == nil {
        await store.refresh()
      }
    }
    .task(id: listIDs) {
      if let selectedListID = store.selectedListID,
        !displayedLists.contains(where: { $0.id == selectedListID })
      {
        store.selectList(nil)
      }
      pruneBatchSelection()
    }
    .refreshable {
      await store.refreshResettingCloudSyncPacing()
    }
    .searchable(
      text: $searchQuery,
      prompt: String(
        localized: "lists.search.prompt", defaultValue: "Search lists", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .sheet(isPresented: $isShowingCreateList) {
      MobileStoreCreateListSheet(store: store, isPresented: $isShowingCreateList)
        .lorvexSpatialBackground()
    }
    .sheet(item: $editingList) { list in
      MobileStoreEditListSheet(
        list: list,
        store: store,
        isPresented: Binding(
          get: { editingList != nil },
          set: { if !$0 { editingList = nil } }
        )
      )
      .lorvexSpatialBackground()
    }
    .safeAreaInset(edge: .bottom) {
      if isBatchSelecting {
        MobileBatchActionBar(
          selectedCount: batchSelectedListIDs.count,
          countText: String(
            format: String(
              localized: "lists.batch.selected_count", defaultValue: "%lld selected",
              table: "Localizable", bundle: MobileL10n.bundle),
            batchSelectedListIDs.count),
          deleteLabel: String(
            localized: "lists.batch.delete_empty", defaultValue: "Delete Empty",
            table: "Localizable", bundle: MobileL10n.bundle),
          canDelete: canDeleteSelectedLists,
          isBusy: store.isDeletingList,
          accessibilityID: "mobileLists.batch.bar",
          clear: { batchSelectedListIDs.removeAll() },
          delete: { Task { await deleteSelectedLists() } }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .accessibilityIdentifier("mobileLists.root")
  }

  @ViewBuilder
  private var compactBody: some View {
    if isBatchSelecting {
      regularList
    } else {
      List {
        Section(
          String(
            localized: "destination.lists", defaultValue: "Lists", table: "Localizable",
            bundle: MobileL10n.bundle)
        ) {
          if store.lists == nil {
            MobileSkeletonRows(count: 4)
          } else if allLists.isEmpty {
            ContentUnavailableView(
              String(
                localized: "lists.empty.no_lists", defaultValue: "No Lists", table: "Localizable",
                bundle: MobileL10n.bundle), systemImage: "folder")
          } else if displayedLists.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
          } else {
            ForEach(displayedLists) { list in
              MobileListCatalogRow(list: list)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                  listEditAction(list)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                  listDeleteAction(list)
                }
                .contextMenu {
                  listEditAction(list)
                  listDeleteAction(list)
                }
                .dropDestination(for: LorvexTaskRef.self) { refs, _ in
                  move(refs, to: list)
                }
                .background {
                  NavigationLink(value: MobileRoute.list(list.id)) {
                    EmptyView()
                  }
                  .opacity(0)
                }
            }
          }
          // No inline "New List" row — the toolbar ＋ is the single add affordance.
        }
      }
    }
  }

  private var regularBody: some View {
    MobileAdaptiveListDetail(selection: listSelection) {
      regularList
    } detail: { id in
      MobileStoreListDetailView(listID: id, store: store)
    } placeholder: {
      ContentUnavailableView {
        Label(
          String(
            localized: "lists.detail.empty.title", defaultValue: "Select a List",
            table: "Localizable", bundle: MobileL10n.bundle), systemImage: "folder")
      } description: {
        Text(
          String(
            localized: "lists.detail.empty.description",
            defaultValue: "Choose a list to review its tasks and progress.", table: "Localizable",
            bundle: MobileL10n.bundle))
      }
    }
  }

  private var regularList: some View {
    List(selection: listSelection) {
      Section(
        String(
          localized: "destination.lists", defaultValue: "Lists", table: "Localizable",
          bundle: MobileL10n.bundle)
      ) {
        if store.lists == nil {
          MobileSkeletonRows(count: 4)
        } else if allLists.isEmpty {
          ContentUnavailableView(
            String(
              localized: "lists.empty.no_lists", defaultValue: "No Lists", table: "Localizable",
              bundle: MobileL10n.bundle),
            systemImage: "folder")
        } else if displayedLists.isEmpty {
          ContentUnavailableView.search(text: searchQuery)
        } else {
          ForEach(displayedLists) { list in
            Button {
              if isBatchSelecting {
                toggleBatchSelection(for: list.id)
              } else {
                store.selectList(list.id)
              }
            } label: {
              batchSelectableRow(for: list)
            }
            .buttonStyle(.plain)
            .lorvexRowHoverEffect()
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
              if !isBatchSelecting {
                listEditAction(list)
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              if !isBatchSelecting {
                listDeleteAction(list)
              }
            }
            .contextMenu {
              if !isBatchSelecting {
                listEditAction(list)
                listDeleteAction(list)
              }
            }
            .dropDestination(for: LorvexTaskRef.self) { refs, _ in
              move(refs, to: list)
            }
            .tag(list.id)
          }
        }
        // No inline "New List" row — the toolbar ＋ is the single add affordance.
      }
    }
  }

  private var listSelection: Binding<LorvexList.ID?> {
    Binding(
      get: { store.selectedListID },
      set: { store.selectList($0) }
    )
  }

  private var allLists: [LorvexList] {
    store.lists?.lists ?? []
  }

  private var displayedLists: [LorvexList] {
    LorvexCatalogSearch.lists(allLists, query: searchQuery)
  }

  private var listIDs: [LorvexList.ID] {
    displayedLists.map(\.id)
  }

  private var selectedLists: [LorvexList] {
    displayedLists.filter { batchSelectedListIDs.contains($0.id) }
  }

  private var canDeleteSelectedLists: Bool {
    !selectedLists.isEmpty && selectedLists.allSatisfy { $0.totalCount == 0 }
  }

  private var batchSelectionTitle: String {
    if isBatchSelecting {
      String(
        localized: "lists.batch.deselect", defaultValue: "Done", table: "Localizable",
        bundle: MobileL10n.bundle)
    } else {
      String(
        localized: "lists.batch.select", defaultValue: "Select", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  private var batchSelectionIcon: String {
    isBatchSelecting ? "checkmark.circle" : "checkmark.circle.badge.plus"
  }

  private func batchSelectableRow(for list: LorvexList) -> some View {
    MobileBatchSelectableRow(
      isBatchSelecting: isBatchSelecting,
      isSelected: batchSelectedListIDs.contains(list.id),
      selectionLabel: String(
        localized: "lists.batch.select_list", defaultValue: "Select list", table: "Localizable",
        bundle: MobileL10n.bundle)
    ) {
      MobileListCatalogRow(list: list, showsChevron: false)
    }
  }

  private func toggleBatchSelection() {
    withAnimation(.snappy) {
      isBatchSelecting.toggle()
      if !isBatchSelecting {
        batchSelectedListIDs.removeAll()
      }
    }
  }

  private func toggleBatchSelection(for id: LorvexList.ID) {
    if batchSelectedListIDs.contains(id) {
      batchSelectedListIDs.remove(id)
    } else {
      batchSelectedListIDs.insert(id)
    }
  }

  private func pruneBatchSelection() {
    let validIDs = Set(listIDs)
    batchSelectedListIDs.formIntersection(validIDs)
    if displayedLists.isEmpty {
      withAnimation(.snappy) {
        isBatchSelecting = false
      }
    }
  }

  private func deleteSelectedLists() async {
    let listsToDelete = selectedLists.filter { $0.totalCount == 0 }
    guard await store.deleteLists(listsToDelete) else { return }
    batchSelectedListIDs.removeAll()
    withAnimation(.snappy) {
      isBatchSelecting = false
    }
  }

  private func move(_ refs: [LorvexTaskRef], to list: LorvexList) -> Bool {
    guard !refs.isEmpty else { return false }
    let listID = list.id
    for ref in refs {
      Task { await store.moveTask(ref.id, toListID: listID) }
    }
    return true
  }

  private func listEditAction(_ list: LorvexList) -> some View {
    Button {
      store.prepareListDraft(for: list)
      editingList = list
    } label: {
      Label(
        String(
          localized: "common.edit", defaultValue: "Edit", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "pencil")
    }
    .tint(.accentColor)
    .disabled(store.isUpdatingList || store.isDeletingList)
  }

  private func listDeleteAction(_ list: LorvexList) -> some View {
    Button(role: .destructive) {
      Task { await store.deleteList(list) }
    } label: {
      Label(
        String(
          localized: "common.delete", defaultValue: "Delete", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "trash")
    }
    .disabled(list.totalCount != 0 || store.isDeletingList || store.isUpdatingList)
  }
}
