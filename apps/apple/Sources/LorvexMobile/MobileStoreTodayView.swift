import LorvexCore
import SwiftUI

enum MobileTodayTaskSections {
  static func todayTasks(from snapshot: MobileHomeSnapshot) -> [LorvexTask] {
    guard let nextID = snapshot.nextTask?.id else { return snapshot.todayTasks }
    return snapshot.todayTasks.filter { $0.id != nextID }
  }

  /// The capture-oriented empty state is truthful only when Today has no work
  /// at all. A started task lives in the separate uncapped in-progress lane, so
  /// an empty open-task lane must not invite someone who is already working to
  /// "get started."
  static func showsOpenTaskEmptyState(for snapshot: MobileHomeSnapshot) -> Bool {
    snapshot.todayTasks.isEmpty && snapshot.inProgressTasks.isEmpty
  }
}

struct MobileStoreTodayView: View {
  @Bindable var store: MobileStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var isShowingCreateEvent = false
  @State private var editingHabit: LorvexHabit?
  @State private var editingCalendarEvent: CalendarTimelineEvent?
  /// Owned here, not in the focus section, so the clear-confirmation dialog
  /// attaches to the stable `List` rather than the focus section's conditionally
  /// rendered `Section` (which would not reliably present).
  @State private var isConfirmingFocusClear = false

  var body: some View {
    content
      // Owned at the shell level (not inside either layout) so it attaches to a
      // stable view and presents reliably from both the compact focus Section and
      // the regular focus card.
      .confirmationDialog(
        String(
          localized: "focus.schedule.clearConfirm.title", defaultValue: "Clear focus plan?",
          table: "Localizable", bundle: MobileL10n.bundle),
        isPresented: $isConfirmingFocusClear,
        titleVisibility: .visible
      ) {
        Button(
          String(
            localized: "focus.schedule.clearConfirm.clear", defaultValue: "Clear Focus Plan",
            table: "Localizable", bundle: MobileL10n.bundle),
          role: .destructive
        ) {
          Task { await store.clearCurrentFocus() }
        }
        Button(
          String(
            localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
            bundle: MobileL10n.bundle), role: .cancel
        ) {}
      } message: {
        Text(
          String(
            localized: "focus.schedule.clearConfirm.message",
            defaultValue:
              "This removes today's focus membership and time-block schedule. Tasks are not deleted.",
            table: "Localizable", bundle: MobileL10n.bundle))
      }
  }

  /// iPhone fills with a `List`; iPad / visionOS (regular width) uses a centered
  /// readable column of cards (`List` can't be width-constrained on iPadOS).
  @ViewBuilder
  private var content: some View {
    if horizontalSizeClass == .regular {
      MobileStoreTodayRegularView(store: store, isConfirmingClear: $isConfirmingFocusClear)
    } else {
      compactBody
    }
  }

  /// Today's events, filtered out of the loaded timeline window to the current
  /// day and agenda-ordered (Lorvex-owned plus mirrored EventKit events).
  private var todayEvents: [CalendarTimelineEvent] {
    store.calendarTimeline?.eventsOccurring(on: store.logicalTodayString) ?? []
  }

  /// A focus time-block timeline is on screen (proposed or saved). When true the
  /// schedule's events are woven into it, so the standalone agenda steps aside.
  private var hasFocusTimeline: Bool {
    store.proposedFocusSchedule != nil || store.focusSchedule != nil
  }

  /// Show the standalone schedule agenda at the top of Today: there are events
  /// today and no focus timeline is folding them in.
  private var showsStandaloneSchedule: Bool {
    !hasFocusTimeline && !todayEvents.isEmpty
  }

