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
  @Environment(\.undoManager) private var undoManager
  /// Each list's first open tasks, previewed on its card.
  @State private var listPreviews: [LorvexList.ID: [LorvexTask]] = [:]

  private enum OverviewMetrics {
    static let rowMaxWidth: CGFloat = 760
  }

  private var listsEmptyState: LorvexEmptyStateModel? {
    if store.lists?.lists.isEmpty == true {
      return LorvexEmptyStateModel(
        title: String(localized: "lists.empty.no_lists_title", defaultValue: "No Lists", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "lists.empty.no_lists_description",
          defaultValue: "Click ＋ to group related tasks into a list — or ask your assistant to.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "folder",
        tint: .accentColor
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
      ListsWorkspaceHeader(subtitle: subtitle)

      Divider()

      listOverview
    }
    .navigationTitle(String(localized: "sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle))
    .toolbar {
      ToolbarSpacer(.flexible)

      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          isShowingCreateList = true
        } label: {
          Label(
            String(localized: "lists.create.a11y", defaultValue: "Create List", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "plus")
        }
        .help(String(localized: "lists.create.help", defaultValue: "Create List", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("lists.create")

        ListsViewOptionsMenu(scope: $listScope)
      }
    }
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
        LazyVStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          ForEach(Array(filteredCatalogLists.enumerated()), id: \.element.id) { index, list in
            ListCatalogRow(
              list: list,
              previewTasks: listPreviews[list.id] ?? [],
              openTask: { store.openTaskInListScope($0, listID: list.id) },
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
            .taskDropTarget(list.id, targeted: $dropTargetedListID) { ids in
              Task { await store.moveTasks(ids: ids, toListID: list.id, undoManager: undoManager) }
            }
            .frame(maxWidth: OverviewMetrics.rowMaxWidth, alignment: .leading)
          }
        }
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.vertical, LorvexDesign.Spacing.s)
      }
    }
    .accessibilityIdentifier("lists.overview")
    .task(id: store.listPreviewKey) { await reloadListPreviews() }
    .overlay {
      if let listsEmptyState {
        LorvexEmptyStatePanel(model: listsEmptyState)
      }
    }
  }

  /// Loads the cards' previews. A load the lists have moved past is cancelled
  /// and throws, so it never overwrites the newer load's previews.
  private func reloadListPreviews() async {
    guard let previews = try? await store.loadListPreviews(ids: store.orderedLists.map(\.id))
    else { return }
    listPreviews = previews
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
    store.openTaskListScope(id)
  }

  /// The line under the Lists title: the scope filter, or no line when the
  /// catalog shows every list. It never counts lists or tasks, since every row
  /// carries its own open and total counts.
  private var subtitle: String {
    listScope.headerCaption ?? ""
  }

  private var filteredCatalogLists: [LorvexList] {
    store.orderedLists.filter(listScope.includes)
  }

}

/// The Lists catalog header: the identity, plus a line naming the scope
/// filter when it narrows the catalog. The create action and the scope menu
/// ride in the window toolbar (`ListsWorkspaceView`).
private struct ListsWorkspaceHeader: View {
  let subtitle: String

  var body: some View {
    WorkspacePlanHeaderChrome {
      WorkspaceHeaderIdentity(
        title: String(localized: "sidebar.item.lists", defaultValue: "Lists", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: subtitle,
        icon: SidebarSelection.lists.systemImage,
        accessibilityIdentifier: "lists.header.identity",
        subtitleAccessibilityIdentifier: "lists.header.summary"
      )
    }
  }
}

private struct ListsViewOptionsMenu: View {
  @Binding var scope: ListsWorkspaceScope

  private var label: String {
    String(localized: "lists.scope.picker", defaultValue: "Filter Lists", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  var body: some View {
    Menu {
      Picker(label, selection: $scope) {
        ForEach(ListsWorkspaceScope.allCases) { scope in
          Label(scope.title, systemImage: scope.systemImage).tag(scope)
        }
      }
      .pickerStyle(.inline)
      .accessibilityIdentifier("lists.scope")
    } label: {
      Label(String(localized: "lists.scope.menu", defaultValue: "View Options", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "slider.horizontal.3")
        .labelStyle(.titleAndIcon)
    }
    .help(label)
    .accessibilityLabel(label)
    .accessibilityIdentifier("lists.viewOptions")
  }
}
