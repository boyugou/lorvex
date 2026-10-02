import LorvexCore
import SwiftUI

/// The top of Today's main column: the day on the clock, under a "Schedule"
/// label. Calendar events and timed tasks share one time-ordered list with a
/// line where the clock sits, so what comes next is answered by reading down.
///
/// A timed task is the same row it is everywhere (``TodayTaskRow``), with its
/// time leading the metadata, so it keeps its circle, hover Start and Defer,
/// selection, and chips; the column's task list below holds only the tasks
/// without a time, so every task appears once. An event row
/// (``TodayEventRow``) puts a bar in its calendar's color where a task has
/// its circle, because an event is not the user's to finish.
///
/// The past rows that open the day (finished meetings and finished tasks,
/// ``LorvexTodayTimeline/earlierFold(_:)``) fold behind an "N earlier" line;
/// an unfinished task whose time passed is never past, so it stays in view.
/// Suggested times the user is deciding on stand above the list, which then
/// reads "Current Schedule".
struct TodayScheduleSection: View {
  @Bindable var store: AppStore
  let rows: [LorvexTodayTimelineItem]
  let nowMinutes: Int?
  /// Today's list entries by task id, for the chips a row carries.
  let items: [LorvexTask.ID: LorvexCalmToday.Item]
  @Environment(\.undoManager) private var undoManager

  @State private var showsPast = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let proposal = store.proposedDayTimes {
        TodaySuggestedTimesSection(
          proposal: proposal, dayRows: rows,
          accept: { Task { await store.acceptSuggestedDayTimes(undoManager: undoManager) } },
          dismiss: { store.dismissSuggestedDayTimes() },
          moveUnscheduledToTomorrow: { Task { await store.moveUnscheduledSuggestionToTomorrow() } }
        )
        .padding(.bottom, LorvexDesign.Spacing.m)
        .transition(.opacity)
      }
      TodayColumnLabel(
        title: store.proposedDayTimes == nil ? TodayCalmCopy.scheduleTitle : TodayCalmCopy.currentScheduleTitle)
      let fold = LorvexTodayTimeline.earlierFold(rows)
      rowViews(rows[..<fold.lowerBound])
      if !fold.isEmpty {
        pastToggle(count: fold.count)
        if showsPast {
          rowViews(rows[fold])
        }
      }
      rowViews(rows[fold.upperBound...])
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.schedule")
  }

  private func rowViews(_ slice: ArraySlice<LorvexTodayTimelineItem>) -> some View {
    ForEach(slice) { row in
      rowView(row)
    }
  }

  @ViewBuilder
  private func rowView(_ row: LorvexTodayTimelineItem) -> some View {
    switch row.kind {
    case .task(let task):
      let isRunning = task.status.isActionable && Self.contains(row, nowMinutes)
      TodayTaskRow(
        task: task, store: store, isBlocked: store.isBlocked(task),
        timeLabel: timeLabel(row, isRunning: isRunning),
        timeIsRunning: isRunning,
        chips: items[task.id].map(TodayColumn.chips(for:)) ?? [])
    case .event(let event):
      TodayEventRow(
        event: event,
        timeLabel: row.startMinutes == nil
          ? TodayCalmCopy.allDay : TodayCalmCopy.timeRange(start: row.startMinutes ?? 0, end: row.endMinutes),
        isPast: row.isPast,
        isSelected: store.selectedCalendarEventID == event.id,
        open: { store.toggleTodayEventSelection(event) })
    case .now:
      TodayNowLine(minutes: row.startMinutes ?? 0)
    }
  }

  /// A running time reads "Until 12:30 PM", since its end is what matters
  /// while it runs; any other time reads as its range.
  private func timeLabel(_ row: LorvexTodayTimelineItem, isRunning: Bool) -> String? {
    guard let start = row.startMinutes else { return nil }
    if isRunning, let end = row.endMinutes { return TodayCalmCopy.untilLabel(end: end) }
    return TodayCalmCopy.timeRange(start: start, end: row.endMinutes)
  }

  private static func contains(_ row: LorvexTodayTimelineItem, _ nowMinutes: Int?) -> Bool {
    guard let nowMinutes, let start = row.startMinutes, let end = row.endMinutes else { return false }
    return (start..<end).contains(nowMinutes)
  }

  private func pastToggle(count: Int) -> some View {
    Button {
      withAnimation(.snappy(duration: 0.18)) { showsPast.toggle() }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.m) {
        LorvexDisclosureChevron(isExpanded: showsPast)
          .imageScale(.small)
          .frame(width: 24)
        Text(
          String(
            localized: "today.schedule.earlier_count", defaultValue: "\(count) earlier",
            table: "Localizable", bundle: LorvexL10n.bundle))
        Spacer(minLength: 0)
      }
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.secondary)
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.vertical, LorvexDesign.Spacing.xs)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("today.schedule.earlier.toggle")
  }
}

