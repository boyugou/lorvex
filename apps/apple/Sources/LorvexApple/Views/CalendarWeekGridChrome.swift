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
      }
    }
    .padding(.vertical, CalendarWeekGridMetrics.headerVerticalPadding)
    .fixedSize(horizontal: false, vertical: true)
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
        allDayColumn(day)
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
    // task drags from every other surface and arbitrary dropped text can't drive
    // `rescheduleScheduledTask(id:)`.
    .dropDestination(for: LorvexTaskRef.self) { refs, _ in
      let ids = refs.droppedTaskIDs
      guard !ids.isEmpty else { return false }
      Task {
        for id in ids { await store.rescheduleScheduledTask(id: id, to: day.date) }
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
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(calendarPillAccessibilityLabel(event))
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
      Button(
        String(
          localized: "calendar.task.plan_day_later", defaultValue: "Plan a Day Later",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "arrow.forward"
      ) {
        reschedule(task, byDays: 1, from: day.date)
      }
      Button(
        String(
          localized: "calendar.task.plan_week_later", defaultValue: "Plan a Week Later",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "arrow.forward.to.line"
      ) {
        reschedule(task, byDays: 7, from: day.date)
      }
    }
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

  private func reschedule(_ task: LorvexTask, byDays days: Int, from day: Date) {
    guard let target = calendar.date(byAdding: .day, value: days, to: day) else { return }
    Task { await store.rescheduleScheduledTask(id: task.id, to: target) }
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
    VStack(spacing: 0) {
      ForEach(0..<24, id: \.self) { hour in
        Text(hourLabel(hour))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .frame(
            width: gutterWidth - CalendarWeekGridMetrics.gutterLabelInset, height: hourHeight,
            alignment: .topTrailing)
          .modifier(WeekGridAnchorModifier(hour: hour))
      }
    }
    .frame(width: gutterWidth)
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

  func hourLabel(_ hour: Int) -> String {
    var components = DateComponents(calendar: calendar)
    components.year = 2001
    components.month = 1
    components.day = 1
    components.hour = hour
    guard let date = calendar.date(from: components) else {
      return "\(hour)"
    }
    return LorvexDateFormatters.hourLabel(date, timeZone: calendar.timeZone)
  }

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
