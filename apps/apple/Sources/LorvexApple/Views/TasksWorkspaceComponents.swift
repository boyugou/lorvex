import LorvexCore
import SwiftUI

struct TasksInitialLoadingState: View {
  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      ProgressView()
        .controlSize(.small)

      VStack(alignment: .leading, spacing: 2) {
        Text(LocalizedStringResource("tasks.loading.title", defaultValue: "Loading Tasks", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(.primary)
        Text(LocalizedStringResource(
          "tasks.loading.description",
          defaultValue: "Keeping the review queue ready while Lorvex refreshes task data.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.vertical, LorvexDesign.Spacing.l)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("tasks.initialLoading")
  }
}

struct TaskStatusSection: View {
  let title: String
  let status: TaskWorkspaceSection
  let tasks: [LorvexTask]
  @Bindable var store: AppStore
  var systemImage: String? = nil
  var tint: Color? = nil
  var topSpacing: CGFloat = LorvexDesign.Spacing.m
  var showsLoadMore = true
  /// A section nested under a top-level group (History / Later) — its header is
  /// rendered subordinate and its content is indented to read as a child.
  var isSubsection = false

  var body: some View {
    if !tasks.isEmpty || (showsLoadMore && store.taskWorkspaceHasMore(status: status)) {
      VStack(alignment: .leading, spacing: 0) {
        WorkspaceTaskSectionHeader(
          title: title,
          countText: store.taskWorkspaceHasMore(status: status) ? "\(tasks.count)+" : "\(tasks.count)",
          systemImage: systemImage ?? status.sectionSymbolName,
          tint: tint ?? (status == .open ? .accentColor : status.sectionTint),
          topSpacing: topSpacing,
          isSubsection: isSubsection
        )
        .padding(.horizontal, LorvexDesign.Spacing.l)

        ForEach(tasks) { task in
          TaskRowDropTarget(task: task, store: store)
            .padding(.horizontal, LorvexDesign.Spacing.m)
        }
        if showsLoadMore && store.taskWorkspaceHasMore(status: status) {
          Button {
            Task { await store.loadMoreTaskWorkspace(status: status) }
          } label: {
            Label(
              String(localized: "tasks.results.load_more", defaultValue: "Load More", table: "Localizable", bundle: LorvexL10n.bundle),
              systemImage: "arrow.down.circle"
            )
          }
          .buttonStyle(.borderless)
          .disabled(store.taskWorkspaceIsLoadingMore(status: status))
          .padding(.horizontal, LorvexDesign.Spacing.l)
          .padding(.vertical, LorvexDesign.Spacing.s)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      // Nest the whole sub-section (header + rows) under its parent group.
      .padding(.leading, isSubsection ? LorvexDesign.Spacing.m : 0)
    }
  }
}

struct TaskOpenBacklogDisclosure: View {
  @Binding var isExpanded: Bool
  let tasks: [LorvexTask]
  @Bindable var store: AppStore

  private var hasMore: Bool {
    store.taskWorkspaceHasMore(status: .open)
  }

  var body: some View {
    if !tasks.isEmpty || hasMore {
      VStack(alignment: .leading, spacing: 0) {
        WorkspaceTaskDisclosureHeader(
          isExpanded: $isExpanded,
          title: String(localized: "tasks.section.backlog", defaultValue: "Backlog", table: "Localizable", bundle: LorvexL10n.bundle),
          countText: hasMore ? "\(tasks.count)+" : "\(tasks.count)",
          systemImage: "tray.full",
          tint: .secondary
        )
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.top, LorvexDesign.Spacing.s)

        if isExpanded {
          ForEach(tasks) { task in
            TaskRowDropTarget(task: task, store: store)
              .padding(.horizontal, LorvexDesign.Spacing.m)
          }
          if hasMore {
            Button {
              Task { await store.loadMoreTaskWorkspace(status: .open) }
            } label: {
              Label(
                String(localized: "tasks.results.load_more", defaultValue: "Load More", table: "Localizable", bundle: LorvexL10n.bundle),
                systemImage: "arrow.down.circle"
              )
            }
            .buttonStyle(.borderless)
            .disabled(store.taskWorkspaceIsLoadingMore(status: .open))
            .padding(.horizontal, LorvexDesign.Spacing.l)
            .padding(.vertical, LorvexDesign.Spacing.s)
          }
        }
      }
      .accessibilityIdentifier("tasks.openBacklog.disclosure")
    }
  }
}

struct TaskLaterDisclosure: View {
  @Binding var isExpanded: Bool
  let deferredTasks: [LorvexTask]
  let scheduledTasks: [LorvexTask]
  let somedayTasks: [LorvexTask]
  @Bindable var store: AppStore

  private var count: Int {
    deferredTasks.count + scheduledTasks.count + somedayTasks.count
  }

  private var hasMore: Bool {
    store.taskWorkspaceHasMore(status: .deferred)
      || store.taskWorkspaceHasMore(status: .scheduled)
      || store.taskWorkspaceHasMore(status: .someday)
  }

  var body: some View {
    if count > 0 || hasMore {
      VStack(alignment: .leading, spacing: 0) {
        WorkspaceTaskDisclosureHeader(
          isExpanded: $isExpanded,
          title: String(localized: "tasks.section.later", defaultValue: "Later", table: "Localizable", bundle: LorvexL10n.bundle),
          countText: hasMore ? "\(count)+" : "\(count)",
          systemImage: "clock",
          tint: .secondary
        )
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.top, LorvexDesign.Spacing.s)

        if isExpanded {
          TaskStatusSection(
            title: String(localized: "tasks.section.deferred", defaultValue: "Deferred", table: "Localizable", bundle: LorvexL10n.bundle),
            status: .deferred,
            tasks: deferredTasks,
            store: store,
            topSpacing: LorvexDesign.Spacing.s,
            isSubsection: true
          )
          TaskStatusSection(
            title: String(localized: "tasks.section.scheduled", defaultValue: "Snoozed", table: "Localizable", bundle: LorvexL10n.bundle),
            status: .scheduled,
            tasks: scheduledTasks,
            store: store,
            topSpacing: LorvexDesign.Spacing.s,
            isSubsection: true
          )
          TaskStatusSection(
            title: String(localized: "tasks.section.someday", defaultValue: "Someday", table: "Localizable", bundle: LorvexL10n.bundle),
            status: .someday,
            tasks: somedayTasks,
            store: store,
            topSpacing: LorvexDesign.Spacing.s,
            isSubsection: true
          )
        }
      }
      .accessibilityIdentifier("tasks.later.disclosure")
    }
  }
}

struct TaskHistoryDisclosure: View {
  @Binding var isExpanded: Bool
  let completedTasks: [LorvexTask]
  let cancelledTasks: [LorvexTask]
  @Bindable var store: AppStore

  private var count: Int {
    completedTasks.count + cancelledTasks.count
  }

  var body: some View {
    if count > 0 || store.taskWorkspaceHasMore(status: .completed) || store.taskWorkspaceHasMore(status: .cancelled) {
      VStack(alignment: .leading, spacing: 0) {
        WorkspaceTaskDisclosureHeader(
          isExpanded: $isExpanded,
          title: String(localized: "tasks.section.history", defaultValue: "History", table: "Localizable", bundle: LorvexL10n.bundle),
          countText: store.taskWorkspaceHasMore(status: .completed) || store.taskWorkspaceHasMore(status: .cancelled)
            ? "\(count)+"
            : "\(count)",
          systemImage: "clock.arrow.circlepath",
          tint: .secondary
        )
        .padding(.horizontal, LorvexDesign.Spacing.l)
        .padding(.top, LorvexDesign.Spacing.s)

        if isExpanded {
          TaskStatusSection(
            title: String(localized: "tasks.section.completed", defaultValue: "Completed", table: "Localizable", bundle: LorvexL10n.bundle),
            status: .completed,
            tasks: completedTasks,
            store: store,
            topSpacing: LorvexDesign.Spacing.s,
            isSubsection: true
          )
          TaskStatusSection(
            title: String(localized: "tasks.section.cancelled", defaultValue: "Cancelled", table: "Localizable", bundle: LorvexL10n.bundle),
            status: .cancelled,
            tasks: cancelledTasks,
            store: store,
            topSpacing: LorvexDesign.Spacing.s,
            isSubsection: true
          )
        }
      }
      .accessibilityIdentifier("tasks.history.disclosure")
    }
  }
}

struct TaskRowDropTarget: View {
  let task: LorvexTask
  @Bindable var store: AppStore

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
      // The Tasks workspace spans every list, so each row shows its owning list.
      showsOwningList: true
    )
  }
}
