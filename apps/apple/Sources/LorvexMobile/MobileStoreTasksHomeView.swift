import LorvexCore
import SwiftUI

/// The Tasks tab home: a grid of smart collections over the user's lists.
/// Drilling into any of them pushes the scoped task list
/// (``MobileStoreTasksView``). The grid's four cards stand in one row where
/// four fit (a phone on its side, an iPad) and in two rows of two where they
/// do not, never three over one; at accessibility text sizes they stack in
/// one column, where a half-width card would break its name mid-word. A store
/// with no task in any status has nothing for the grid to count, so an
/// invitation to capture the first task stands in its place.
@MainActor
public struct MobileStoreTasksHomeView: View {
  @Bindable var store: MobileStore
  @State private var searchQuery = ""
  @State private var searchResults = MobileTaskWorkspacePage.empty
  @State private var isSearching = false
  /// Counts for the smart-collection cards and the Completed / Cancelled rows,
  /// keyed by the scope's description.
  @State private var smartCounts: [String: Int] = [:]
  /// Whether the store holds any task, or nil until the counts load (the grid
  /// shows meanwhile, so a store with tasks never shifts its layout).
  @State private var holdsTasks: Bool?
  @State private var isShowingCreateList = false
  @State private var editingList: LorvexList?
  /// The grid's width, which decides how many cards share a row.
  @State private var gridWidth: CGFloat = 0
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(store: MobileStore) {
    self.store = store
  }