/// A calendar event in Today's schedule, laid out like a task row: a bar in
/// the calendar's color where a task has its circle, the title, and the time
/// with the location under it. A past event quiets its title and fades its
/// bar.
///
/// Clicking the row opens the event's detail in the inspector, as clicking a
/// task row opens the task's; clicking it again, or Return or Space while it
/// has focus, toggles it the same way. The open event's row carries the
/// selection fill a selected task row does.
struct TodayEventRow: View {
  let event: CalendarTimelineEvent
  let timeLabel: String
  let isPast: Bool
  var isSelected = false
  var open: () -> Void = {}

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      Capsule()
        .fill(Color(lorvexHex: event.color) ?? LorvexDesign.Palette.neutral)
        .frame(width: 4, height: 18)
        .opacity(isPast ? LorvexDesign.Palette.pastMarkOpacity : 1)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(userContent: event.title)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(isPast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .lineLimit(2)
        HStack(spacing: LorvexDesign.Spacing.sm) {
          HStack(spacing: LorvexDesign.Spacing.xxs) {
            Image(systemName: "clock").accessibilityHidden(true)
            Text(timeLabel).monospacedDigit()
          }
          if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
            !location.isEmpty
          {
            Text("·").foregroundStyle(.tertiary)
            Text(location).lineLimit(1)
          }
        }
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: LorvexDesign.Spacing.s)
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
          .fill(LorvexDesign.Palette.selectionFill)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: open)
    .focusable(true)
    .onKeyPress(.return) {
      open()
      return .handled
    }
    .onKeyPress(.space) {
      open()
      return .handled
    }
    .reduceMotionAnimation(.snappy(duration: 0.16), value: isSelected)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityAction(.default, open)
    .accessibilityIdentifier("today.schedule.event.\(event.id)")
  }
}

/// Where the clock sits in Today's schedule: a dot in the circle column, the
/// time, and a rule across the column, in the now color.
struct TodayNowLine: View {
  let minutes: Int

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Circle()
        .fill(LorvexDesign.Palette.nowIndicator)
        .frame(width: 8, height: 8)
        .frame(width: 24)
      HStack(spacing: LorvexDesign.Spacing.s) {
        Text(lorvexClockTimeLabel(minutes: minutes))
          .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.semibold))
          .foregroundStyle(LorvexDesign.Palette.nowIndicator)
        Rectangle()
          .fill(LorvexDesign.Palette.nowIndicator)
          .frame(height: 1)
      }
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      String(
        localized: "today.schedule.now.a11y", defaultValue: "Current time", table: "Localizable",
        bundle: LorvexL10n.bundle))
    .accessibilityValue(lorvexClockTimeLabel(minutes: minutes))
    .accessibilityIdentifier("today.schedule.now")
  }
}

/// A section label in Today's main column ("Schedule", "Tasks"), inset to
/// line up with the rows' circles.
struct TodayColumnLabel: View {
  let title: String

  var body: some View {
    LorvexPageLabel(title)
      .padding(.horizontal, LorvexDesign.Spacing.s)
      .padding(.bottom, LorvexDesign.Spacing.xxs)
  }
}
