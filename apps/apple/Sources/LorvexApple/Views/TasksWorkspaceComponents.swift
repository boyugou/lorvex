import LorvexCore
import SwiftUI

/// The task workspace's first load: a small spinner and "Loading Tasks" where
/// the rows will appear. It is the only loading cue; the header adds none.
struct TasksInitialLoadingState: View {
  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      ProgressView()
        .controlSize(.small)
      Text(LocalizedStringResource("tasks.loading.title", defaultValue: "Loading Tasks", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.vertical, LorvexDesign.Spacing.l)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("tasks.initialLoading")
  }
}

/// The open tasks at the top of the Tasks workspace, straight under the
/// quick-add field. They carry no header: the field above them already says
/// this is the list being worked, and a title would only add an indent level.
struct TaskOpenRows: View {
  let tasks: [LorvexTask]
  @Bindable var store: AppStore
  /// False while the rows are a preview whose overflow folds into Backlog,
  /// which then owns paging.
  var showsLoadMore = true

  var body: some View {
    let timeLabels = store.todayTimeLabels
    VStack(alignment: .leading, spacing: 0) {
      ForEach(tasks) { task in
        TaskRowDropTarget(task: task, store: store, timeLabel: timeLabels[task.id])
          .padding(.horizontal, LorvexDesign.Spacing.m)
      }
      if showsLoadMore && store.taskWorkspaceHasMore(status: .open) {
        WorkspaceTaskLoadMoreButton(isLoading: store.taskWorkspaceIsLoadingMore(status: .open)) {
          Task { await store.loadMoreTaskWorkspace(status: .open) }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, LorvexDesign.Spacing.xs)
  }
}

/// A folded group of the Tasks workspace (Backlog, Later, History): a quiet
/// fold row, then, when unfolded, one flat run of task rows on the same two
/// columns as the open tasks above. The group has no sub-headers; each row's
/// own status circle and metadata say what kind of task it is.
///
/// `pagedSections` are the workspace sections whose pages feed `tasks`. Load
/// More appears while any of them has another page, and fetches the next page
/// of each one that does.
struct TaskFoldSection: View {
  @Binding var isExpanded: Bool
  let title: String
  let tasks: [LorvexTask]
  let pagedSections: [TaskWorkspaceSection]
  @Bindable var store: AppStore
  let accessibilityIdentifier: String

  private var sectionsWithMore: [TaskWorkspaceSection] {
    pagedSections.filter { store.taskWorkspaceHasMore(status: $0) }
  }

  var body: some View {
    let sectionsWithMore = sectionsWithMore
    if !tasks.isEmpty || !sectionsWithMore.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        WorkspaceTaskDisclosureHeader(
          isExpanded: $isExpanded,
          title: title,
          countText: sectionsWithMore.isEmpty ? "\(tasks.count)" : "\(tasks.count)+"
        )
        .padding(.horizontal, WorkspaceTaskColumns.markerLeading)
        .padding(.top, LorvexDesign.Spacing.m)
        .padding(.bottom, LorvexDesign.Spacing.xs)

        if isExpanded {
          ForEach(tasks) { task in
            TaskRowDropTarget(task: task, store: store)
              .padding(.horizontal, LorvexDesign.Spacing.m)
          }
          if !sectionsWithMore.isEmpty {
            WorkspaceTaskLoadMoreButton(
              isLoading: sectionsWithMore.contains { store.taskWorkspaceIsLoadingMore(status: $0) }
            ) {
              Task {
                for section in sectionsWithMore {
                  await store.loadMoreTaskWorkspace(status: section)
                }
              }
            }
          }
        }
      }
      .accessibilityIdentifier(accessibilityIdentifier)
    }
  }
}

struct TaskRowDropTarget: View {
  let task: LorvexTask
  @Bindable var store: AppStore
  /// When the task happens today, if it is timed (``AppStore/todayTimeLabels``).
  var timeLabel: String? = nil

  private var isBatchSelected: Bool {
    store.taskWorkspaceSelectedTaskIDs.contains(task.id)
  }

  var body: some View {
    WorkspaceSelectableTaskRow(
      task: task,
      store: store,
      selectionSurface: .taskWorkspace,
      isBatchSelected: isBatchSelected,
      batchAccessibilityIdentifier: "tasks.row.batchSelect.\(task.id)",
      toggleBatchSelection: { store.toggleTaskWorkspaceBatchSelection(task.id) },
      openTask: { store.selectOnlyTaskInWorkspace(task.id) },
      // Unscoped, the workspace spans every list, so the owning list is the row's
      // most useful context. Scoped to one list, every row would repeat the list
      // already named in the header — the same reason a list's own detail pane
      // never shows it.
      showsOwningList: store.taskWorkspaceListScopeID == nil,
      timeLabel: timeLabel
    )
  }
}
