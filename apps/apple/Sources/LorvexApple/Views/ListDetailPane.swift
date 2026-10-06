import LorvexCore
import SwiftUI

/// One list's working set — its open and started tasks — as the detached list
/// window shows it: the list's identity header, an inline quick-add that files
/// into the list, and the rows, loaded a page at a time behind a Load More
/// control. The header names the list and carries its description; it never
/// counts the rows below it. With two or more rows selected, a Selection
/// Actions menu joins the header's trailing edge. The window's title is the
/// list's name, so the Window menu tells list windows apart, but the titlebar
/// shows no text and the window has no toolbar: the name appears once, in the
/// header, and the titlebar stays a thin strip.
struct ListDetailPane: View {
  @Bindable var store: AppStore

  private var selectedListTint: Color {
    Color(lorvexHex: store.selectedListDetail?.list.color) ?? .accentColor
  }

  var body: some View {
    Group {
      if let detail = store.selectedListDetail {
        VStack(spacing: 0) {
          detailHeader(detail)

          Divider()

          WorkspaceReviewList(taskNavigation: store.arrowKeyTaskNavigation(on: .selectedList)) {
            QuickAddRow(
              placeholder: AppStore.quickAddPlaceholder(listName: detail.list.displayName),
              focusToken: store.quickAddFocusToken,
              preview: store.quickAddPreview
            ) { text in
              await store.createInlineTask(text, destination: .list(detail.list.id))
            }
            .padding(.horizontal, LorvexDesign.Spacing.m)
            .padding(.top, LorvexDesign.Spacing.s)

            // Read from the list's own tasks, not the Today page: a detached
            // list window never loads Today, and a task's time today is its
            // planned time on that day either way.
            let timeLabels = store.selectedListTasks.times(on: store.logicalTodayDateString)
              .mapValues { TodayCalmCopy.timeRange(start: $0.lowerBound, end: $0.upperBound) }
            ForEach(store.selectedListTasks) { task in
              ListDetailTaskResultRow(task: task, store: store, timeLabel: timeLabels[task.id])
                .padding(.horizontal, LorvexDesign.Spacing.m)
            }

            if store.selectedListHasMoreTasks {
              WorkspaceTaskLoadMoreButton(isLoading: store.isLoadingMoreSelectedListTasks) {
                Task { await store.loadMoreSelectedListTasks() }
              }
            }
          }
          .cancelSelectedTaskOnDelete(store, on: .selectedList)
          .overlay {
            if let state = listDetailEmptyState(for: detail) {
              LorvexEmptyStatePanel(model: state)
            }
          }
        }
      } else {
        DetachedWindowPlaceholder(
          systemImage: "tray",
          title: String(
            localized: "detached_window.placeholder.no_list_title",
            defaultValue: "No List Selected",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          )
        )
      }
    }
    .navigationTitle(store.selectedListDetail?.list.displayName ?? LorvexWindowID.detachedListTitle)
    .toolbar(removing: .title)
    .userActivity(
      LorvexActivityType.openList,
      isActive: store.selectedListDetail != nil
    ) { activity in
      guard let listID = store.selectedListDetail?.list.id else { return }
      configureOpenListActivity(activity, listID: listID, title: store.selectedListDetail?.list.displayName)
    }
  }

  /// The list's icon in its color, its name, and its description when it has
  /// one — the same identity the main window's list scope shows — plus the
  /// batch menu while two or more rows are selected.
  private func detailHeader(_ detail: ListDetailSnapshot) -> some View {
    WorkspacePlanHeaderChrome {
      HStack(alignment: .center, spacing: LorvexDesign.Spacing.m) {
        WorkspaceHeaderIdentity(
          title: detail.list.displayName,
          subtitle: detail.list.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
          icon: detail.list.icon ?? "folder",
          accessibilityIdentifier: "listDetail.header.identity"
        )
        .tint(selectedListTint)

        Spacer(minLength: 0)

        if store.selectedListTaskSelectionCount > 1 {
          ListDetailSelectionActionMenu(store: store)
        }
      }
    }
  }