  private var hasQuery: Bool {
    !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public var body: some View {
    Group {
      if hasQuery {
        searchResultsList
      } else {
        overview
      }
    }
    .navigationTitle(MobileDestination.tasks.title)
    .searchable(text: $searchQuery, prompt: String(localized: "tasks.search.prompt", defaultValue: "Search tasks", table: "Localizable", bundle: MobileL10n.bundle))
    #if DEBUG
      .onAppear {
        if let query = MobileSearchDebugState.takeInitialQuery(for: .tasks) {
          searchQuery = query
        }
      }
    #endif
    // No toolbar ＋: the tab bar's round ＋ already raises capture on every tab,
    // and a second one in the navigation bar was the same action twice.
    // Scopes ride MobileRoute (`.tasksScope`) so they push onto the same typed
    // `tasksRoutePath` as task-detail routes; both resolve through the one
    // MobileRoute destination below.
    .navigationDestination(for: MobileRoute.self) { route in
      MobileStoreRouteView(route: route, store: store)
    }
    .refreshable {
      await store.refresh()
      await reloadSmartCounts()
    }
    .task(id: store.taskWorkspaceRevision) {
      if store.lists == nil {
        await store.refresh()
      }
      await reloadSmartCounts()
    }
    .task(id: "\(searchQuery)|\(store.taskWorkspaceRevision)") {
      guard hasQuery else {
        searchResults = .empty
        isSearching = false
        return
      }
      isSearching = true
      guard await LorvexSearchDebounce.shouldSearch(searchQuery) else { return }
      let results = await store.taskWorkspacePage(scope: .all, query: searchQuery)
      // A newer query or revision cancels this search without awaiting it; its
      // late reply must not replace the newer results.
      guard !Task.isCancelled else { return }
      searchResults = results
      isSearching = false
    }
    .sheet(isPresented: $isShowingCreateList) {
      MobileStoreCreateListSheet(store: store, isPresented: $isShowingCreateList)
    }
    .sheet(item: $editingList) { list in
      MobileStoreEditListSheet(
        list: list,
        store: store,
        isPresented: Binding(get: { editingList != nil }, set: { if !$0 { editingList = nil } })
      )
    }
    .accessibilityIdentifier("mobileTasksHome.root")
  }

  // MARK: - Overview

  private var overview: some View {
    List {
      Section {
        if holdsTasks == false {
          firstTaskInvitation
        } else {
          // No side insets: row insets count from the section's edge, so the
          // cards line up with the list groups below rather than sitting
          // inside them.
          smartGrid
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
      }

      Section {
        if store.lists == nil {
          MobileSkeletonRows(count: 4)
        } else if userLists.isEmpty {
          // Text only: the header ＋ already owns "new list", so the row points
          // at it instead of repeating the action.
          MobileEmptyState(
            icon: "folder",
            title: String(localized: "lists.empty.no_lists", defaultValue: "No Lists", table: "Localizable", bundle: MobileL10n.bundle),
            message: String(localized: "tasks.lists.empty.message", defaultValue: "Tap ＋ to group related tasks into a list — or ask your assistant to.", table: "Localizable", bundle: MobileL10n.bundle))
        } else {
          ForEach(userLists) { list in
            NavigationLink(value: MobileRoute.tasksScope(.list(list.id))) {
              MobileListCatalogRow(list: list)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
              Button {
                store.prepareListDraft(for: list)
                editingList = list
              } label: {
                Label(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "pencil")
              }
              .tint(.accentColor)
            }
            // The core never deletes the Inbox, and refuses a list that still
            // holds tasks, so the Inbox has no delete and a non-empty list's
            // stays disabled.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              if !list.isInbox {
                Button(role: .destructive) {
                  Task { await store.deleteList(list) }
                } label: {
                  Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
                }
                .disabled(list.totalCount != 0 || store.isDeletingList)
              }
            }
            .accessibilityIdentifier("mobileTasks.list.\(list.id)")
          }
        }

        // New List closes the user's lists, where a new one will appear.
        Button {
          isShowingCreateList = true
        } label: {
          Label(String(localized: "lists.new", defaultValue: "New List", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "plus.circle.fill")
        }
        .accessibilityIdentifier("mobileTasks.newList")
      } header: {
        // At the cards' edge in the page-label face, as Today's headings are,
        // so the title, search field, grid, and heading share one edge.
        Text(String(localized: "destination.lists", defaultValue: "Lists", table: "Localizable", bundle: MobileL10n.bundle))
          .font(LorvexDesign.Typography.pageLabel)
          .textCase(nil)
          .listRowInsets(.horizontal, 0)
      }

      // The finished and cancelled tasks are history across every list, not
      // lists of their own, so they sit in a card apart from the lists.
      Section {
        // The two history rows carry the same tile and count as the list
        // rows, so both cards share one icon column and separator inset and
        // every destination states its size.
        NavigationLink(value: MobileRoute.tasksScope(.completed)) {
          MobileNavigationRow(
            title: String(localized: "tasks.scope.completed", defaultValue: "Completed", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "checkmark",
            tint: LorvexDesign.Palette.done,
            count: smartCounts[String(describing: MobileTasksScope.completed)])
        }
        .accessibilityIdentifier("mobileTasks.completed")

        NavigationLink(value: MobileRoute.tasksScope(.cancelled)) {
          MobileNavigationRow(
            title: String(localized: "tasks.scope.cancelled", defaultValue: "Cancelled", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "xmark",
            tint: LorvexDesign.Palette.cancelled,
            count: smartCounts[String(describing: MobileTasksScope.cancelled)])
        }
        .accessibilityIdentifier("mobileTasks.cancelled")
      }

      // Habits and Memory have no place in the tab bar, so they open from here.
      Section {
        NavigationLink(value: MobileRoute.workspace(.habits)) {
          MobileNavigationRow(
            title: String(
              localized: "tasksHome.habits", defaultValue: "Habits", table: "Localizable",
              bundle: MobileL10n.bundle),
            systemImage: MobileDestination.habits.systemImage,
            tint: MobileDestination.habits.tileTint
          )
        }
        .accessibilityIdentifier("mobileTasks.habits")
        NavigationLink(value: MobileRoute.workspace(.memory)) {
          MobileNavigationRow(
            title: String(
              localized: "tasksHome.memory", defaultValue: "Memory", table: "Localizable",
              bundle: MobileL10n.bundle),
            systemImage: MobileDestination.memory.systemImage,
            tint: MobileDestination.memory.tileTint
          )
        }
        .accessibilityIdentifier("mobileTasks.memory")
      }
    }
  }

  /// The grid's columns: as many as ``MobileStoreTasksHomeView/smartGridColumnCount(width:itemCount:)``
  /// fits, or one at accessibility text sizes, where a half-width card has no
  /// room for "Scheduled" and breaks it mid-word (Reminders stacks its smart
  /// lists the same way).
  private var smartGridColumns: [GridItem] {
    let count =
      dynamicTypeSize.isAccessibilitySize
      ? 1
      : Self.smartGridColumnCount(width: gridWidth, itemCount: MobileTaskSmartCollection.grid.count)
    return Array(repeating: GridItem(.flexible(), spacing: LorvexDesign.Spacing.m), count: count)
  }

  /// The narrowest a card can be and still hold its count beside its tile
  /// and its name on one line ("Запланированные", the longest name, at the
  /// default text size).
  nonisolated static let smartGridMinimumCardWidth: CGFloat = 150

  /// How many cards share a row in `width` points: every card in one row
  /// when they all fit at ``smartGridMinimumCardWidth``, otherwise rows filled
  /// as evenly as ``LorvexBalancedGrid`` fills them, so four cards make one
  /// row of four or two rows of two and never three over one. Two before the
  /// width is known, the phone's layout.
  nonisolated static func smartGridColumnCount(width: CGFloat, itemCount: Int) -> Int {
    guard width > 0 else { return 2 }
    let spacing = LorvexDesign.Spacing.m
    let capacity = max(1, Int(((width + spacing) / (smartGridMinimumCardWidth + spacing)).rounded(.down)))
    return LorvexBalancedGrid.columnCount(itemCount: itemCount, capacity: capacity)
  }

  private var smartGrid: some View {
    LazyVGrid(columns: smartGridColumns, spacing: LorvexDesign.Spacing.m) {
      ForEach(MobileTaskSmartCollection.grid) { collection in
        // A Button (pushing the route programmatically) rather than a
        // NavigationLink, so the grid cards don't carry List disclosure chevrons.
        Button {
          store.tasksRoutePath.append(.tasksScope(collection.scope))
        } label: {
          MobileTaskCollectionCard(
            collection: collection,
            count: smartCounts[String(describing: collection.scope)]
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mobileTasks.collection.\(collection.id)")
      }
    }
    // The column count follows the width but never changes it, so measuring
    // the grid itself cannot feed back into its own layout.
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
  }

  /// Text only, like every empty state here: the tab bar's ＋ already owns
  /// capture, so the row points at it instead of repeating the action.
  private var firstTaskInvitation: some View {
    MobileEmptyState(
      icon: MobileDestination.tasks.systemImage,
      title: String(localized: "tasks.home.empty.title", defaultValue: "No Tasks Yet", table: "Localizable", bundle: MobileL10n.bundle),
      message: String(localized: "tasks.home.empty.message", defaultValue: "Tap ＋ to capture your first task — or ask your assistant to add some.", table: "Localizable", bundle: MobileL10n.bundle))
    .accessibilityIdentifier("mobileTasks.firstTask")
  }

  // MARK: - Search results

  private var searchResultsList: some View {
    List {
      if isSearching && searchResults.tasks.isEmpty {
        MobileSkeletonRows(count: 5)
      } else if searchResults.tasks.isEmpty {
        MobileEmptyState.search(text: searchQuery)
      } else {
        ForEach(searchResults.tasks) { task in
          MobileActionTaskRow(
            task: task,
            isBlocked: searchResults.blockedTaskIDs.contains(task.id),
            isMutating: store.taskIsMutating(task.id),
            actions: store.rowActions(for: task.id)
          )
        }
      }
    }
  }

  // MARK: - Data

  private var userLists: [LorvexList] {
    store.lists?.lists ?? []
  }

  /// Loads every count the overview shows. The grid's scopes need a wide page
  /// because two of them (Scheduled, Priority) narrow in memory, so their total
  /// is the size of the filtered page. The history scopes do not narrow, so
  /// their total is the query's own and one row is enough to read it — which
  /// matters most for Completed, the one scope that grows without bound.
  /// Only when every count is zero does it ask whether the store holds any
  /// task at all, since a task the counts leave out still makes the grid
  /// worth showing.
  private func reloadSmartCounts() async {
    for collection in MobileTaskSmartCollection.grid {
      let page = await store.taskWorkspacePage(scope: collection.scope, query: "", limit: 200)
      smartCounts[String(describing: collection.scope)] = page.totalMatching
    }
    for scope in [MobileTasksScope.completed, .cancelled] {
      let page = await store.taskWorkspacePage(scope: scope, query: "", limit: 1)
      smartCounts[String(describing: scope)] = page.totalMatching
    }
    let holds = smartCounts.values.contains { $0 > 0 } ? true : await store.holdsAnyTask()
    if holds != holdsTasks {
      withAnimation(.snappy(duration: 0.25)) { holdsTasks = holds }
    }
  }
}

/// A smart-collection card: the collection's tinted icon tile, its open count,
/// and its name. The tile is the same ``MobileIconTile`` the list rows below
/// the grid lead with, so the four collections and the lists read as one
/// catalog in one vocabulary rather than a bright strip of badges over a
/// quieter list; the count stays the card's largest element because it is the
/// one fact the card exists to show.
struct MobileTaskCollectionCard: View {
  let collection: MobileTaskSmartCollection
  let count: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      HStack(alignment: .top) {
        MobileIconTile(symbol: collection.systemImage, tint: collection.tint, size: 30)
        Spacer()
        Group {
          if let count {
            Text(count, format: .number)
          } else {
            Text(verbatim: "—")
          }
        }
        .font(.title2.weight(.semibold).monospacedDigit())
        .foregroundStyle(.primary)
        .contentTransition(.numericText())
        .accessibilityHidden(true)
      }
      Text(collection.title)
        .font(LorvexDesign.Typography.secondaryText.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      count.map { "\(collection.title), \($0.formatted())" } ?? collection.title)
  }
}
