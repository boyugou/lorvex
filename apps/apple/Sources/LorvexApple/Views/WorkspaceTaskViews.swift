import LorvexCore
import SwiftUI

private enum WorkspaceTaskSectionMetrics {
  static let iconWidth: CGFloat = 16
}

/// The two columns every row of a task lane lines up on, measured from the
/// lane's edge: the marker column, where a task row's completion circle and a
/// fold row's chevron sit, and the text column, where both titles start.
enum WorkspaceTaskColumns {
  /// From the lane's edge to the marker column: the row's outer inset plus its
  /// own inner padding.
  static let markerLeading = LorvexDesign.Spacing.l
  /// The marker column's width: a task row's completion circle.
  static let markerWidth: CGFloat = 20
  /// From the marker column to the text column.
  static let markerSpacing = LorvexDesign.Spacing.m
}

private enum WorkspaceTaskSectionTypography {
  static let title = LorvexDesign.Typography.primaryText.weight(.semibold)
  static let foldTitle = LorvexDesign.Typography.secondaryText.weight(.semibold)
  static let icon = LorvexDesign.Typography.tertiaryText.weight(.semibold)
}

/// A section's title row: a tinted glyph and the title. It carries no count,
/// because an open section's rows are their own count; a folding section uses
/// ``WorkspaceTaskDisclosureHeader``, which counts its rows while they are
/// folded away.
struct WorkspaceTaskSectionHeader: View {
  let title: String
  let systemImage: String
  let tint: Color
  var topSpacing: CGFloat = LorvexDesign.Spacing.m
  var bottomSpacing: CGFloat = LorvexDesign.Spacing.xs

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: systemImage)
        .font(WorkspaceTaskSectionTypography.icon)
        .foregroundStyle(tint)
        .frame(width: WorkspaceTaskSectionMetrics.iconWidth)

      Text(title)
        .font(WorkspaceTaskSectionTypography.title)
        .foregroundStyle(.primary)

      Spacer(minLength: 0)
    }
    .textCase(nil)
    .padding(.top, topSpacing)
    .padding(.bottom, bottomSpacing)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityAddTraits(.isHeader)
  }
}

/// A folding section's quiet title row in a task lane: the disclosure chevron
/// in the marker column, where the rows below carry their completion circles,
/// and the title in the text column, so folding adds no indent of its own. The
/// row count shows while the section is folded (an open section's rows are
/// their own count); VoiceOver hears it either way. Place it at
/// ``WorkspaceTaskColumns/markerLeading`` from the lane's edge.
/// `accessibilityIdentifier` names the fold it opens, such as
/// `tasks.later.disclosure`.
struct WorkspaceTaskDisclosureHeader: View {
  @Binding var isExpanded: Bool
  let title: String
  let countText: String
  let accessibilityIdentifier: String

