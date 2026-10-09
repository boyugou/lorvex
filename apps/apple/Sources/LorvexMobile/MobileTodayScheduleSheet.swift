import LorvexCore
import SwiftUI

/// The day drawn to its clock: suggested times with their Use and Dismiss
/// controls while the user decides on them, then the day's calendar events and
/// timed tasks in one timeline (``MobileTodayScheduleTimelineSection``),
/// headed "Current Schedule" while a suggestion sits above it. Tasks without a
/// time stay in the Today list only; while today has tasks and none of them is
/// timed, a line says so. iPad keeps the schedule beside Today as a standing
/// pane with its own "Schedule" label and the ⋯ menu
/// (``MobileTodayScheduleMenu``); iPhone shows it in
/// ``MobileTodayScheduleSheet``, which carries the label as its title and the
/// menu in its toolbar.
struct MobileTodayScheduleList: View {
  @Bindable var store: MobileStore
  /// The pane draws the "Schedule" label with the menu beside it; the sheet
  /// leaves both to its navigation bar.
  var showsHeader = true
  var openTask: (LorvexTask) -> Void = { _ in }
  var openEvent: (CalendarTimelineEvent) -> Void = { _ in }

  var body: some View {
    // Per-minute so the now row and a running time follow the clock without a
    // reload, as the Today list beside it does.
    TimelineView(.everyMinute) { _ in
      let rows = store.todaySchedule
      let drawsRows = rows.contains { $0.kind != .now }
      List {
        Group {
          if showsHeader {
            header
          }
          if let proposal = store.proposedDayTimes {
            MobileTodaySuggestedTimesRows(store: store, proposal: proposal, dayRows: rows)
          }
          if drawsRows {
            if store.proposedDayTimes != nil {
              LorvexPageLabel(MobileTodayCalmCopy.currentScheduleTitle)
                .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
                .padding(.top, LorvexDesign.Spacing.m)
            }
            MobileTodayScheduleTimelineSection(
              store: store, items: rows, openTask: openTask, openEvent: openEvent)
          }
          if store.proposedDayTimes == nil, let hint = hint(drawsRows: drawsRows) {
            Text(hint)
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
              .padding(.vertical, LorvexDesign.Spacing.xs)
              .accessibilityIdentifier("today.schedule.hint")
          }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(
          EdgeInsets(
            top: 1, leading: LorvexDesign.Spacing.s, bottom: 1, trailing: LorvexDesign.Spacing.s))
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .reduceMotionAnimation(.snappy(duration: 0.2), value: store.proposedDayTimes)
    }
    .accessibilityIdentifier("today.schedule")
  }

  /// What the schedule says under its rows: that today's tasks have no times
  /// yet, or, with nothing drawn at all, that the day is open.
  private func hint(drawsRows: Bool) -> String? {
    let unfinished = store.snapshot.today.tasks.filter(\.status.isActionable)
    if !unfinished.isEmpty, !unfinished.contains(where: { $0.time(on: store.logicalTodayString) != nil }) {
      return MobileTodayCalmCopy.scheduleUntimedHint
    }
    return drawsRows ? nil : MobileTodayCalmCopy.scheduleEmpty
  }

  private var header: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      LorvexPageLabel(MobileTodayCalmCopy.scheduleTitle)
      // The glyph is 20pt across: 12pt each way makes the target 44pt wide and
      // as tall as the header row's margins allow.
      MobileTodayScheduleMenu(store: store, tapOutset: 12)
    }
    .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
    .padding(.top, LorvexDesign.Spacing.m)
    .padding(.bottom, LorvexDesign.Spacing.xs)
  }
}

/// The schedule's ⋯ menu: Suggest Times, and Clear Times once a task has a
/// time today. Neither is a standing button, so the day itself stays the thing
/// on screen. Draws nothing while today holds no unfinished task, since there
/// is then nothing to time. Clearing asks first: iPhone and iPad have no Edit
/// menu to undo it from.
struct MobileTodayScheduleMenu: View {
  @Bindable var store: MobileStore
  /// How far the tap target reaches past the glyph on every side, without
  /// moving it. A menu in a toolbar leaves this at zero, since the toolbar sizes
  /// its own button; one in a list header, which draws only the glyph, sets it.
  var tapOutset: CGFloat = 0
  @State private var isConfirmingClear = false