  private var compactBody: some View {
    List {
      // Today opens with the day's fixed commitments — the schedule frames the
      // free hours the rest of Today fills in. Shown only while no focus
      // timeline exists; once a schedule is proposed/saved these same events are
      // woven into the focus timeline below instead of listed twice.
      if showsStandaloneSchedule {
        MobileStoreCalendarSection(
          events: todayEvents,
          isMutating: store.isMutatingCalendarEvent,
          isExporting: store.isExportingCalendarICS,
          displayLimit: 5,
          title: String(
            localized: "today.section.schedule", defaultValue: "Schedule", table: "Localizable",
            bundle: MobileL10n.bundle),
          hidesEventDate: true,
          createEvent: { isShowingCreateEvent = true },
          editEvent: {
            store.prepareCalendarDraft(for: $0)
            editingCalendarEvent = $0
          },
          deleteEvent: { event in
            if event.supportsScopedMutation {
              store.prepareCalendarDraft(for: event)
              editingCalendarEvent = event
              return false
            }
            return await store.deleteCalendarEvent(event)
          },
          deleteScopedEvent: { await store.deleteScopedCalendarEvent($0, scope: $1) },
          exportICS: { await store.exportCalendarICS() },
          viewAll: { store.openPrimaryShortcutTab(.calendar) },
          showsActions: false
        )
      }

      MobileStoreFocusScheduleSection(store: store, isConfirmingClear: $isConfirmingFocusClear)

      // Started work pinned at the top, so what you're mid-way through is the
      // first thing you resume. These rows do not repeat in the list below.
      if !store.snapshot.inProgressTasks.isEmpty {
        Section {
          ForEach(store.snapshot.inProgressTasks) { task in
            MobileActionTaskRow(
              task: task,
              isFocused: store.taskIsFocused(task.id),
              isMutating: store.taskIsMutating(task.id),
              select: { store.selectTask(task.id) },
              toggleFocus: { await store.toggleTaskFocus(task.id) },
              complete: { await store.completeTask(task.id) },
              deferTask: { await store.deferTaskToTomorrow(task.id) },
              start: { await store.startTask(task.id) },
              markNotStarted: { await store.markTaskNotStarted(task.id) }
            )
          }
        } header: {
          Text(
            String(
              localized: "today.section.in_progress", defaultValue: "In Progress",
              table: "Localizable", bundle: MobileL10n.bundle))
        }
      }

      // One unified task list in canonical order (most-urgent first).
      if MobileTodayTaskSections.showsOpenTaskEmptyState(for: store.snapshot) {
        Section { MobileStoreTaskEmptyState(store: store) }
      } else if !store.snapshot.todayTasks.isEmpty {
        Section {
          ForEach(store.snapshot.todayTasks) { task in
            MobileActionTaskRow(
              task: task,
              isFocused: store.taskIsFocused(task.id),
              isMutating: store.taskIsMutating(task.id),
              select: { store.selectTask(task.id) },
              toggleFocus: { await store.toggleTaskFocus(task.id) },
              complete: { await store.completeTask(task.id) },
              deferTask: { await store.deferTaskToTomorrow(task.id) },
              start: { await store.startTask(task.id) },
              markNotStarted: { await store.markTaskNotStarted(task.id) }
            )
          }
        }
      }

      // Today is a view of *the day*, not a portal to every surface. Lists live
      // in their own destination — they were a feature-dump here. Habits appear
      // only when there's something to show, so a clear day reads as one calm
      // composed state instead of a stack of empty sections. Today's events ride
      // at the top as the Schedule agenda, not here.
      if let habits = store.habits?.habits, !habits.isEmpty {
        MobileStoreHabitsSection(
          habits: habits,
          isMutating: store.isMutatingHabit || store.isDeletingHabit,
          editHabit: {
            store.prepareHabitDraft(for: $0)
            editingHabit = $0
          },
          deleteHabit: { await store.deleteHabit($0) },
          complete: { await store.completeHabit($0) },
          reset: { await store.uncompleteHabit($0) },
          displayLimit: 4,
          viewAll: { store.openMoreDestination(.habits) }
        )
      }
    }
    .refreshable { await store.refreshResettingCloudSyncPacing() }
    .toolbar {
      if horizontalSizeClass != .regular {
        Button {
          store.isPresentingCapture = true
        } label: {
          Label(
            String(
              localized: "today.capture", defaultValue: "Capture", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "plus.circle")
        }
        .lorvexToolbarHoverEffect()
        .accessibilityIdentifier("today.toolbar.capture")
      }
    }
    .lorvexSpatialContainerPadding()
    .lorvexBottomOrnament {
      Button {
        store.isPresentingCapture = true
      } label: {
        Label(
          String(
            localized: "today.capture", defaultValue: "Capture", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus.circle")
      }
      .buttonStyle(.bordered)
      .lorvexToolbarHoverEffect()
    }
    .sheet(item: $editingHabit) { habit in
      MobileStoreEditHabitSheet(
        habit: habit,
        store: store,
        isPresented: Binding(
          get: { editingHabit != nil },
          set: { if !$0 { editingHabit = nil } }
        )
      )
      .lorvexSpatialBackground()
    }
    .sheet(isPresented: $isShowingCreateEvent) {
      MobileStoreCreateCalendarEventSheet(store: store, isPresented: $isShowingCreateEvent)
        .lorvexSpatialBackground()
    }
    .sheet(item: $editingCalendarEvent) { event in
      MobileStoreEditCalendarEventSheet(
        event: event,
        store: store,
        isPresented: Binding(
          get: { editingCalendarEvent != nil },
          set: { if !$0 { editingCalendarEvent = nil } }
        )
      )
      .lorvexSpatialBackground()
    }
  }
}