  var body: some View {
    Button {
      lorvexAnimated(.snappy(duration: 0.16)) {
        isExpanded.toggle()
      }
    } label: {
      HStack(spacing: WorkspaceTaskColumns.markerSpacing) {
        LorvexDisclosureChevron(isExpanded: isExpanded)
          .font(WorkspaceTaskSectionTypography.icon)
          .foregroundStyle(.tertiary)
          .frame(width: WorkspaceTaskColumns.markerWidth)

        HStack(spacing: LorvexDesign.Spacing.s) {
          Text(title)
            .font(WorkspaceTaskSectionTypography.foldTitle)
            .foregroundStyle(.secondary)

          if !isExpanded {
            WorkspaceTaskSectionCountBadge(countText: countText)
              .transition(.opacity)
          }
        }

        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(lorvexPairLabel(title, countText))
    .accessibilityValue(
      isExpanded
        ? Text(LocalizedStringResource("common.expanded", defaultValue: "Expanded", table: "Localizable", bundle: LorvexL10n.bundle))
        : Text(LocalizedStringResource("common.collapsed", defaultValue: "Collapsed", table: "Localizable", bundle: LorvexL10n.bundle))
    )
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

/// The control at the end of a paged task list that appends the next page
/// below the rows already shown. It is disabled while that page is in flight,
/// so a second click cannot ask for the same rows again.
struct WorkspaceTaskLoadMoreButton: View {
  let isLoading: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(
        String(localized: "tasks.results.load_more", defaultValue: "Load More", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "arrow.down.circle"
      )
    }
    .buttonStyle(.borderless)
    .disabled(isLoading)
    .padding(.horizontal, LorvexDesign.Spacing.l)
    .padding(.vertical, LorvexDesign.Spacing.s)
  }
}

private struct WorkspaceTaskSectionCountBadge: View {
  let countText: String

  var body: some View {
    LorvexChip(countText, tint: LorvexDesign.Palette.neutral)
  }
}

/// A batch-selection entry for a task's context menu: its title (Select or
/// Deselect) and the toggle it runs.
struct WorkspaceTaskBatchMenuItem {
  let title: String
  let toggle: () -> Void
}

struct WorkspaceTaskContextMenu: View {
  @Bindable var store: AppStore
  let task: LorvexTask
  /// Offered on rows that take part in batch selection; `nil` elsewhere.
  var batchItem: WorkspaceTaskBatchMenuItem? = nil
  @Environment(\.undoManager) private var undoManager
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    if task.status == .inProgress {
      Button {
        Task { await store.pauseTaskFromRow(task) }
      } label: {
        Label(
          String(
            localized: "task.action.pause", defaultValue: "Pause", table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "pause.circle"
        )
      }
    } else {
      // Grayed out, not hidden, while a task it waits on is unfinished: the
      // row's Blocked capsule says why.
      Button {
        Task { await store.startTaskFromRow(task) }
      } label: {
        Label(
          String(localized: "task.action.start", defaultValue: "Start", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "play.circle"
        )
      }
      .disabled(task.status != .open || store.startIsHeldUp(for: task))
    }

    TaskDeferMenu(store: store, onDefer: { date in
      Task { await store.deferTaskFromRow(task, until: date) }
    }) {
      Label(
        String(localized: "common.defer", defaultValue: "Defer", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "clock.arrow.circlepath"
      )
    }
    .disabled(task.status.isResolved)

    TaskSnoozeMenu(store: store, onSnooze: { date in
      Task { await store.snoozeTask(id: task.id, until: date) }
    }) {
      Label(
        String(localized: "task.snooze.title", defaultValue: "Snooze Until", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "eye.slash"
      )
    }
    .disabled(task.status.isResolved)
    .accessibilityIdentifier("task.snooze.\(task.id)")

    Button {
      store.selectedTaskID = task.id
      Task { await store.completeSelectedTask(undoManager: undoManager) }
    } label: {
      Label(
        String(localized: "common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "checkmark.circle"
      )
    }
    .disabled(task.status.isResolved)

    Button {
      store.selectedTaskID = task.id
      Task { await store.reopenSelectedTask() }
    } label: {
      Label(
        String(localized: "common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "arrow.counterclockwise"
      )
    }
    .disabled(!(task.status.isResolved))

    if task.status == .someday {
      Button {
        store.selectedTaskID = task.id
        Task { await store.reopenSelectedTask() }
      } label: {
        Label(
          String(localized: "task.action.move_to_open", defaultValue: "Move to Open", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.up.circle"
        )
      }
    } else {
      Button {
        store.selectedTaskID = task.id
        Task { await store.markSelectedTaskSomeday() }
      } label: {
        Label(
          String(localized: "task.action.move_to_someday", defaultValue: "Move to Someday", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "moon"
        )
      }
      .disabled(task.status != .open)
    }

    // The day choices of dragging the row onto the calendar, for a pointer or a
    // keyboard that cannot drag. The task keeps its time of day.
    Menu {
      ForEach(TaskPlanDayChoice.allCases) { choice in
        Button {
          Task {
            await store.planTasks(
              ids: [task.id], daysFromToday: choice.daysFromToday, undoManager: undoManager)
          }
        } label: {
          Label(choice.title, systemImage: choice.systemImage)
        }
      }
    } label: {
      Label(AppStore.planTaskTitle, systemImage: "calendar.badge.plus")
    }
    .disabled(!task.status.isActionable)
    .accessibilityIdentifier("task.plan.\(task.id)")

    // Every list but the one the task is in. Makes the same move as dragging the
    // row onto a list in the sidebar, for a pointer that cannot drag.
    let moveTargets = store.orderedLists.filter {
      $0.id != (task.listID ?? LorvexListNaming.inboxID)
    }
    Menu {
      ForEach(moveTargets) { list in
        Button {
          Task { await store.moveTasks(ids: [task.id], toListID: list.id, undoManager: undoManager) }
        } label: {
          LorvexListMenuLabel(list: list)
        }
      }
    } label: {
      Label(AppStore.moveToListTitle, systemImage: "folder")
    }
    .disabled(moveTargets.isEmpty)
    .accessibilityIdentifier("task.moveToList.\(task.id)")

    Divider()

    if let batchItem {
      Button(action: batchItem.toggle) {
        Label(batchItem.title, systemImage: "checkmark.circle")
      }
    }

    Button {
      openWindow(id: LorvexWindowID.stickyTaskGroupID, value: StickyTaskRef(taskID: task.id))
    } label: {
      Label(
        String(localized: "task_detail.pin_sticky", defaultValue: "Pin as Sticky", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "pin"
      )
    }

    Button(role: .destructive) {
      // Recurring tasks route to the shared occurrence-vs-series scope dialog
      // (ContentView); non-recurring cancel directly. Matches the detail pane.
      store.requestCancel(task, undoManager: undoManager)
    } label: {
      Label(
        String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "xmark.circle"
      )
    }
    .disabled(task.status.isResolved)

    Button(role: .destructive) {
      store.selectedTaskID = task.id
      store.requestPermanentDelete(task)
    } label: {
      Label(
        String(localized: "task.permanent_delete.action", defaultValue: "Delete Permanently…", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "trash"
      )
    }
  }
}
