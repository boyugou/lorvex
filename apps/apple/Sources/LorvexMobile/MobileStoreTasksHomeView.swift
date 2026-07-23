import LorvexCore
import SwiftUI

/// The Tasks tab home: a 2×2 grid of smart collections over a "My Lists"
/// section. Drilling into any of them pushes the scoped task list
/// (``MobileStoreTasksView``). Lists are first-class here now, instead of a
/// separate "More" destination.
@MainActor
public struct MobileStoreTasksHomeView: View {
  @Bindable var store: MobileStore
  @State private var searchQuery = ""
  @State private var searchResults = MobileTaskWorkspacePage.empty
  @State private var isSearching = false
  /// Counts for the smart-collection cards, keyed by the scope's description.
  @State private var smartCounts: [String: Int] = [:]
  @State private var isShowingCreateList = false
  @State private var editingList: LorvexList?

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
    .toolbar {
      Button {
        store.isPresentingCapture = true
      } label: {
        Label(String(localized: "capture.sheet.title", defaultValue: "Capture", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "plus")
      }
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("mobileTasks.new")
    }
    // Scopes ride MobileRoute (`.tasksScope`) so they push onto the same typed
    // `tasksRoutePath` as task-detail routes; both resolve through the one
    // MobileRoute destination below.
    .navigationDestination(for: MobileRoute.self) { route in
      MobileStoreRouteView(route: route, store: store)
    }
    .refreshable {
      await store.refreshResettingCloudSyncPacing()
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
        return
      }
      isSearching = true
      defer { isSearching = false }
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      searchResults = await store.taskWorkspacePage(scope: .all, query: searchQuery)
    }
    .sheet(isPresented: $isShowingCreateList) {
      MobileStoreCreateListSheet(store: store, isPresented: $isShowingCreateList)
        .lorvexSpatialBackground()
    }
    .sheet(item: $editingList) { list in
      MobileStoreEditListSheet(
        list: list,
        store: store,
        isPresented: Binding(get: { editingList != nil }, set: { if !$0 { editingList = nil } })
      )
      .lorvexSpatialBackground()
    }
    .accessibilityIdentifier("mobileTasksHome.root")
  }

  // MARK: - Overview

  private var overview: some View {
    List {
      Section {
        smartGrid
          .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }

      Section {
        if store.lists == nil {
          MobileSkeletonRows(count: 4)
        } else if userLists.isEmpty {
          ContentUnavailableView {
            Label(String(localized: "lists.empty.no_lists", defaultValue: "No Lists", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "folder")
          } description: {
            Text(String(localized: "tasks.lists.empty.message", defaultValue: "Group related tasks into a list — or ask your AI assistant to.", table: "Localizable", bundle: MobileL10n.bundle))
          }
        } else {
          ForEach(userLists) { list in
            NavigationLink(value: MobileRoute.tasksScope(.list(list.id))) {
              MobileListCatalogRow(list: list, showsChevron: false, showsProgress: false)
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                Task { await store.deleteList(list) }
              } label: {
                Label(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "trash")
              }
              .disabled(list.totalCount != 0 || store.isDeletingList)
            }
            .accessibilityIdentifier("mobileTasks.list.\(list.id)")
          }
        }

        NavigationLink(value: MobileRoute.tasksScope(.completed)) {
          Label {
            Text(String(localized: "tasks.scope.completed", defaultValue: "Completed", table: "Localizable", bundle: MobileL10n.bundle))
          } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(LorvexDesign.Palette.done)
          }
        }
        .accessibilityIdentifier("mobileTasks.completed")

        NavigationLink(value: MobileRoute.tasksScope(.cancelled)) {
          Label {
            Text(String(localized: "tasks.scope.cancelled", defaultValue: "Cancelled", table: "Localizable", bundle: MobileL10n.bundle))
          } icon: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
        }
        .accessibilityIdentifier("mobileTasks.cancelled")
      } header: {
        HStack {
          Text(String(localized: "destination.lists", defaultValue: "Lists", table: "Localizable", bundle: MobileL10n.bundle))
          Spacer()
          Button {
            isShowingCreateList = true
          } label: {
            Label(String(localized: "lists.new", defaultValue: "New List", table: "Localizable", bundle: MobileL10n.bundle), systemImage: "plus")
              .labelStyle(.iconOnly)
          }
          .accessibilityIdentifier("mobileTasks.newList")
        }
      }
    }
  }

  private var smartGrid: some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: LorvexDesign.Spacing.m),
        GridItem(.flexible()),
      ],
      spacing: LorvexDesign.Spacing.m
    ) {
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
  }

  // MARK: - Search results

  private var searchResultsList: some View {
    List {
      if isSearching && searchResults.tasks.isEmpty {
        MobileSkeletonRows(count: 5)
      } else if searchResults.tasks.isEmpty {
        ContentUnavailableView.search(text: searchQuery)
      } else {
        ForEach(searchResults.tasks) { task in
          MobileActionTaskRow(
            task: task,
            isFocused: store.taskIsFocused(task.id),
            isMutating: store.taskIsMutating(task.id),
            select: { store.selectTask(task.id) },
            toggleFocus: { await store.toggleTaskFocus(task.id) },
            complete: { await store.completeTask(task.id) },
            deferTask: { await store.deferTaskToTomorrow(task.id) }
          )
        }
      }
    }
  }

  // MARK: - Data

  private var userLists: [LorvexList] {
    store.lists?.lists ?? []
  }

  private func reloadSmartCounts() async {
    for collection in MobileTaskSmartCollection.grid {
      let page = await store.taskWorkspacePage(scope: collection.scope, query: "", limit: 200)
      smartCounts[String(describing: collection.scope)] = page.totalMatching
    }
  }
}

/// A smart-collection card: a colored icon, a big count, and a label — the
/// Reminders idiom, rendered in Lorvex's design system.
struct MobileTaskCollectionCard: View {
  let collection: MobileTaskSmartCollection
  let count: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      HStack(alignment: .top) {
        Image(systemName: collection.systemImage)
          .font(.headline)
          .foregroundStyle(.white)
          .frame(width: 30, height: 30)
          .background(collection.tint.gradient, in: Circle())
        Spacer()
        Text(count.map(String.init) ?? "—")
          .font(.title.weight(.semibold).monospacedDigit())
          .foregroundStyle(.primary)
          .contentTransition(.numericText())
          .accessibilityHidden(true)
      }
      Text(collection.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LorvexDesign.Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      count.map { "\(collection.title), \($0)" } ?? collection.title)
  }
}
