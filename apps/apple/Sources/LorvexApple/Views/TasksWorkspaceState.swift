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

  var visibleOverdueOpenTaskCount: Int {
    visibleOpenTasks.filter { $0.isOverdue() }.count
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

    if let selectedListScope {
      let tint = Color(lorvexHex: selectedListScope.color) ?? .accentColor
      let icon = selectedListScope.icon ?? "folder"
      return LorvexEmptyStateModel(
        title: String(localized: "tasks.empty.list_title", defaultValue: "No Tasks in This List", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "tasks.empty.list_description",
          defaultValue: "This list is empty. Tasks you add to it appear here.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: icon,
        tint: tint,
        chips: [
          LorvexEmptyStateChip(
            title: selectedListScope.name,
            systemImage: icon,
            tint: tint
          )
        ],
        action: LorvexEmptyStateAction(
          title: String(localized: "tasks.empty.show_all_tasks", defaultValue: "Show All Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "checklist"
        ) {
          store.setTaskWorkspaceListScope(nil)
        }
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
        tint: .orange,
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
    return LorvexEmptyStateModel(
      title: String(localized: "tasks.empty.no_tasks_title", defaultValue: "No Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
      message: String(
        localized: "tasks.empty.no_tasks_description",
        defaultValue: "Capture a task to start shaping your plan.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "checklist",
      tint: .accentColor,
      chips: [],
      action: LorvexEmptyStateAction(
        title: AppCommand.newTask.title,
        systemImage: AppCommand.newTask.systemImage,
        style: .primary
      ) {
        store.requestQuickAddFocus()
      }
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

  var headerSubtitle: String {
    if isInitialTaskWorkspaceLoad {
      return String(
        localized: "tasks.header.loading_queue",
        defaultValue: "Loading review queue",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }

    if isDefaultTaskReviewHeader {
      return String(
        localized: "tasks.header.review_queue",
        defaultValue: "Every task across all lists — review, triage, batch-edit",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }

    var parts: [String] = []
    if store.hasActiveSearch {
      parts.append(
        String(
          format: String(
            localized: "tasks.header.searching",
            defaultValue: "Searching \"%@\"",
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
    if selectedListScope != nil, parts.isEmpty {
      parts.append(String(
        localized: "tasks.header.list_scope",
        defaultValue: "List scope",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
    }
    if parts.isEmpty {
      if isTableMode {
        parts.append(String(
          localized: "tasks.header.table_audit",
          defaultValue: "Audit table",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
      } else {
        parts.append(String(
          localized: "tasks.header.review_queue",
          defaultValue: "Every task across all lists — review, triage, batch-edit",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
      }
    }
    return parts.joined(separator: " · ")
  }

  var headerTitle: String {
    selectedListScope?.name
      ?? String(localized: "sidebar.item.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  var headerScope: TasksHeaderScope? {
    guard let selectedListScope else { return nil }
    return TasksHeaderScope(
      name: selectedListScope.name,
      icon: selectedListScope.icon,
      tint: Color(lorvexHex: selectedListScope.color) ?? .accentColor
    )
  }

  var headerSummary: String? {
    if isInitialTaskWorkspaceLoad { return nil }

    if isDefaultTaskReviewHeader { return nil }

    if isTableMode {
      return String(
        localized: "tasks.header.summary.table",
        defaultValue: "Audit every loaded task status",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }

    if store.hasActiveSearch || priorityFilter != nil {
      return String(
        localized: "tasks.header.summary.filtered",
        defaultValue: "Filtered review",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }

    if selectedListScope != nil {
      return String(
        localized: "tasks.header.summary.scoped",
        defaultValue: "Scoped review",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }

    return headerCountSummary
  }

  var headerMetrics: [TasksHeaderMetric] {
    guard !isInitialTaskWorkspaceLoad else { return [] }

    if isTableMode {
      return [
        TasksHeaderMetric(
          title: String(localized: "tasks.header.stat.loaded", defaultValue: "Loaded", table: "Localizable", bundle: LorvexL10n.bundle),
          count: visibleTaskPool.count,
          tint: .accentColor
        ),
        TasksHeaderMetric(
          title: String(localized: "tasks.header.stat.open", defaultValue: "Open", table: "Localizable", bundle: LorvexL10n.bundle),
          count: visibleOpenTasks.count,
          tint: .blue
        ),
        TasksHeaderMetric(
          title: String(localized: "tasks.header.stat.history", defaultValue: "History", table: "Localizable", bundle: LorvexL10n.bundle),
          count: visibleHistoryTaskPool.count,
          tint: .secondary
        ),
      ].filter { $0.count > 0 }
    }

    var metrics: [TasksHeaderMetric] = []
    metrics.append(TasksHeaderMetric(
      title: String(localized: "tasks.header.stat.next", defaultValue: "Next", table: "Localizable", bundle: LorvexL10n.bundle),
      count: headerNextCount,
      tint: .accentColor
    ))

    if visibleOverdueOpenTaskCount > 0 {
      metrics.append(TasksHeaderMetric(
        title: String(localized: "tasks.header.stat.overdue", defaultValue: "Overdue", table: "Localizable", bundle: LorvexL10n.bundle),
        count: visibleOverdueOpenTaskCount,
        tint: .orange,
        isAttention: true
      ))
    }

    if showLater && visibleLaterTaskCount > 0 {
      metrics.append(TasksHeaderMetric(
        title: String(localized: "tasks.header.stat.later", defaultValue: "Later", table: "Localizable", bundle: LorvexL10n.bundle),
        count: visibleLaterTaskCount,
        tint: .secondary
      ))
    }

    if showHistory && !visibleHistoryTaskPool.isEmpty {
      metrics.append(TasksHeaderMetric(
        title: String(localized: "tasks.header.stat.history", defaultValue: "History", table: "Localizable", bundle: LorvexL10n.bundle),
        count: visibleHistoryTaskPool.count,
        tint: .secondary
      ))
    }

    return metrics.filter { $0.count > 0 }
  }

  var headerNextCount: Int {
    usesReviewQueuePreview ? visibleReviewQueueTasks.count : visibleCurrentTaskPool.count
  }

  var headerCountSummary: String {
    var parts: [String] = []
    if headerNextCount > 0 {
      parts.append(String(
        format: String(localized: "tasks.header.summary.next_count", defaultValue: "%lld next", table: "Localizable", bundle: LorvexL10n.bundle),
        headerNextCount))
    }
    if showLater && visibleLaterTaskCount > 0 {
      parts.append(String(
        format: String(localized: "tasks.header.summary.later_count", defaultValue: "%lld later", table: "Localizable", bundle: LorvexL10n.bundle),
        visibleLaterTaskCount))
    }
    if showHistory && !visibleHistoryTaskPool.isEmpty {
      parts.append(String(
        format: String(localized: "tasks.header.summary.history_count", defaultValue: "%lld history", table: "Localizable", bundle: LorvexL10n.bundle),
        visibleHistoryTaskPool.count))
    }
    guard !parts.isEmpty else {
      return String(
        localized: "tasks.header.summary.no_matches",
        defaultValue: "No matching tasks",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
    return parts.joined(separator: " · ")
  }

}
