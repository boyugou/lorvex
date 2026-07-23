import LorvexCore
import SwiftUI

struct ListDetailPane: View {
  @Bindable var store: AppStore

  private var selectedListTint: Color {
    Color(lorvexHex: store.selectedListDetail?.list.color) ?? .accentColor
  }

  private var canMoveSelectedTaskHere: Bool {
    guard
      store.selectedTaskID != nil,
      let selectedTask = store.selectedTask,
      let selectedListID = store.selectedListID
    else {
      return false
    }
    return selectedTask.listID != selectedListID
  }

  private func listDetailEmptyState(for detail: ListDetailSnapshot?) -> LorvexEmptyStateModel? {
    if detail == nil {
      return LorvexEmptyStateModel(
        title: String(localized: "list_detail.empty.select_list_title", defaultValue: "Select a List", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "list_detail.empty.select_list_description",
          defaultValue: "Choose a list to inspect its tasks.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "folder",
        tint: .accentColor,
        action: nil
      )
    }

    if store.hasActiveSearch && store.filteredSelectedListTasks.isEmpty {
      return LorvexEmptyStateModel(
        title: String(localized: "list_detail.empty.search_title", defaultValue: "No List Results", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "list_detail.empty.search_description",
          defaultValue: "No task in this list matches the current search.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "text.magnifyingglass",
        tint: .accentColor,
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

    if let detail, detail.tasks.isEmpty {
      return LorvexEmptyStateModel(
        title: String(localized: "list_detail.empty.no_tasks_title", defaultValue: "No Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "list_detail.empty.no_tasks_description",
          defaultValue: "Tasks assigned to this list will appear here.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: detail.list.icon ?? "checklist",
        tint: selectedListTint,
        chips: [
          LorvexEmptyStateChip(
            title: detail.list.name,
            systemImage: detail.list.icon ?? "folder",
            tint: selectedListTint
          )
        ],
        action: nil
      )
    }

    return nil
  }

  var body: some View {
    VStack(spacing: 0) {
      if let detail = store.selectedListDetail {
        detailHeader(detail)

        Divider()

        WorkspaceReviewList(taskNavigation: store.arrowKeyTaskNavigation(on: .selectedList)) {
          WorkspaceTaskSectionHeader(
            title: String(localized: "list_detail.tasks_section", defaultValue: "Tasks", table: "Localizable", bundle: LorvexL10n.bundle),
            count: store.filteredSelectedListTasks.count,
            systemImage: "checklist",
            tint: selectedListTint
          )
          .padding(.horizontal, LorvexDesign.Spacing.l)

          QuickAddRow(
            placeholder: String(
              format: String(
                localized: "list_detail.quick_add.placeholder",
                defaultValue: "Add a task to “%@”",
                table: "Localizable",
                bundle: LorvexL10n.bundle
              ),
              detail.list.name
            ),
            isCreating: store.isCreating,
            focusToken: store.quickAddFocusToken
          ) { title in
            await store.createTaskInList(title: title, listID: detail.list.id)
          }
          .padding(.horizontal, LorvexDesign.Spacing.m)

          ForEach(store.filteredSelectedListTasks) { task in
            ListDetailTaskResultRow(task: task, store: store)
              .padding(.horizontal, LorvexDesign.Spacing.m)
          }
        }
        .cancelSelectedTaskOnDelete(store, on: .selectedList)
        .overlay {
          if let state = listDetailEmptyState(for: detail) {
            LorvexEmptyStatePanel(model: state)
          }
        }
      } else {
        if let state = listDetailEmptyState(for: nil) {
          LorvexEmptyStatePanel(model: state)
        }
      }
    }
    .userActivity(
      LorvexActivityType.openList,
      isActive: store.selectedListDetail != nil
    ) { activity in
      guard let listID = store.selectedListDetail?.list.id else { return }
      let built = makeOpenListActivity(listID: listID, title: store.selectedListDetail?.list.name)
      activity.title = built.title
      activity.isEligibleForHandoff = built.isEligibleForHandoff
      activity.isEligibleForSearch = built.isEligibleForSearch
      activity.requiredUserInfoKeys = built.requiredUserInfoKeys
      activity.addUserInfoEntries(from: built.userInfo ?? [:])
    }
  }

  private func detailHeader(_ detail: ListDetailSnapshot) -> some View {
    WorkspacePlanHeaderChrome {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
          LorvexListIconView(
            icon: detail.list.icon,
            tint: selectedListTint,
            size: 34,
            font: .system(size: 18, weight: .semibold),
            background: .roundedSquare(size: 34, opacity: 0.14, cornerRadius: 8)
          )

          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
            Text(detail.list.name)
              .font(LorvexDesign.Typography.sectionHeader)
              .lineLimit(1)

            Text(headerSubtitle(detail))
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
              .monospacedDigit()

            if let description = detail.list.description, !description.isEmpty {
              Text(description)
                .font(LorvexDesign.Typography.secondaryText)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.top, 2)
            }
          }

          Spacer(minLength: LorvexDesign.Spacing.l)

          headerActions
        }

        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          Text(listDetailSummary(detail.list))
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)

          if let fraction = detail.list.progressFraction {
            LorvexProgressBar(value: fraction, tint: selectedListTint)
              .frame(maxWidth: 180)
              .accessibilityLabel(progressText(fraction))
              .accessibilityIdentifier("listDetail.progress")
          }
        }
        .accessibilityIdentifier("listDetail.header.stats")
      }
    }
  }

  private func listDetailSummary(_ list: LorvexList) -> String {
    String(
      format: String(
        localized: "list_detail.summary",
        defaultValue: "%lld open · %lld complete · %lld total",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      list.openCount,
      list.completedCount,
      list.totalCount
    )
  }

  @ViewBuilder
  private var headerActions: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      if canMoveSelectedTaskHere {
        Button {
          Task { await store.moveSelectedTaskToSelectedList() }
        } label: {
          Label(
            String(localized: "list_detail.move_selected_here", defaultValue: "Move Here", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "arrow.right.doc.on.clipboard"
          )
        }
        .buttonStyle(.lorvexSecondary)
        .help(String(
          localized: "list_detail.move_selected_here.help",
          defaultValue: "Move Selected Task Here",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
        .accessibilityIdentifier("listDetail.moveSelectedHere")
      }

      if store.selectedListTaskSelectionCount > 1 {
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
            move: { listID in Task { await store.moveSelectedListTaskSelection(toListID: listID) } },
            excludeListID: store.selectedListID
          )
        } label: {
          Label("\(store.selectedListTaskSelectionCount)", systemImage: "checklist.checked")
        }
        .menuStyle(.button)
        .buttonStyle(.lorvexNeutral)
        .help(String(localized: "common.more", defaultValue: "More", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("listDetail.batchTaskSelection")
      }
    }
  }

  private func headerSubtitle(_ detail: ListDetailSnapshot) -> String {
    if store.hasActiveSearch {
      return matchingCountText(detail.totalMatching)
    }
    if detail.truncated {
      return shownCountWithNextPageText(
        returned: detail.returned,
        nextOffset: detail.nextOffset ?? detail.offset)
    }
    return totalCountText(detail.totalMatching)
  }

  private func progressText(_ fraction: Double) -> String {
    fraction.formatted(.percent.precision(.fractionLength(0)))
  }

  private func matchingCountText(_ count: Int) -> String {
    String(
      format: String(localized: "list_detail.count.matching", defaultValue: "%lld matching", table: "Localizable", bundle: LorvexL10n.bundle),
      count
    )
  }

  private func totalCountText(_ count: Int) -> String {
    String(
      localized: "list_detail.tasks_count",
      defaultValue: "\(count) tasks",
      table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  private func shownCountWithNextPageText(returned: Int, nextOffset: Int) -> String {
    String(
      format: String(
        localized: "list_detail.count.shown_next_page",
        defaultValue: "%lld shown · next page %lld",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      returned,
      nextOffset
    )
  }
}

private struct ListDetailTaskResultRow: View {
  let task: LorvexTask
  @Bindable var store: AppStore

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
      openTask: { store.selectOnlySelectedListTask(task.id) }
    )
  }
}
