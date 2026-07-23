import LorvexCore
import SwiftUI

struct TasksView: View {
  static let reviewQueuePreviewLimit = 10

  @Bindable var store: AppStore
  /// View-layer priority filter. Hides non-matching rows within each status
  /// section; does NOT change the canonical task sort order (the core's
  /// `priority_effective ASC, due ASC, id ASC` is preserved).
  @State var priorityFilter: LorvexTask.Priority?
  /// The priority filter parked while in table mode (which has no filter
  /// equivalent), restored when the user returns to list mode.
  @State private var parkedPriorityFilter: LorvexTask.Priority?
  /// When `true`, shows the flat sortable Table instead of the sectioned List.
  /// Persisted so the user's preference survives navigation.
  @AppStorage("tasks.workspace.isTableMode") var isTableMode = false
  /// Completed/cancelled tasks are history, not the default review surface.
  /// Keep the user's choice durable because expanding history is often a
  /// deliberate audit workflow.
  @AppStorage("tasks.workspace.showHistory") var showHistory = false
  /// Deferred/someday work is real context, but it should not dominate the
  /// default review path. Keep it folded until the user intentionally audits it.
  @AppStorage("tasks.workspace.showLater") var showLater = false
  /// The default Tasks surface is a review queue, not an infinite audit sheet.
  /// Keep overflow open tasks folded so the first screen stays actionable.
  @AppStorage("tasks.workspace.showOpenBacklog") var showOpenBacklog = false
  @State var tableSortOrder: [KeyPathComparator<LorvexTask>] = [
    KeyPathComparator(\.priority),
    KeyPathComparator(\.dueDate, comparator: OptionalDateComparator()),
    // Canonical `id ASC` tiebreaker so the default order is fully determined
    // (priority + due date alone leave equal rows in arbitrary order).
    KeyPathComparator(\.id),
  ]

  private func quickAddPlaceholder(for listID: LorvexList.ID) -> String {
    let name = store.lists?.lists.first { $0.id == listID }?.name ?? listID
    return String(
      format: String(
        localized: "list_detail.quick_add.placeholder",
        defaultValue: "Add a task to “%@”",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      name
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      TasksWorkspaceHeader(
        store: store,
        title: headerTitle,
        subtitle: headerSubtitle,
        scope: headerScope,
        summary: headerSummary,
        metrics: headerMetrics,
        isTableMode: $isTableMode,
        priorityFilter: $priorityFilter
      )

      Divider()

      Group {
        if isInitialTaskWorkspaceLoad {
          WorkspaceReviewList {
            TasksInitialLoadingState()
          }
        } else if isTableMode {
          TasksTableWorkspaceView(
            store: store,
            tasks: tableVisibleTaskPool,
            sortOrder: $tableSortOrder,
            selection: taskSelection
          )
        } else {
          WorkspaceReviewList(taskNavigation: store.arrowKeyTaskNavigation(on: .taskWorkspace)) {
            // The Tasks surface always leads with an inline quick-add so ⌘N and
            // the empty-state capture button always have a field to focus. With
            // an active list scope this surface IS the list (the sidebar routes
            // list clicks here), so typed tasks land in the scoped list; with no
            // scope they land in the default/inbox list. Either way capture stays
            // in place so consecutive adds flow.
            if let scopedListID = store.taskWorkspaceListScopeID {
              QuickAddRow(
                placeholder: quickAddPlaceholder(for: scopedListID),
                isCreating: store.isCreating,
                focusToken: store.quickAddFocusToken
              ) { title in
                await store.createTaskInList(title: title, listID: scopedListID)
              }
              .padding(.horizontal, LorvexDesign.Spacing.m)
              .padding(.top, LorvexDesign.Spacing.s)
            } else {
              QuickAddRow(
                placeholder: String(
                  localized: "tasks.quick_add.placeholder", defaultValue: "Add a task",
                  table: "Localizable",
                  bundle: LorvexL10n.bundle),
                isCreating: store.isCreating,
                focusToken: store.quickAddFocusToken
              ) { title in
                await store.createTaskInInbox(title: title)
              }
              .padding(.horizontal, LorvexDesign.Spacing.m)
              .padding(.top, LorvexDesign.Spacing.s)
            }
            TaskStatusSection(
              title: String(localized: "tasks.section.open", defaultValue: "Next Up", table: "Localizable", bundle: LorvexL10n.bundle),
              status: .open,
              tasks: visibleReviewQueueTasks,
              store: store,
              systemImage: "list.bullet",
              tint: .secondary,
              topSpacing: LorvexDesign.Spacing.s,
              showsLoadMore: !usesReviewQueuePreview)
            if usesReviewQueuePreview {
              TaskOpenBacklogDisclosure(
                isExpanded: $showOpenBacklog,
                tasks: visibleOpenBacklogTasks,
                store: store
              )
            }
            TaskLaterDisclosure(
              isExpanded: $showLater,
              deferredTasks: visibleDeferredTasks,
              scheduledTasks: visibleScheduledTasks,
              somedayTasks: visibleSomedayTasks,
              store: store
            )
            TaskHistoryDisclosure(
              isExpanded: $showHistory,
              completedTasks: visibleCompletedTasks,
              cancelledTasks: visibleCancelledTasks,
              store: store
            )
          }
          .cancelSelectedTaskOnDelete(store, on: .taskWorkspace)
        }
      }
      .overlay {
        if allSectionsEmpty, let tasksEmptyState {
          LorvexEmptyStatePanel(model: tasksEmptyState)
        }
      }
    }
    .task(id: store.taskWorkspaceLoadSignature) {
      // Debounce non-empty queries so a keystroke doesn't fire a five-query
      // workspace load each time. SwiftUI cancels the prior task on every
      // searchText change, and `loadTaskWorkspace` discards results for a
      // superseded query, so stale results can't overwrite the current view.
      // The empty/initial load runs immediately (no debounce).
      if !store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
      }
      await store.loadTaskWorkspace()
    }
    .onChange(of: isTableMode) { _, tableMode in
      if tableMode {
        parkedPriorityFilter = priorityFilter
        priorityFilter = nil
      } else {
        priorityFilter = parkedPriorityFilter
        parkedPriorityFilter = nil
      }
    }
    .onAppear {
      store.setTaskWorkspaceVisibleOrderedTaskIDs(visibleOrderedTaskIDs)
    }
    .onChange(of: visibleOrderedTaskIDs) { _, ids in
      store.setTaskWorkspaceVisibleOrderedTaskIDs(ids)
    }
    .navigationTitle(String(localized: "sidebar.item.tasks", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle))
    .lorvexOpenDestinationActivity(selection: .tasks, isActive: store.selection == .tasks)
  }

}