  /// The calm panel over a list with no open or started task: finished when
  /// the list has completed work, empty when it never had any.
  private func listDetailEmptyState(for detail: ListDetailSnapshot) -> LorvexEmptyStateModel? {
    guard detail.tasks.isEmpty else { return nil }
    let isAllDone = detail.list.completedCount > 0
    return LorvexEmptyStateModel(
      title: isAllDone
        ? String(localized: "list_detail.empty.all_done_title", defaultValue: "All Done", table: "Localizable", bundle: LorvexL10n.bundle)
        : String(localized: "list_detail.empty.no_tasks_title", defaultValue: "No Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
      message: isAllDone
        ? String(
          localized: "list_detail.empty.all_done_description",
          defaultValue: "Every task in this list is done.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        )
        : String(
          localized: "list_detail.empty.no_tasks_description",
          defaultValue: "Tasks assigned to this list will appear here.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
      systemImage: isAllDone
        ? "checkmark.circle"
        : LorvexListIconView.symbolName(for: detail.list.icon) ?? "checklist",
      tint: selectedListTint,
      action: nil
    )
  }
}

/// The batch actions for the detached list window's selected rows: complete,
/// defer, cancel, reopen, Someday, and moving them to another list.
private struct ListDetailSelectionActionMenu: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) private var undoManager

  var body: some View {
    Menu {
      TaskBatchActionMenuContent(
        store: store,
        selectionSurface: .selectedList,
        canActOnSelection: store.selectedListTasksForBatch.contains {
          $0.status.isActive
        },
        canReopenSelection: store.selectedListTasksForBatch.contains {
          $0.status.isResolved
        },
        canMoveSelectionToSomeday: store.selectedListTasksForBatch.contains { $0.status == .open },
        complete: { Task { await store.completeSelectedListTaskSelection() } },
        deferToTomorrow: { Task { await store.deferSelectedListTaskSelection() } },
        cancel: { Task { await store.cancelSelectedListTaskSelection() } },
        reopen: { Task { await store.reopenSelectedListTaskSelection() } },
        moveToSomeday: { Task { await store.markSelectedListTaskSelectionSomeday() } },
        move: { listID in
          Task {
            await store.moveSelectedListTaskSelection(toListID: listID, undoManager: undoManager)
          }
        },
        excludeListID: store.selectedListID
      )
    } label: {
      Label(selectionActionsLabel, systemImage: "checklist.checked")
        .labelStyle(.titleAndIcon)
    }
    .menuStyle(.button)
    .buttonStyle(.bordered)
    .fixedSize()
    .help(selectionActionsLabel)
    .accessibilityLabel(
      String(
        localized: "tasks.selection.count",
        defaultValue: "\(store.selectedListTaskSelectionCount) selected",
        table: "Localizable", bundle: LorvexL10n.bundle)
    )
    .accessibilityIdentifier("listDetail.batchTaskSelection")
  }

  private var selectionActionsLabel: String {
    String(localized: "tasks.header.selection_actions", defaultValue: "Selection Actions", table: "Localizable", bundle: LorvexL10n.bundle)
  }
}

private struct ListDetailTaskResultRow: View {
  let task: LorvexTask
  @Bindable var store: AppStore
  /// When the task happens today, if it has a planned time today.
  var timeLabel: String? = nil

  private var isBatchSelected: Bool {
    store.selectedListTaskIDs.contains(task.id)
  }

  var body: some View {
    WorkspaceSelectableTaskRow(
      task: task,
      store: store,
      selectionSurface: .selectedList,
      isBatchSelected: isBatchSelected,
      batchAccessibilityIdentifier: "listDetail.row.batchSelect.\(task.id)",
      toggleBatchSelection: { store.toggleSelectedListTaskBatchSelection(task.id) },
      openTask: { store.selectOnlySelectedListTask(task.id) },
      isBlocked: store.isBlocked(task),
      timeLabel: timeLabel
    )
  }
}