  private var unfinishedTasks: [LorvexTask] {
    store.snapshot.today.tasks.filter(\.status.isActionable)
  }

  private var isBusy: Bool {
    store.isSuggestingDayTimes || store.isSavingDayTimes
  }

  var body: some View {
    let tasks = unfinishedTasks
    if !tasks.isEmpty {
      let hasTimedTask = tasks.contains { $0.time(on: store.logicalTodayString) != nil }
      Menu {
        Button {
          Task { await store.suggestDayTimes() }
        } label: {
          Label(
            store.isSuggestingDayTimes
              ? MobileTodayCalmCopy.suggestingTimes : MobileTodayCalmCopy.suggestTimes,
            systemImage: "calendar.badge.clock")
        }
        .disabled(isBusy)
        .accessibilityIdentifier("today.schedule.suggest")

        if hasTimedTask {
          Divider()
          Button(role: .destructive) {
            isConfirmingClear = true
          } label: {
            Label(MobileTodayCalmCopy.clearTimes, systemImage: "xmark.circle")
          }
          .disabled(isBusy)
          .accessibilityIdentifier("today.schedule.clear")
        }
      } label: {
        // The label's padding widens the tap target, and the negative padding
        // outside the menu gives the layout the glyph's own size back.
        Image(systemName: "ellipsis.circle")
          .padding(tapOutset)
          .contentShape(Rectangle())
      }
      .padding(-tapOutset)
      .accessibilityLabel(MobileTodayCalmCopy.scheduleMenuLabel)
      .accessibilityIdentifier("today.schedule.menu")
      .confirmationDialog(
        MobileTodayCalmCopy.clearTimesConfirmTitle, isPresented: $isConfirmingClear,
        titleVisibility: .visible
      ) {
        Button(MobileTodayCalmCopy.clearTimes, role: .destructive) {
          Task { await store.clearDayTimes() }
        }
        Button(MobileTodayCalmCopy.cancel, role: .cancel) {}
      } message: {
        Text(MobileTodayCalmCopy.clearTimesConfirmMessage)
      }
    }
  }
}

/// ``MobileTodayScheduleList`` as a sheet, opened from Today's day strip on
/// iPhone. Opening a task or an event from a row dismisses the sheet first,
/// then hands the item to the page underneath. Closing the sheet dismisses a
/// suggestion still under review, since nothing else on iPhone shows it.
struct MobileTodayScheduleSheet: View {
  @Bindable var store: MobileStore
  var openTask: (LorvexTask) -> Void = { _ in }
  var openEvent: (CalendarTimelineEvent) -> Void = { _ in }
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      MobileTodayScheduleList(
        store: store, showsHeader: false,
        openTask: { task in
          dismiss()
          openTask(task)
        },
        openEvent: { event in
          dismiss()
          openEvent(event)
        }
      )
      .navigationTitle(MobileTodayCalmCopy.scheduleTitle)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .navigation) {
          MobileTodayScheduleMenu(store: store)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(MobileTodayCalmCopy.done) { dismiss() }
            .accessibilityIdentifier("today.schedule.done")
        }
      }
    }
    .mobileCompactEditorSheetPresentation()
    // The list draws no background of its own (it is also the iPad's
    // transparent schedule pane), so at the medium detent the default glass
    // let Today's rows show through behind the schedule's text.
    .presentationBackground(.thickMaterial)
    .onDisappear { store.dismissSuggestedDayTimes() }
  }
}

