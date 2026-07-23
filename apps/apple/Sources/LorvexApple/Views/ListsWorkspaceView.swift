import LorvexCore
import SwiftUI

struct ListsWorkspaceView: View {
  @Bindable var store: AppStore
  @State private var isShowingCreateList = false
  @State private var editingList: LorvexList?
  @State private var listScope: ListsWorkspaceScope = .all
  /// The catalog row currently under a task drag, highlighted so the drop
  /// target reads clearly — mirrors the sidebar list rows' drop affordance.
  @State private var dropTargetedListID: LorvexList.ID?

  private enum OverviewMetrics {
    static let rowMaxWidth: CGFloat = 760
  }

  private var listsEmptyState: LorvexEmptyStateModel? {
    if store.hasActiveSearch && filteredCatalogLists.isEmpty {
      return LorvexEmptyStateModel(
        title: String(localized: "lists.empty.search_title", defaultValue: "No List Results", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "lists.empty.search_description",
          defaultValue: "No project list matches the current search.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "magnifyingglass",
        tint: .secondary,
        chips: [
          LorvexEmptyStateChip(
            title: store.searchText,
            systemImage: "text.magnifyingglass",
            tint: .accentColor
          )
        ],
        action: LorvexEmptyStateAction(
          title: String(localized: "common.clear_search", defaultValue: "Clear Search", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "xmark.circle"
        ) {
          store.searchText = ""
        }
      )
    }

    if store.lists?.lists.isEmpty == true {
      return LorvexEmptyStateModel(
        title: String(localized: "lists.empty.no_lists_title", defaultValue: "No Lists", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "lists.empty.no_lists_description",
          defaultValue: "Lists will appear here once they're created.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "folder",
        tint: .accentColor,
        chips: [],
        action: LorvexEmptyStateAction(
          title: String(localized: "lists.create", defaultValue: "Create List", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "plus",
          style: .primary
        ) {
          isShowingCreateList = true
        }
      )
    }

    if filteredCatalogLists.isEmpty {
      return LorvexEmptyStateModel(
        title: listScope.emptyTitle,
        message: listScope.emptyDescription,
        systemImage: listScope.systemImage,
        tint: .secondary,
        chips: [
          LorvexEmptyStateChip(
            title: listScope.title,
            systemImage: listScope.systemImage,
            tint: .secondary
          )
        ],
        action: LorvexEmptyStateAction(
          title: String(localized: "lists.empty.show_all", defaultValue: "Show All Lists", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "folder"
        ) {
          listScope = .all
        }
      )
    }

    return nil
  }

  var body: some View {
    VStack(spacing: 0) {
      ListsWorkspaceHeader(
        summary: summary,
        scope: $listScope,
        create: { isShowingCreateList = true }
      )

      Divider()

      listOverview
    }
    .navigationTitle(String(localized: "sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle))
    .sheet(isPresented: $isShowingCreateList) {
      CreateListSheet(
        store: store,
        isPresented: $isShowingCreateList
      )
    }
    .sheet(item: $editingList) { list in
      EditListSheet(
        list: list,
        store: store,
        isPresented: Binding(
          get: { editingList != nil },
          set: { if !$0 { editingList = nil } }
        )
      )
    }
  }

  private var listOverview: some View {
    ScrollView {
      WorkspaceDashboardLane {
        LazyVStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          ForEach(Array(filteredCatalogLists.enumerated()), id: \.element.id) { index, list in
            ListCatalogRow(
              list: list,
              select: {
                openListScope(list.id)
              },
              edit: {
                store.prepareListDraft(for: list)
                editingList = list
              },
              delete: {
                Task { await store.deleteList(list) }
              },
              archive: {
                Task { await store.archiveList(list) }
              },
              canMoveUp: index > 0,
              canMoveDown: index < filteredCatalogLists.count - 1,
              moveUp: { moveCatalogList(list.id, by: -1) },
              moveDown: { moveCatalogList(list.id, by: 1) }
            )
            .background {
              if dropTargetedListID == list.id {
                RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
                  .fill(.tint.opacity(0.16))
              }
            }
            .dropDestination(for: LorvexTaskRef.self) { [store] refs, _ -> Bool in
              let listID: LorvexList.ID = list.id
              for ref in refs {
                Task { await store.moveTask(id: ref.id, toListID: listID) }
              }
              return !refs.isEmpty
            } isTargeted: { targeted in
              if targeted {
                dropTargetedListID = list.id
              } else if dropTargetedListID == list.id {
                dropTargetedListID = nil
              }
            }
            .frame(maxWidth: OverviewMetrics.rowMaxWidth, alignment: .leading)
          }
        }
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.vertical, LorvexDesign.Spacing.s)
      }
    }
    .accessibilityIdentifier("lists.overview")
    .overlay {
      if let listsEmptyState {
        LorvexEmptyStatePanel(model: listsEmptyState)
      }
    }
  }

  private func moveCatalogList(_ listID: LorvexList.ID, by delta: Int) {
    var visibleIDs = filteredCatalogLists.map(\.id)
    guard let index = visibleIDs.firstIndex(of: listID) else { return }
    let target = index + delta
    guard visibleIDs.indices.contains(target) else { return }
    let destination = delta > 0 ? target + 1 : target
    visibleIDs.move(fromOffsets: IndexSet(integer: index), toOffset: destination)
    let merged = AppStore.mergeReorderedVisible(
      visibleIDs,
      intoFullOrder: store.orderedLists.map(\.id)
    )
    Task { await store.reorderLists(merged) }
  }

  private func openListScope(_ id: LorvexList.ID) {
    store.selectedTaskID = nil
    store.setTaskWorkspaceListScope(id)
    store.selection = .tasks
  }

  private var summary: String {
    let count = filteredCatalogLists.count
    let openCount = filteredCatalogLists.reduce(0) { $0 + $1.openCount }
    if store.hasActiveSearch {
      return String(
        localized: "lists.summary.search_count",
        defaultValue: "\(count) lists matching the current search.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    }
    let format: String
    switch (count == 1, openCount == 1) {
    case (true, true):
      format = String(localized: "lists.summary.all.one_list_one_task", defaultValue: "%1$lld list with %2$lld open task.", table: "Localizable", bundle: LorvexL10n.bundle)
    case (true, false):
      format = String(localized: "lists.summary.all.one_list_many_tasks", defaultValue: "%1$lld list with %2$lld open tasks.", table: "Localizable", bundle: LorvexL10n.bundle)
    case (false, true):
      format = String(localized: "lists.summary.all.many_lists_one_task", defaultValue: "%1$lld lists with %2$lld open task.", table: "Localizable", bundle: LorvexL10n.bundle)
    case (false, false):
      format = String(localized: "lists.summary.all.many_lists_many_tasks", defaultValue: "%1$lld lists with %2$lld open tasks.", table: "Localizable", bundle: LorvexL10n.bundle)
    }
    return String(format: format, count, openCount)
  }

  private var filteredCatalogLists: [LorvexList] {
    store.filteredLists.filter(listScope.includes)
  }

}

private struct ListsWorkspaceHeader: View {
  let summary: String
  @Binding var scope: ListsWorkspaceScope
  let create: () -> Void

  var body: some View {
    WorkspacePlanHeaderChrome {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HStack(alignment: .center, spacing: LorvexDesign.Spacing.m) {
          WorkspaceHeaderIdentity(
            title: String(localized: "sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle),
            subtitle: summary,
            systemImage: SidebarSelection.lists.systemImage,
            accessibilityIdentifier: "lists.header.identity",
            subtitleAccessibilityIdentifier: "lists.header.summary"
          )

          Spacer(minLength: LorvexDesign.Spacing.m)

          HStack(spacing: LorvexDesign.Spacing.s) {
            Button(action: create) {
              Image(systemName: "plus")
            }
            .workspaceHeaderActionStyle()
            .help(String(localized: "lists.create.help", defaultValue: "Create List", table: "Localizable", bundle: LorvexL10n.bundle))
            .accessibilityLabel(String(localized: "lists.create.a11y", defaultValue: "Create List", table: "Localizable", bundle: LorvexL10n.bundle))
            .accessibilityIdentifier("lists.create")

            ListsViewOptionsMenu(scope: $scope)
          }
          .fixedSize(horizontal: true, vertical: false)
        }
      }
    }
  }
}

private struct ListsViewOptionsMenu: View {
  @Binding var scope: ListsWorkspaceScope

  private var label: String {
    String(localized: "lists.scope.picker", defaultValue: "List Scope", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  var body: some View {
    Menu {
      Picker(label, selection: $scope) {
        ForEach(ListsWorkspaceScope.allCases) { scope in
          Label(scope.title, systemImage: scope.systemImage).tag(scope)
        }
      }
      .accessibilityIdentifier("lists.scope")
    } label: {
      Label(String(localized: "lists.scope.menu", defaultValue: "Scope", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "slider.horizontal.3")
    }
    .menuStyle(.button)
    .workspaceHeaderLabeledActionStyle()
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier("lists.viewOptions")
  }
}
