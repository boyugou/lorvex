import LorvexCore
import SwiftUI

extension CalendarWeekGridView {
  // MARK: Header

  func header(_ columns: [CalendarGridDay]) -> some View {
    let load = weekLoad(columns)
    return HStack(spacing: 0) {
      // Fixed-width *and* fixed-height spacer: a bare `Color.clear.frame(width:)`
      // stays vertically greedy, so the header HStack would compete with the
      // scrollable time grid for slack height and balloon into a tall band with
      // the day numbers floating in its centre. Pinning the gutter height (and
      // the whole row via `fixedSize` below) keeps the header content-sized.
      Color.clear.frame(width: gutterWidth, height: CalendarWeekGridMetrics.headerGutterHeight)
      ForEach(Array(columns.enumerated()), id: \.element.id) { index, day in
        let loadDay = load.days.indices.contains(index) ? load.days[index] : nil
        let caption = loadDay.flatMap(CalendarWeekDayLoadCaption.init)
        // A day the week has left behind steps back: its number takes the
        // secondary style its weekday and caption already have. The column
        // never fades as a whole, which would put its words under 2.5:1.
        let isPast = loadDay?.isPast == true
        VStack(spacing: LorvexDesign.Spacing.xxs) {
          Text(LorvexDateFormatters.string(day.date, template: "EEE", timeZone: calendar.timeZone))
            .textCase(.uppercase)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
          Text(LorvexDateFormatters.dayNumber(day.date, timeZone: calendar.timeZone))
            .font(LorvexDesign.Typography.primaryEmphasis)
            .foregroundStyle(
              isToday(day.date) ? AnyShapeStyle(.tint) : isPast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .frame(width: CalendarWeekGridMetrics.dayNumberSize, height: CalendarWeekGridMetrics.dayNumberSize)
            .background {
              if isToday(day.date) {
                Circle().fill(.tint.opacity(0.15))
              }
            }
          CalendarWeekDayLoadLine(caption: caption, isPast: isPast)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          "\(headerAccessibilityLabel(day.date)), \(caption?.sentence ?? CalendarWeekDayLoadCaption.nothingPlanned)")
        .accessibilityAddTraits(.isHeader)
      }
    }
    .padding(.vertical, CalendarWeekGridMetrics.headerVerticalPadding)
    .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: Day grouping

  /// One day's column of the all-day strip as an accessibility container named
  /// by its day, so VoiceOver reads one day's pills before the next day's and
  /// says which day they belong to. A day with nothing in `column` is hidden,
  /// so it is no stop. A single-day grid needs no grouping: its header already
  /// names the day.
  @ViewBuilder
  func groupedByDay<Column: View>(
    _ column: Column, day: CalendarGridDay, totalDays: Int, isEmpty: Bool
  ) -> some View {
    if totalDays > 1 {
      column
        .accessibilityElement(children: .contain)
        .accessibilityLabel(headerAccessibilityLabel(day.date))
        .accessibilityHidden(isEmpty)
    } else {
      column
    }
  }

  /// The sort priority VoiceOver orders the grid's blocks by, higher first: an
  /// earlier day reads before a later one, and within a day the block that
  /// starts earliest reads first; blocks that start together keep the grid's
  /// own order. Events and task blocks share one scale, so the week reads day
  /// by day in time order whatever each block is. The day columns are not
  /// containers, so the priorities order every block of the grid at once.
  static func accessibilitySortPriority(dayIndex: Int, totalDays: Int, startMinutes: Int) -> Double {
    Double((totalDays - dayIndex) * 2 * 24 * 60 + 24 * 60 - startMinutes)
  }

  /// `label` for a block of the grid, followed by its day when the grid shows
  /// more than one, since its column header is not beside it for VoiceOver.
  func blockAccessibilityLabel(_ label: String, on day: CalendarGridDay, totalDays: Int) -> String {
    totalDays > 1 ? "\(label), \(headerAccessibilityLabel(day.date))" : label
  }

  // MARK: All-day strip

  func allDayStrip(_ columns: [CalendarGridDay]) -> some View {
    let hasContent = columns.contains {
      !$0.allDayEvents.isEmpty || !$0.scheduledTasks.isEmpty
    }
    return HStack(alignment: .top, spacing: 0) {
      Text(LocalizedStringResource("calendar.all_day_strip", defaultValue: "all-day", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
        // A label that wraps in the gutter keeps each line against the hour
        // labels' trailing edge.
        .multilineTextAlignment(.trailing)
        .frame(width: gutterWidth, alignment: .trailing)
        .padding(.trailing, LorvexDesign.Spacing.sm)
      ForEach(columns) { day in
        groupedByDay(
          allDayColumn(day), day: day, totalDays: columns.count,
          isEmpty: day.allDayEvents.isEmpty && day.scheduledTasks.isEmpty)
      }
    }
    .padding(.vertical, hasContent ? CalendarWeekGridMetrics.allDayStripContentPadding : CalendarWeekGridMetrics.allDayStripEmptyPadding)
    .frame(minHeight: CalendarWeekGridMetrics.allDayStripMinHeight)
    // Size to content so the strip never competes with the scrollable grid for
    // slack height (see the header note).
    .fixedSize(horizontal: false, vertical: true)
  }

  /// One day's stack in the all-day strip: event pills, then task pills. Task
  /// pills are draggable by id and every column is a drop target, so a task
  /// can be re-planned onto another day without opening it. The stack
  /// is capped at ``CalendarWeekGridMetrics/allDayMaxItems``; anything past the
  /// cap collapses into a "+N more" overflow pill so a busy day can't grow the
  /// strip without bound.
  func allDayColumn(_ day: CalendarGridDay) -> some View {
    let layout = allDayLayout(for: day)
    return VStack(spacing: LorvexDesign.Spacing.xxs) {
      ForEach(layout.events) { event in
        allDayEventPill(event, on: day)
      }
      ForEach(layout.tasks) { task in
        allDayTaskPill(task, on: day)
      }
      if !layout.hiddenEvents.isEmpty || !layout.hiddenTasks.isEmpty {
        allDayOverflowPill(day: day, hidden: layout.hiddenEvents, hiddenTasks: layout.hiddenTasks)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, LorvexDesign.Spacing.xxs)
    .frame(minHeight: CalendarWeekGridMetrics.allDayStripMinHeight, alignment: .top)
    .contentShape(Rectangle())
    .background {
      if dropTargetedDay == day.date {
        RoundedRectangle(cornerRadius: LorvexDesign.Radius.s).fill(.tint.opacity(0.14))
      }
    }
    // Typed `LorvexTaskRef` (not a raw `String`) so the all-day strip accepts
    // task drags from every other surface and arbitrary dropped text can't plan
    // a task. A task dropped here takes the day and no time; one that had a time
    // gives it up.
    .dropDestination(for: LorvexTaskRef.self) { refs, _ in
      let ids = refs.droppedTaskIDs
      guard !ids.isEmpty else { return false }
      Task {
        await store.planTasks(ids: ids, on: day.date, time: .dayOnly, undoManager: undoManager)
      }
      return true
    } isTargeted: { targeted in
      dropTargetedDay = targeted ? day.date : (dropTargetedDay == day.date ? nil : dropTargetedDay)
    }
  }

  /// The bounded slices for one column: the events + tasks that fit under the
  /// per-column cap, and the ones that spill into the overflow pill. When the
  /// column overflows, one visible slot is reserved for the "+N" pill itself.
  private func allDayLayout(for day: CalendarGridDay) -> (
    events: [CalendarTimelineEvent], tasks: [LorvexTask],
    hiddenEvents: [CalendarTimelineEvent], hiddenTasks: [LorvexTask]
  ) {
    let total = day.allDayEvents.count + day.scheduledTasks.count
    guard total > CalendarWeekGridMetrics.allDayMaxItems else {
      return (day.allDayEvents, day.scheduledTasks, [], [])
    }
    let cap = max(0, CalendarWeekGridMetrics.allDayMaxItems - 1)
    let events = Array(day.allDayEvents.prefix(cap))
    let tasks = Array(day.scheduledTasks.prefix(max(0, cap - events.count)))
    return (
      events, tasks,
      Array(day.allDayEvents.dropFirst(events.count)),
      Array(day.scheduledTasks.dropFirst(tasks.count)))
  }

  /// An event's pill: its title, followed by its start on the day a timed
  /// event of a day or more starts and by its end on the day it ends.
  private func allDayEventPill(_ event: CalendarTimelineEvent, on day: CalendarGridDay) -> some View {
    allDayPill(title: event.title, time: event.pillTimeLabel(on: day.dayKey), color: eventColor(event))
      .onTapGesture { selectEvent(event) }
      .calendarPointingHandCursor()
      .accessibilityElement(children: .ignore)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(calendarPillAccessibilityLabel(event))
      .accessibilityAction { selectEvent(event) }
  }

  /// A task in the all-day strip speaks the timed blocks' task vocabulary,
  /// never an event pill's fill and rail: a leading circle that completes it,
  /// on the calendar task surface. A finished task stays, struck through and
  /// faded, as the day's record. A task past its due day ends with the
  /// overdue clock Today's rows use, since the circle's tint already speaks
  /// for priority. The pill opens the task.
  private func allDayTaskPill(_ task: LorvexTask, on day: CalendarGridDay) -> some View {
    let isDone = task.status == .completed
    let isOverdue = task.isOverdue(now: LorvexPreviewClock.now(in: calendar), timeZone: calendar.timeZone)
    return HStack(spacing: 3) {
      taskCompletionCircle(for: task)
        .accessibilityIdentifier("calendar.allDay.task.complete")
      Text(task.title)
        .font(LorvexDesign.Typography.tertiaryText)
        .strikethrough(isDone)
        .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      if isOverdue {
        Image(systemName: "clock.badge.exclamationmark")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(LorvexDesign.Palette.overdue)
          .accessibilityHidden(true)
      }
    }
    .padding(.leading, 3)
    .padding(.trailing, LorvexDesign.Spacing.sm)
    .padding(.vertical, LorvexDesign.Spacing.xxs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lorvexCalendarTaskSurface(isDone: isDone, cornerRadius: LorvexDesign.Radius.s)
    .contentShape(Rectangle())
    .onTapGesture { openTask(task) }
    .calendarPointingHandCursor()
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
    // Pointer-free counterpart to drag-to-reschedule: the same moves,
    // reachable through the context menu / VoiceOver actions rotor.
    .contextMenu {
      Button(
        String(localized: "calendar.task.open", defaultValue: "Open Task", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "arrow.up.forward.square"
      ) { openTask(task) }
      Button(
        taskCompletionLabel(isDone: isDone),
        systemImage: isDone ? "arrow.uturn.backward.circle" : "checkmark.circle"
      ) { toggleCompletion(of: task) }
      Divider()
      planLaterButtons(for: task, from: day.date)
    }
    // One stop per pill: the circle would otherwise read the pill's label too.
    // Opening the task is the default action and completing it a named one.
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(
      String(
        format: String(
          localized: "calendar.scheduled_task.a11y",
          defaultValue: "Scheduled task %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        task.title))
    .accessibilityValue(
      isOverdue
        ? String(localized: "task_detail.pill.overdue", defaultValue: "Overdue", table: "Localizable", bundle: LorvexL10n.bundle)
        : "")
    .accessibilityAction { openTask(task) }
    .accessibilityAction(named: taskCompletionLabel(isDone: isDone)) { toggleCompletion(of: task) }
  }

  /// The "+N more" pill capping a busy all-day column. Opens a popover listing
  /// the hidden events and tasks, each still tappable to open.
  private func allDayOverflowPill(
    day: CalendarGridDay, hidden: [CalendarTimelineEvent], hiddenTasks: [LorvexTask]
  ) -> some View {
    let count = hidden.count + hiddenTasks.count
    return Button {
      allDayOverflowDayID = day.id
    } label: {
      Text("+\(count)")
        .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, LorvexDesign.Spacing.sm)
        .padding(.vertical, LorvexDesign.Spacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      String(
        localized: "calendar.all_day.more.a11y", defaultValue: "\(count) more all-day items",
        table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("calendar.allDay.overflow")
    .popover(
      isPresented: Binding(
        get: { allDayOverflowDayID == day.id },
        set: { if !$0 { allDayOverflowDayID = nil } })
    ) {
      allDayOverflowPopover(day: day, events: hidden, tasks: hiddenTasks)
    }
  }

  private func allDayOverflowPopover(
    day: CalendarGridDay, events: [CalendarTimelineEvent], tasks: [LorvexTask]
  ) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      Text(LocalizedStringResource("calendar.all_day.overflow.title", defaultValue: "All-day", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.primaryEmphasis)
      ForEach(events) { event in
        overflowRow(title: event.title, color: eventColor(event)) {
          allDayOverflowDayID = nil
          selectEvent(event)
        }
      }
      ForEach(tasks) { task in
        overflowRow(title: task.title, color: LorvexDesign.Palette.accent) {
          allDayOverflowDayID = nil
          openTask(task)
        }
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: 240, alignment: .leading)
  }

  private func overflowRow(title: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Circle().fill(color).frame(width: 8, height: 8)
        Text(title)
          .font(LorvexDesign.Typography.secondaryText)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// The context-menu items that plan `task` a day or a week after `day`, the
  /// pointer-free counterpart of dragging it to another column. The task keeps
  /// its own time, if it has one.
  @ViewBuilder
  func planLaterButtons(for task: LorvexTask, from day: Date) -> some View {
    Button(
      String(
        localized: "calendar.task.plan_day_later", defaultValue: "Plan a Day Later",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      systemImage: "arrow.forward"
    ) {
      plan(task, byDays: 1, from: day)
    }
    Button(
      String(
        localized: "calendar.task.plan_week_later", defaultValue: "Plan a Week Later",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      systemImage: "arrow.forward.to.line"
    ) {
      plan(task, byDays: 7, from: day)
    }
  }

  private func plan(_ task: LorvexTask, byDays days: Int, from day: Date) {
    guard let target = calendar.date(byAdding: .day, value: days, to: day) else { return }
    Task {
      await store.planTasks(
        ids: [task.id], on: target, time: .unchanged, undoManager: undoManager)
    }
  }

  /// An event's pill in the all-day strip: the title, followed by `time`
  /// where the width allows (``LorvexCalendarStripLabel``).
  func allDayPill(title: String, time: String?, color: Color) -> some View {
    LorvexCalendarStripLabel(title: title, time: time)
      .font(LorvexDesign.Typography.tertiaryText)
      .padding(.horizontal, LorvexDesign.Spacing.sm)
      .padding(.vertical, LorvexDesign.Spacing.xxs)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      .overlay(alignment: .leading) {
        Rectangle().fill(color).frame(width: 2)
          .clipShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      }
      .contentShape(Rectangle())
  }

  // MARK: Hour gutter

  func hourGutter() -> some View {
    let labels = LorvexDateFormatters.hourLabels(timeZone: calendar.timeZone)
    let gutter = CalendarWeekGridMetrics.gutterWidth(fitting: labels)
    return VStack(spacing: 0) {
      ForEach(0..<24, id: \.self) { hour in
        Text(labels[hour])
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .frame(
            width: gutter - CalendarWeekGridMetrics.gutterLabelInset, height: hourHeight,
            alignment: .topTrailing)
          .modifier(WeekGridAnchorModifier(hour: hour))
      }
    }
    .frame(width: gutter)
    // Twenty-four labels would be twenty-four stops, and each block already
    // names its own time.
    .accessibilityHidden(true)
  }

  /// The now line across one day column, centered on `now`'s time of day: red
  /// on today, a faint guide on the other days so the time reads across the
  /// week. The grid draws it under the blocks; today's dot is ``nowDot(now:)``.
  func nowLine(now: Date, isToday: Bool) -> some View {
    let lineColor = isToday ? LorvexDesign.Palette.nowIndicator : Color.secondary.opacity(0.22)
    let thickness: CGFloat = isToday ? 1.5 : 1
    return Rectangle().fill(lineColor).frame(height: thickness)
      .offset(y: nowOffset(now) - thickness / 2)
      .accessibilityHidden(true)
  }

  /// Today's now dot, centered on the column's leading edge at `now`'s time of
  /// day. The grid draws it above the blocks, so a block that spans the current
  /// time never covers it while the line itself runs beneath them.
  func nowDot(now: Date) -> some View {
    Circle().fill(LorvexDesign.Palette.nowIndicator).frame(width: 7, height: 7)
      .offset(x: -3.5, y: nowOffset(now) - 3.5)
      .accessibilityHidden(true)
  }

  /// The distance from the grid's midnight line to `now`'s time of day.
  private func nowOffset(_ now: Date) -> CGFloat {
    let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    return CGFloat(minutes) / 60 * hourHeight
  }

  func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }

  func eventColor(_ event: CalendarTimelineEvent) -> Color {
    Color(lorvexHex: event.color) ?? .accentColor
  }

  func headerAccessibilityLabel(_ date: Date) -> String {
    let base = LorvexDateFormatters.string(date, dateStyle: .full, timeZone: calendar.timeZone)
    return isToday(date)
      ? String(
        format: String(
          localized: "calendar.today_date.a11y",
          defaultValue: "Today, %@",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        base)
      : base
  }
}
