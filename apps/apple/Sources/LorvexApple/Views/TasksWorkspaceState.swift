import LorvexCore
import SwiftUI
extension TasksView {
  func byPriority(_ tasks: [LorvexTask]) -> [LorvexTask] {
    guard let priorityFilter else { return tasks }
    return tasks.filter { $0.priority == priorityFilter }
  }

  var selectedListScope: LorvexList? {
    guard let listID = store.taskWorkspaceListScopeID else { return nil }
    return store.lists?.lists.first { $0.id == listID }
  }

  var visibleOpenTasks: [LorvexTask] {
    byPriority(store.taskWorkspaceOpenTasks)
  }

  var visibleCompletedTasks: [LorvexTask] {
    byPriority(store.taskWorkspaceCompletedTasks)
  }

  var visibleCancelledTasks: [LorvexTask] {
    byPriority(store.taskWorkspaceCancelledTasks)
  }

  var visibleTaskPool: [LorvexTask] {
    visibleOpenTasks
      + visibleDeferredTasks
      + visibleScheduledTasks
      + visibleCompletedTasks
      + visibleCancelledTasks
      + visibleSomedayTasks
  }

  var tableVisibleTaskPool: [LorvexTask] {
    visibleTaskPool.sorted(using: tableSortOrder)
  }

  var isInitialTaskWorkspaceLoad: Bool {
    store.taskWorkspaceIsLoading && !store.taskWorkspaceHasLoaded
  }

  var visibleCurrentTaskPool: [LorvexTask] {
    visibleOpenTasks
  }

  var usesReviewQueuePreview: Bool {
    isDefaultTaskReviewHeader
  }

  var visibleReviewQueueTasks: [LorvexTask] {
    guard usesReviewQueuePreview else { return visibleOpenTasks }
    return Array(visibleOpenTasks.prefix(Self.reviewQueuePreviewLimit))
  }

  var visibleOpenBacklogTasks: [LorvexTask] {
    guard usesReviewQueuePreview else { return [] }
    return Array(visibleOpenTasks.dropFirst(Self.reviewQueuePreviewLimit))
  }

  var visibleHistoryTaskPool: [LorvexTask] {
    visibleCompletedTasks + visibleCancelledTasks
  }

  var allSectionsEmpty: Bool {
    if isInitialTaskWorkspaceLoad { return false }
    if isTableMode { return visibleTaskPool.isEmpty }
    return visibleCurrentTaskPool.isEmpty
      && visibleLaterTaskCount == 0
      && visibleHistoryTaskPool.isEmpty
  }

  var tasksEmptyState: LorvexEmptyStateModel? {
    if store.hasActiveSearch {
      return LorvexEmptyStateModel(
        title: String(localized: "tasks.empty.search_title", defaultValue: "No Search Results", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "tasks.empty.search_description",
          defaultValue: "No tasks match your search. Try different words or clear the search.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "magnifyingglass",
        tint: .secondary,
        action: LorvexEmptyStateAction(
          title: String(localized: "common.clear_search", defaultValue: "Clear Search", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "xmark.circle"
        ) {
          store.searchText = ""
        }
      )
    }

    // The list's name is the page title and the sidebar leaves the list in
    // one click, so the empty panel names neither: it points at the
    // quick-add row above it, where a task for this list is typed.
    if let selectedListScope {
      let tint = Color(lorvexHex: selectedListScope.color) ?? .accentColor
      let icon = selectedListScope.icon ?? "folder"
      return LorvexEmptyStateModel(
        title: String(localized: "tasks.empty.list_title", defaultValue: "No Tasks in This List", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "tasks.empty.list_description",
          defaultValue: "Type a task in the field above to add it to this list.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: icon,
        tint: tint
      )
    }

    if !isTableMode, let priorityFilter {
      return LorvexEmptyStateModel(
        title: String(localized: "tasks.empty.no_matching_title", defaultValue: "No Matching Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "tasks.empty.no_matching_description",
          defaultValue: "No tasks match the selected priority filter.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "line.3.horizontal.decrease.circle",
        tint: LorvexDesign.Palette.neutral,
        chips: [
          LorvexEmptyStateChip(
            title: TaskDisplayText.priority(priorityFilter),
            systemImage: "flag",
            tint: priorityFilter.priorityTint
          )
        ],
        action: LorvexEmptyStateAction(
          title: String(
            localized: "tasks.empty.show_all_priorities",
            defaultValue: "Show All Priorities",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          systemImage: "line.3.horizontal.decrease.circle"
        ) {
          self.priorityFilter = nil
        }
      )
    }

    guard !store.taskWorkspaceIsLoading else { return nil }
    // No capture action: the quick-add row above the empty panel is where a
    // task is typed, and ⌘N focuses it.
    return LorvexEmptyStateModel(
      title: String(localized: "tasks.empty.no_tasks_title", defaultValue: "No Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
      message: String(
        localized: "tasks.empty.no_tasks_description",
        defaultValue: "Type a task in the field above — or ask your assistant to add some.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "checklist",
      tint: .accentColor
    )
  }

  var taskSelection: Binding<Set<LorvexTask.ID>> {
    Binding(
      get: { store.taskWorkspaceSelectedTaskIDs },
      set: { store.setTaskWorkspaceSelection($0) }
    )
  }

  var isDefaultTaskReviewHeader: Bool {
    !isTableMode
      && !store.hasActiveSearch
      && priorityFilter == nil
      && selectedListScope == nil
  }

  /// One line under the title saying what narrows the rows: the active search
  /// and priority filter; otherwise the scoped list's description. All Tasks
  /// itself, and a list without a description, show no line, since the title
  /// already names the rows. The Queue/Audit mode is not named either (the
  /// rows show it), and the first load shows its progress where the rows will
  /// be (`TasksInitialLoadingState`).
  var headerSubtitle: String {
    var parts: [String] = []
    if store.hasActiveSearch {
      parts.append(
        String(
          format: String(
            localized: "tasks.header.searching",
            defaultValue: "Searching “%@”",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          store.searchText
        )
      )
    }
    if let priorityFilter {
      parts.append(TaskDisplayText.priority(priorityFilter))
    }
    if !parts.isEmpty {
      return parts.joined(separator: " · ")
    }
    return selectedListScope?.description.trimmedNilIfEmpty ?? ""
  }

  var headerTitle: String {
    selectedListScope?.displayName
      ?? String(localized: "sidebar.item.tasks", defaultValue: "All Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// The scoped list's own icon — an SF Symbol name or an emoji, "folder" when
  /// it has none — else the Tasks symbol.
  var headerIcon: String {
    guard let selectedListScope else { return SidebarSelection.tasks.systemImage }
    return selectedListScope.icon.trimmedNilIfEmpty ?? "folder"
  }

  /// The scoped list's color, which tints its symbol icon; nil for All Tasks.
  var headerIconTint: Color? {
    selectedListScope.map { Color(lorvexHex: $0.color) ?? .accentColor }
  }
}
