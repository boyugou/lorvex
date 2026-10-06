import LorvexCore
import SwiftUI

// MARK: - Schedule controls

/// The toolbar's Suggest Times control while today has tasks. Suggest Times
/// asks for suggested times, which Today's schedule shows for review; once
/// any of today's tasks has a time, the control is a split button whose menu
/// holds Clear Times, which ⌘Z can undo.
struct TodayScheduleToolbar: ToolbarContent {
  let canClear: Bool
  /// The working window the suggestion fills, named in the tooltip.
  var workingHours: Range<Int>?
  let suggest: () -> Void
  let clear: () -> Void

  var body: some ToolbarContent {
    ToolbarSpacer(.flexible)

    ToolbarItem(placement: .primaryAction) {
      Group {
        if canClear {
          Menu {
            Button(TodayCalmCopy.clearTimes, systemImage: "xmark.circle", action: clear)
              .accessibilityIdentifier("today.schedule.clear")
          } label: {
            label
          } primaryAction: {
            suggest()
          }
        } else {
          Button(action: suggest) { label }
        }
      }
      .help(TodayCalmCopy.suggestTimesHelp(workingHours: workingHours))
      .accessibilityIdentifier("today.schedule.suggest")
    }
  }

  private var label: some View {
    Label(TodayCalmCopy.suggestTimes, systemImage: "calendar.badge.clock")
      .labelStyle(.titleAndIcon)
  }
}

// MARK: - Selection actions

/// The batch-action menu for a multi-task selection on Today: the shared
/// complete, defer, cancel, reopen, Someday, and move actions over
/// `todaySelectedTasks`.
struct TodaySelectionActionMenu: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) private var undoManager

  var body: some View {
    Menu {
      TaskBatchActionMenuContent(
        store: store,
        selectionSurface: .today,
        canActOnSelection: store.todaySelectedTasks.contains { $0.status.isActive },
        canReopenSelection: store.todaySelectedTasks.contains {
          $0.status.isResolved
        },
        canMoveSelectionToSomeday: store.todaySelectedTasks.contains { $0.status == .open },
        complete: { Task { await store.completeTodaySelection() } },
        deferToTomorrow: { Task { await store.deferTodaySelection() } },
        cancel: { Task { await store.cancelTodaySelection() } },
        reopen: { Task { await store.reopenTodaySelection() } },
        moveToSomeday: { Task { await store.markTodaySelectionSomeday() } },
        move: { listID in
          Task { await store.moveTodaySelection(toListID: listID, undoManager: undoManager) }
        }
      )
    } label: {
      Label(
        String(
          localized: "today.selection.count", defaultValue: "\(store.todaySelectionCount) selected",
          table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "checklist.checked"
      )
    }
    .buttonStyle(.bordered)
    .accessibilityIdentifier("today.selection.menu")
  }
}
