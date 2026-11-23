import LorvexCore
import SwiftUI

/// The Today workspace: the day's column and, in a main window wide enough,
/// the day on a time grid in a rail beside it (``TodayPageLayout``).
///
/// This view resolves the layout and owns the window's title, toolbar and
/// loading; ``TodayPage`` draws the page for the layout it is given.
struct TodayView: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) private var undoManager
  /// The main window's layout, which knows the width right of the sidebar
  /// with the inspector's share included; nil in a Today window of its own.
  @Environment(MainWindowLayout.self) private var windowLayout: MainWindowLayout?
  @Environment(\.controlActiveState) private var controlActiveState
  /// The placement the page last had, which it keeps while the inspector is
  /// open (``TodayPageLayout``).
  @State private var placementBeforeInspector: TodaySchedulePlacement?

  var body: some View {
    GeometryReader { geometry in
      let resolved = pageLayout(viewWidth: geometry.size.width)
      let layout = resolved ?? .columnOnly
      TodayPage(store: store, layout: layout)
        // The store orders the arrow keys and range selection by the rows the
        // column draws, which depend on where the schedule stands.
        .onChange(of: resolved?.schedulePlacement, initial: true) { _, placement in
          guard let placement else { return }
          placementBeforeInspector = placement
          store.todaySchedulePlacement = placement
        }
        // Today can be open in the main window and in a window of its own,
        // which place the schedule differently and share the store. The keys
        // go to the key window, so its rows are the ones they follow.
        .onChange(of: controlActiveState) { _, state in
          if state == .key { store.todaySchedulePlacement = layout.schedulePlacement }
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
    // The Done section lists tasks outside Today's own list, so it reloads
    // whenever task data does, not only when Today's list changes.
    .onChange(of: store.today) {
      Task { await store.loadDoneTodayCount() }
    }
    .onChange(of: store.taskDataGeneration) {
      Task { await store.loadDoneTodayCount() }
    }
  }

  /// The page's layout, or nil before the window has a width to divide.
  ///
  /// A Today window of its own keeps the schedule in the column at any width:
  /// it has no inspector and no event sheet for a rail's blocks to open in.
  private func pageLayout(viewWidth: CGFloat) -> TodayPageLayout? {
    guard let windowLayout else { return .columnOnly }
    let inspectorOpen = store.isMainInspectorOpen
    let areaWidth: CGFloat
    if let measured = windowLayout.detailAreaWidth {
      areaWidth = measured
    } else if viewWidth > 0 {
      // Before the window reports its width, the page's own width stands in
      // for it, with the share an open inspector has taken added back.
      areaWidth = viewWidth + (inspectorOpen ? MainWindowLayoutMetrics.inspectorIdealWidth : 0)
    } else {
      return nil
    }
    return TodayPageLayout.resolve(
      areaWidth: areaWidth, inspectorOpen: inspectorOpen,
      placementBeforeInspector: placementBeforeInspector)
  }

  /// Today holds unfinished tasks, so there is something to suggest times for.
  private var hasOpenTasks: Bool {
    store.today.tasks.contains { $0.status.isActionable }
  }

  /// Some unfinished task on today has a time, so there are times to clear.
  private var hasTimedTasks: Bool {
    store.today.tasks.contains {
      $0.status.isActionable && $0.time(on: store.logicalTodayDateString) != nil
    }
  }
}

/// Today's page drawn for one layout: the selection bar, the column, and the
/// day rail.
///
/// It is a view of its own so that resizing the window, which changes the
/// width ``TodayView`` reads on every frame, redraws the page only when the
/// layout that width resolves to changes.
private struct TodayPage: View {
  @Bindable var store: AppStore
  let layout: TodayPageLayout

  var body: some View {
    VStack(spacing: 0) {
      if store.todaySelectionCount > 1 {
        todaySelectionBar
        Divider()
      }
      TimelineView(.everyMinute) { tick in
        let content = store.todayColumnContent(at: tick.date, placement: layout.schedulePlacement)
        HStack(spacing: 0) {
          ScrollViewReader { scroll in
            ScrollView {
              mainColumn(content)
            }
            .workspaceTaskArrowKeyNavigation(
              store.arrowKeyTaskNavigation(on: .today), proxy: scroll)
          }
          // On the column alone: a task dropped on the rail takes the time it
          // lands on, which the rail's grid handles itself.
          .dropDestination(for: LorvexTaskRef.self) { refs, _ in
            let ids = refs.droppedTaskIDs
            guard !ids.isEmpty else { return false }
            // One batch write for the whole drop, so the dropped tasks land on
            // today together.
            Task { await store.planTasksForToday(ids: ids) }
            return true
          }
          if let railWidth = layout.railWidth {
            rail(width: railWidth)
          }
        }
        .background(alignment: .top) { sky(content.nowMinutes) }
      }
      .cancelSelectedTaskOnDelete(store, on: .today)
      .copySelectedTasksAsText(store, on: .today)
      .selectAllTasksOnCommand(store, on: .today)
    }
    .reduceMotionAnimation(.snappy(duration: 0.18), value: layout.showsRail)
  }

  /// The day's column. Its date line is Today's title, so the column insets by
  /// the amount every other workspace's title does
  /// (``WorkspaceHeaderTitleMetrics/titleInset``) and the title stays on one
  /// edge when the user switches workspaces. Beside the rail its trailing
  /// inset is the smaller one a divider needs.
  private func mainColumn(_ content: TodayColumnContent) -> some View {
    TodayColumn(store: store, content: content)
      .padding(.leading, TodayPageMetrics.columnLeadingInset)
      .padding(
        .trailing,
        content.schedulePlacement == .besideColumn
          ? TodayPageMetrics.columnTrailingInsetBesideRail : TodayPageMetrics.columnLeadingInset
      )
      .padding(.top, LorvexDesign.Spacing.xl)
      .padding(.bottom, LorvexDesign.Spacing.xl)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The day rail and the divider before it.
  ///
  /// While the inspector stands in the rail's place, the rail stays in the
  /// page at its own width and is given none of the page's: it is not drawn
  /// and takes no clicks, drops or keyboard focus, and its time axis is where
  /// the person left it when the inspector closes.
  @ViewBuilder
  private func rail(width: CGFloat) -> some View {
    let isShown = layout.showsRail
    if isShown { Divider() }
    TodayDayRail(store: store)
      .frame(width: width)
      .frame(width: isShown ? width : 0, alignment: .leading)
      .clipped()
      .opacity(isShown ? 1 : 0)
      .allowsHitTesting(isShown)
      .disabled(!isShown)
      .accessibilityHidden(!isShown)
      .transition(.opacity)
  }

  /// The wash behind the page, under the column and the rail alike. It runs
  /// up under the toolbar to the window's top edge, so the column reads as
  /// part of the window rather than a panel set below a blank band; the
  /// toolbar's controls float over it.
  private func sky(_ nowMinutes: Int?) -> some View {
    LorvexSkyWash(nowMinutes: nowMinutes)
      .frame(height: 320)
      .ignoresSafeArea(edges: .top)
  }

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

  var workCue: TodayWorkCue? = nil

  private var isBatchSelected: Bool {
    store.todaySelectedTaskIDs.contains(task.id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
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
        showsRowStart: workCue == nil || task.status == .inProgress,
        timeLabel: timeLabel,
        timeIsRunning: timeIsRunning,
        chips: chips
      )
      .environment(\.lorvexTaskRowDay, store.logicalTodayDateString)
      if let workCue {
        TodayWorkActionLine(store: store, task: task, cue: workCue)
      }
    }
  }
}
