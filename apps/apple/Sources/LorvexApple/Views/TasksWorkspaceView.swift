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
    let name = store.lists?.lists.first { $0.id == listID }?.displayName ?? listID
    return AppStore.quickAddPlaceholder(listName: name)
  }

  /// The inline quick-add both view modes lead with, so ⌘N always has a field
  /// to focus. With an active list scope this surface IS the list (the sidebar
  /// routes list clicks here), so typed tasks land in the scoped list; with no
  /// scope they land in the inbox. Capture stays in place so consecutive adds
  /// flow.
  @ViewBuilder
  private var quickAdd: some View {
    Group {
      if let scopedListID = store.taskWorkspaceListScopeID {
        QuickAddRow(
          placeholder: quickAddPlaceholder(for: scopedListID),
          focusToken: store.quickAddFocusToken,
          preview: store.quickAddPreview
        ) { text in
          await store.createInlineTask(text, destination: .list(scopedListID))
        }
      } else {
        QuickAddRow(
          placeholder: String(
            localized: "tasks.quick_add.placeholder", defaultValue: "Add a task",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          focusToken: store.quickAddFocusToken,
          preview: store.quickAddPreview
        ) { text in
          await store.createInlineTask(text, destination: .inbox)
        }
      }
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.top, LorvexDesign.Spacing.s)
  }

  var body: some View {
    VStack(spacing: 0) {
      TasksWorkspaceHeader(
        title: headerTitle,
        subtitle: headerSubtitle,
        icon: headerIcon,
        iconTint: headerIconTint
      )

      Divider()

      Group {
        if isInitialTaskWorkspaceLoad {
          if let taskWorkspaceLoadFailureState {
            LorvexEmptyStatePanel(model: taskWorkspaceLoadFailureState)
          } else {
            WorkspaceReviewList {
              TasksInitialLoadingState()
            }
          }
        } else if isTableMode {
          VStack(spacing: 0) {
            quickAdd
              .padding(.bottom, LorvexDesign.Spacing.s)
            TasksTableWorkspaceView(
              store: store,
              tasks: tableVisibleTaskPool,
              sortOrder: $tableSortOrder,
              selection: taskSelection
            )
          }
        } else {
          WorkspaceReviewList(taskNavigation: store.arrowKeyTaskNavigation(on: .taskWorkspace)) {
            quickAdd
            TaskOpenRows(
              tasks: visibleReviewQueueTasks,
              store: store,
              showsLoadMore: !usesReviewQueuePreview)
            if usesReviewQueuePreview {
              TaskFoldSection(
                isExpanded: $showOpenBacklog,
                title: String(localized: "tasks.section.backlog", defaultValue: "Backlog", table: "Localizable", bundle: LorvexL10n.bundle),
                tasks: visibleOpenBacklogTasks,
                pagedSections: [.open],
                store: store,
                accessibilityIdentifier: "tasks.openBacklog.disclosure")
            }
            TaskFoldSection(
              isExpanded: $showLater,
              title: String(localized: "tasks.section.later", defaultValue: "Later", table: "Localizable", bundle: LorvexL10n.bundle),
              tasks: visibleLaterTasks,
              pagedSections: [.deferred, .scheduled, .someday],
              store: store,
              accessibilityIdentifier: "tasks.later.disclosure")
            TaskFoldSection(
              isExpanded: $showHistory,
              title: String(localized: "tasks.section.history", defaultValue: "History", table: "Localizable", bundle: LorvexL10n.bundle),
              tasks: visibleHistoryTaskPool,
              pagedSections: [.completed, .cancelled],
              store: store,
              accessibilityIdentifier: "tasks.history.disclosure")
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
      // A typed query waits for a typing pause, so a keystroke doesn't fire a
      // six-query workspace load each time; `loadTaskWorkspace` discards the
      // results of a superseded query, so they can't overwrite the current
      // view.
      guard await LorvexSearchDebounce.shouldSearch(store.searchText) else { return }
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
    .navigationTitle(String(localized: "sidebar.item.tasks", defaultValue: "All Tasks", table: "Localizable", bundle: LorvexL10n.bundle))
    .toolbar {
      // Leading edge: the window's search field holds the trailing one.
      ToolbarItemGroup(placement: .primaryAction) {
        if store.taskWorkspaceSelectionCount > 1 {
          TasksSelectionActionMenu(store: store)
        }
        TasksReviewOptionsMenu(isTableMode: $isTableMode, priorityFilter: $priorityFilter)
      }
    }
    .lorvexOpenDestinationActivity(selection: .tasks, isActive: store.selection == .tasks)
  }

}