/// Suggested times the user is deciding on: a caption when no working time is
/// left, the two answers, Use These Times and Dismiss, then the suggestion
/// drawn in the timeline's columns (``LorvexProposedScheduleRows``) so it
/// reads against the day below, and Move to Tomorrow for the tasks that did
/// not fit. The answers stand above the rows so a long suggestion never
/// pushes them off screen; Move to Tomorrow follows the rows, beside the
/// tasks it moves. These are list rows: the schedule list owns the insets and
/// separators.
struct MobileTodaySuggestedTimesRows: View {
  @Bindable var store: MobileStore
  let proposal: DayTimesProposal
  /// The day's timeline, where an event finds its calendar's color.
  let dayRows: [LorvexTodayTimelineItem]

  var body: some View {
    LorvexPageLabel(MobileTodayCalmCopy.suggestionTitle)
      .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
      .padding(.top, LorvexDesign.Spacing.s)
      .accessibilityIdentifier("today.suggestion")

    if proposal.placesNothing {
      Text(MobileTodayCalmCopy.noTimeLeft(workingHours: proposal.workingHours))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
        .padding(.vertical, LorvexDesign.Spacing.xs)
        .accessibilityIdentifier("today.suggestion.noTimeLeft")
    }

    answers
      .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
      .padding(.vertical, LorvexDesign.Spacing.xs)

    LorvexProposedScheduleRows(
      proposal: proposal, dayRows: dayRows, wontFitLabel: MobileTodayCalmCopy.wontFit,
      busyLabel: MobileTodayCalmCopy.busy, durationLabel: { LorvexDurationFormat.minutes($0) })

    // What did not fit has somewhere to go: tomorrow, one tap away, under the
    // rows that say what did not fit.
    if !proposal.unscheduled.isEmpty {
      moveUnscheduled
        .padding(.horizontal, LorvexTimelineMetrics.horizontalPadding)
        .padding(.vertical, LorvexDesign.Spacing.xs)
    }
  }

  private var moveUnscheduled: some View {
    HStack(spacing: 0) {
      Button {
        Task { await store.moveUnscheduledSuggestionToTomorrow() }
      } label: {
        Text(MobileTodayCalmCopy.overbookedAction)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .disabled(store.isSavingDayTimes)
      .accessibilityIdentifier("today.suggestion.moveToTomorrow")
      Spacer(minLength: 0)
    }
  }

  /// Use These Times is the answer the suggestion asks for, so it is the
  /// prominent button; Dismiss stands beside it, bordered, or under it when the
  /// two do not fit on one line at the text size or in the language, each as
  /// wide as the row. Beside each other in a narrow row the capsules would wrap
  /// their words into a blob. Styled buttons each own their tap target inside
  /// the List row, where default-styled ones would make the whole row one
  /// ambiguous button.
  private var answers: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        useButton(fillsWidth: false)
        dismissButton(fillsWidth: false)
        Spacer(minLength: 0)
      }
      VStack(spacing: LorvexDesign.Spacing.s) {
        useButton(fillsWidth: true)
        dismissButton(fillsWidth: true)
      }
    }
    .buttonBorderShape(.capsule)
  }

  @ViewBuilder
  private func useButton(fillsWidth: Bool) -> some View {
    if !proposal.placements.isEmpty {
      Button {
        Task { await store.useSuggestedDayTimes() }
      } label: {
        // Text alone: a list tints a `Label`'s icon with the accent, which
        // would vanish into the prominent button's accent fill.
        Group {
          if store.isSavingDayTimes {
            HStack(spacing: LorvexDesign.Spacing.xs) {
              ProgressView()
                .controlSize(.small)
              Text(MobileTodayCalmCopy.useSuggestion)
            }
          } else {
            Text(MobileTodayCalmCopy.useSuggestion)
          }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
      }
      .buttonStyle(.borderedProminent)
      .disabled(store.isSavingDayTimes)
      .accessibilityIdentifier("today.suggestion.use")
    }
  }

  private func dismissButton(fillsWidth: Bool) -> some View {
    Button(role: .cancel) {
      store.dismissSuggestedDayTimes()
    } label: {
      Text(MobileTodayCalmCopy.dismissSuggestion)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
    }
    .buttonStyle(.bordered)
    .disabled(store.isSavingDayTimes)
    .accessibilityIdentifier("today.suggestion.dismiss")
  }
}
