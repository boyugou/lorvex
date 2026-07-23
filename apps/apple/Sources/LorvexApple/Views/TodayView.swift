import LorvexCore
import SwiftUI

struct TodayView: View {
  @Bindable var store: AppStore
  /// "HH:MM–HH:MM" window for the propose tooltip; loaded once per appearance.
  @State private var workingHoursText: String?
  @State private var isShowingClearConfirmation = false

  private var todayEmptyState: LorvexEmptyStateModel {
    if store.hasActiveSearch {
      return LorvexEmptyStateModel(
        title: String(
          localized: "today.empty.search_title", defaultValue: "No Results Today",
          table: "Localizable", bundle: LorvexL10n.bundle),
        message: String(
          localized: "today.empty.search_description",
          defaultValue: "No focus or today tasks match the current search.",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "magnifyingglass",
        tint: .secondary,
        chips: [
          LorvexEmptyStateChip(
            title: store.searchText,
            systemImage: "text.magnifyingglass",
            tint: .accentColor
          )
        ],
        action: LorvexEmptyStateAction(
          title: String(
            localized: "common.clear_search", defaultValue: "Clear Search", table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "xmark.circle"
        ) {
          store.searchText = ""
        }
      )
    }

    return LorvexEmptyStateModel(
      title: String(
        localized: "today.empty.no_tasks_title", defaultValue: "No Tasks Today",
        table: "Localizable", bundle: LorvexL10n.bundle),
      message: String(
        localized: "today.empty.no_tasks_description",
        defaultValue: "Capture a task or load a Lorvex database to start planning.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "checklist",
      tint: .accentColor,
      chips: [],
      action: LorvexEmptyStateAction(
        title: AppCommand.newTask.title,
        systemImage: AppCommand.newTask.systemImage,
        style: .primary
      ) {
        store.requestQuickAddFocus()
      }
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      TodayHeaderView(store: store) {
        if focusStats.hasHeaderActions {
          TodayScheduleControls(
            stats: focusStats,
            proposeSchedule: { Task { await store.proposeFocusSchedule() } },
            workingHoursText: workingHoursText,
            saveSchedule: { Task { await store.saveProposedFocusSchedule() } },
            clear: { isShowingClearConfirmation = true }
          )
        }
      }
      Divider()
      if store.focusWorkspaceSelectionCount > 1 {
        todaySelectionBar
        Divider()
      }
      WorkspaceReviewList(taskNavigation: store.arrowKeyTaskNavigation(on: .focus)) {
        QuickAddRow(
          placeholder: String(
            localized: "today.quick_add.placeholder", defaultValue: "Add a task for today",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          isCreating: store.isCreating,
          focusToken: store.quickAddFocusToken
        ) { title in
          await store.createTaskPlannedToday(title: title)
        }
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .padding(.top, LorvexDesign.Spacing.s)

        // Today opens with the day's fixed commitments — the schedule frames the
        // free time the rest of Today fills in. Shown only while no focus
        // timeline exists; once a schedule is proposed/saved these events are
        // folded into it (see `showsStandaloneTodaySchedule`).
        if store.showsStandaloneTodaySchedule {
          TodayScheduleSection(events: store.todayScheduleEvents)
        }

        if let proposed = store.proposedFocusSchedule {
          FocusScheduleSection(
            title: String(
              localized: "focus.workspace.proposed_schedule", defaultValue: "Proposed Schedule",
              table: "Localizable", bundle: LorvexL10n.bundle),
            schedule: proposed
          )
        } else if let schedule = store.focusSchedule {
          FocusScheduleSection(
            title: String(
              localized: "focus.workspace.saved_schedule", defaultValue: "Saved Schedule",
              table: "Localizable", bundle: LorvexL10n.bundle),
            schedule: schedule
          )
        }

        if !store.filteredInProgressTodayTasks.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            WorkspaceTaskSectionHeader(
              title: String(
                localized: "today.section.in_progress", defaultValue: "In Progress",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              count: store.filteredInProgressTodayTasks.count,
              systemImage: "play.fill",
              tint: .accentColor,
              topSpacing: LorvexDesign.Spacing.s
            )
            .padding(.horizontal, LorvexDesign.Spacing.l)

            ForEach(store.filteredInProgressTodayTasks) { task in
              TodayTaskRow(task: task, store: store)
                .padding(.horizontal, LorvexDesign.Spacing.m)
            }
          }
        }

        if !store.filteredFocusedTasks.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            WorkspaceTaskSectionHeader(
              title: String(
                localized: "today.section.focus_plan", defaultValue: "Focus Plan",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              count: store.filteredFocusedTasks.count,
              systemImage: "scope",
              tint: .accentColor,
              topSpacing: store.filteredInProgressTodayTasks.isEmpty
                ? LorvexDesign.Spacing.s : LorvexDesign.Spacing.m
            )
            .padding(.horizontal, LorvexDesign.Spacing.l)

            ForEach(store.filteredFocusedTasks) { task in
              TodayTaskRow(task: task, store: store, isFocused: true)
                .padding(.horizontal, LorvexDesign.Spacing.m)
            }
          }
        }

        if !store.filteredRemainingTodayTasks.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            WorkspaceTaskSectionHeader(
              title: String(
                localized: "today.section.next_up", defaultValue: "Next Up",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              count: store.filteredRemainingTodayTasks.count,
              systemImage: "list.bullet",
              tint: .secondary,
              topSpacing: store.filteredFocusedTasks.isEmpty
                && store.filteredInProgressTodayTasks.isEmpty
                ? LorvexDesign.Spacing.s : LorvexDesign.Spacing.m
            )
            .padding(.horizontal, LorvexDesign.Spacing.l)

            ForEach(store.filteredRemainingTodayTasks) { task in
              TodayTaskRow(task: task, store: store)
                .padding(.horizontal, LorvexDesign.Spacing.m)
            }
          }
        }
      }
      .cancelSelectedTaskOnDelete(store, on: .focus)
      .dropDestination(for: LorvexTaskRef.self) { refs, _ in
        let ids = refs.map(\.id)
        guard !ids.isEmpty else { return false }
        // Batch all dropped IDs into one core call so concurrent single-item
        // addToCurrentFocus Tasks can't overwrite each other's currentFocus result.
        Task { await store.addTasksToCurrentFocus(ids: ids) }
        return true
      }
      .overlay {
        // Show an empty state only when nothing actually renders in the list.
        // `hasVisibleTodayTasks` (not `today.tasks`) is the correct signal: a
        // focused task that isn't due today still renders in the Focus section
        // while `today.tasks` is empty, and a today task that resolves into
        // neither partition leaves both sections empty while `today.tasks` is not.
        if !store.hasVisibleTodayTasks
          && !store.showsStandaloneTodaySchedule
          && store.proposedFocusSchedule == nil
          && store.focusSchedule == nil
        {
          LorvexEmptyStatePanel(model: todayEmptyState)
        }
      }
    }
    .confirmationDialog(
      String(
        localized: "focus.workspace.clear_confirm.title", defaultValue: "Clear current focus plan?",
        table: "Localizable", bundle: LorvexL10n.bundle),
      isPresented: $isShowingClearConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "focus.workspace.clear_confirm.clear", defaultValue: "Clear Focus Plan",
          table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive
      ) {
        Task { await store.clearCurrentFocus() }
      }
      Button(
        String(
          localized: "common.keep", defaultValue: "Keep", table: "Localizable",
          bundle: LorvexL10n.bundle), role: .cancel
      ) {}
    } message: {
      Text(
        String(
          localized: "focus.workspace.clear_confirm.message",
          defaultValue:
            "Removes all \(store.currentFocusTaskCount) tasks from the current focus plan and clears its time-block schedule. The tasks themselves are not deleted.",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
    }
    .navigationTitle(String(localized: store.selection.macOSLocalizedTitle))
    .lorvexOpenDestinationActivity(selection: .today, isActive: store.selection == .today)
    .task {
      async let schedule: Void = store.loadFocusSchedule()
      async let todaySchedule: Void = store.loadTodaySchedule()
      let hours = await store.loadWorkingHoursPreference()
      workingHoursText = "\(hours.start)–\(hours.end)"
      _ = await schedule
      _ = await todaySchedule
    }
  }

  private var focusStats: FocusWorkspaceStats {
    FocusWorkspaceStats(
      canProposeSchedule: store.currentFocusTaskCount > 0,
      canSaveSchedule: store.proposedFocusSchedule != nil
    )
  }

  /// Batch-action bar shown when one or more Today tasks are multi-selected.
  /// Reuses the same selection set and menu as the Focus workspace (Today's rows
  /// toggle into `focusWorkspaceSelectedTaskIDs`), so a selection started here
  /// gets the full complete / defer / move / cancel / reopen / focus actions.
  private var todaySelectionBar: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      FocusSelectionActionMenu(store: store)
      Button {
        store.setFocusWorkspaceSelection([])
      } label: {
        Label(
          String(
            localized: "common.clear", defaultValue: "Clear", table: "Localizable",
            bundle: LorvexL10n.bundle), systemImage: "xmark.circle")
      }
      .buttonStyle(.lorvexNeutral)
      .accessibilityIdentifier("today.selection.clear")
      Spacer(minLength: 0)
    }
    .controlSize(.small)
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityIdentifier("today.selection.bar")
  }

}

private struct TodayTaskRow: View {
  let task: LorvexTask
  @Bindable var store: AppStore
  var isFocused = false

  private var isBatchSelected: Bool {
    store.focusWorkspaceSelectedTaskIDs.contains(task.id)
  }

  var body: some View {
    WorkspaceSelectableTaskRow(
      task: task,
      store: store,
      selectionSurface: .focus,
      isBatchSelected: isBatchSelected,
      batchAccessibilityIdentifier: "today.row.batchSelect.\(task.id)",
      toggleBatchSelection: { store.toggleFocusWorkspaceTaskBatchSelection(task.id) },
      openTask: { store.selectOnlyFocusWorkspaceTask(task.id) },
      isFocused: isFocused,
      // Today mixes tasks from every list, so each row shows its owning list.
      showsOwningList: true,
      // Pushing a task to another day is the dominant inline action on Today.
      showsDeferButton: true
    )
  }
}
