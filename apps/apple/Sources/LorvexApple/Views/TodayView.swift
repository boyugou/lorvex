import LorvexCore
import SwiftUI

struct TodayView: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) private var undoManager

  var body: some View {
    VStack(spacing: 0) {
      if store.todaySelectionCount > 1 {
        todaySelectionBar
        Divider()
      }
      TimelineView(.everyMinute) { _ in
        let content = store.todayColumnContent
        ScrollViewReader { scroll in
          ScrollView {
            mainColumn(content)
          }
          .workspaceTaskArrowKeyNavigation(
            store.arrowKeyTaskNavigation(on: .today), proxy: scroll)
        }
        .background(alignment: .top) { sky(content.nowMinutes) }
      }
      .cancelSelectedTaskOnDelete(store, on: .today)
      .dropDestination(for: LorvexTaskRef.self) { refs, _ in
        let ids = refs.map(\.id)
        guard !ids.isEmpty else { return false }
        // One batch write for the whole drop, so the dropped tasks land on
        // today together.
        Task { await store.planTasksForToday(ids: ids) }
        return true
      }
    }
    .navigationTitle(String(localized: store.selection.macOSLocalizedTitle))
    .toolbar {
      if hasOpenTasks {
        TodayScheduleToolbar(
          canClear: hasTimedTasks,
          workingHours: store.workdayWindow,
          suggest: { Task { await store.suggestDayTimes() } },
          clear: { Task { await store.clearDayTimes(undoManager: undoManager) } }
        )
      }
    }
    .lorvexOpenDestinationActivity(selection: .today, isActive: store.selection == .today)
    .task {
      async let todaySchedule: Void = store.loadTodaySchedule()
      async let doneCount: Void = store.loadDoneTodayCount()
      await store.loadWorkdayWindow()
      _ = await todaySchedule
      _ = await doneCount
    }
    .onChange(of: store.today) {
      Task { await store.loadDoneTodayCount() }
    }
  }

  private func mainColumn(_ content: TodayColumnContent) -> some View {
    TodayColumn(store: store, content: content)
      .padding(.horizontal, LorvexDesign.Spacing.xl + 16)
      .padding(.top, LorvexDesign.Spacing.xl)
      .padding(.bottom, LorvexDesign.Spacing.xl)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The wash behind the main column. It runs up under the toolbar to the
  /// window's top edge, so the column reads as part of the window rather than
  /// a panel set below a blank band; the toolbar's controls float over it.
  private func sky(_ nowMinutes: Int?) -> some View {
    LorvexSkyWash(nowMinutes: nowMinutes)
      .frame(height: 320)
      .ignoresSafeArea(edges: .top)
  }

  /// Today holds unfinished tasks, so there is something to suggest times for.
  private var hasOpenTasks: Bool {
    today.tasks.contains { $0.status.isActionable }
  }

  /// Some unfinished task on today has a time, so there are times to clear.
  private var hasTimedTasks: Bool {
    today.tasks.contains { $0.status.isActionable && $0.time(on: store.logicalTodayDateString) != nil }
  }

  private var today: TodaySnapshot { store.today }

  /// Batch-action bar shown when more than one Today task is selected: the
  /// complete, defer, move, cancel, and reopen actions over the selection.
  private var todaySelectionBar: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      TodaySelectionActionMenu(store: store)
      Button {
        store.setTodaySelection([])
      } label: {
        Label(
          String(
            localized: "common.clear", defaultValue: "Clear", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "xmark.circle")
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("today.selection.clear")
      Spacer(minLength: 0)
    }
    .controlSize(.small)
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityIdentifier("today.selection.bar")
  }

}

/// A Today task row: the shared selectable row wired to Today's selection
/// surface, with the hover Start and Defer controls.
struct TodayTaskRow: View {
  let task: LorvexTask
  @Bindable var store: AppStore
  /// Marks a row whose dependencies are still open. The row stays interactive —
  /// the user may still want to open it or push it to another day — so this is a
  /// warning, not a disabled state.
  var isBlocked = false
  /// See ``LorvexTaskRow/timeLabel``.
  var timeLabel: String? = nil
  /// See ``LorvexTaskRow/timeIsRunning``.
  var timeIsRunning = false
  /// See ``LorvexTaskRow/chips``.
  var chips: [LorvexTaskRowChip] = []

  private var isBatchSelected: Bool {
    store.todaySelectedTaskIDs.contains(task.id)
  }

  var body: some View {
    WorkspaceSelectableTaskRow(
      task: task,
      store: store,
      selectionSurface: .today,
      isBatchSelected: isBatchSelected,
      batchAccessibilityIdentifier: "today.row.batchSelect.\(task.id)",
      toggleBatchSelection: { store.toggleTodayTaskBatchSelection(task.id) },
      openTask: { store.selectOnlyTodayTask(task.id) },
      isBlocked: isBlocked,
      // Today mixes tasks from every list, so each row shows its owning list.
      showsOwningList: true,
      // Starting and deferring are the day's own verbs, one hover away.
      showsTodayActions: true,
      timeLabel: timeLabel,
      timeIsRunning: timeIsRunning,
      chips: chips
    )
  }
}
