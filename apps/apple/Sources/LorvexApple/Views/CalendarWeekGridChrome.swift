import LorvexCore
import SwiftUI

extension CalendarWeekGridView {
  // MARK: Header

  func header(_ columns: [CalendarGridDay]) -> some View {
    HStack(spacing: 0) {
      // Fixed-width *and* fixed-height spacer: a bare `Color.clear.frame(width:)`
      // stays vertically greedy, so the header HStack would compete with the
      // scrollable time grid for slack height and balloon into a tall band with
      // the day numbers floating in its centre. Pinning the gutter height (and
      // the whole row via `fixedSize` below) keeps the header content-sized.
      Color.clear.frame(width: gutterWidth, height: CalendarWeekGridMetrics.headerGutterHeight)
      ForEach(columns) { day in
        VStack(spacing: 2) {
          Text(Self.weekdayFormatter.string(from: day.date).uppercased())
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
          Text(Self.dayNumberFormatter.string(from: day.date))
            .font(LorvexDesign.Typography.primaryEmphasis)
            .foregroundStyle(isToday(day.date) ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(width: CalendarWeekGridMetrics.dayNumberSize, height: CalendarWeekGridMetrics.dayNumberSize)
            .background {
              if isToday(day.date) {
                Circle().fill(.tint.opacity(0.15))
              }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel(day.date))
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
        .frame(width: gutterWidth, alignment: .trailing)
        .padding(.trailing, 6)
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

  /// One day's stack in the all-day strip: event pills, then scheduled-task
  /// pills. Task pills are draggable by id and every column is a drop target,
  /// so a task can be re-planned onto another day without opening it. The stack
  /// is capped at ``CalendarWeekGridMetrics/allDayMaxItems``; anything past the
  /// cap collapses into a "+N more" overflow pill so a busy day can't grow the
  /// strip without bound.
  func allDayColumn(_ day: CalendarGridDay) -> some View {
    let layout = allDayLayout(for: day)
    return VStack(spacing: 3) {
      ForEach(layout.events) { event in
        allDayEventPill(event)
      }
      ForEach(layout.tasks) { task in
        allDayTaskPill(task, on: day)
      }
      if !layout.hiddenEvents.isEmpty || !layout.hiddenTasks.isEmpty {
        allDayOverflowPill(day: day, hidden: layout.hiddenEvents, hiddenTasks: layout.hiddenTasks)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 3)
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
      guard let ref = refs.first else { return false }
      Task { await store.rescheduleScheduledTask(id: ref.id, to: day.date) }
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

  private func allDayEventPill(_ event: CalendarTimelineEvent) -> some View {
    allDayPill(title: event.title, color: eventColor(event))
      .onTapGesture { selectEvent(event) }
      .calendarPointingHandCursor()
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(
        String(
          format: String(
            localized: "calendar.all_day_event.a11y",
            defaultValue: "All day event %@",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          event.title))
  }

  private func allDayTaskPill(_ task: LorvexTask, on day: CalendarGridDay) -> some View {
    allDayPill(title: task.title, color: taskColor(task))
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
        Divider()
        Button(
          String(
            localized: "calendar.task.plan_day_later", defaultValue: "Plan a Day Later",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "arrow.right"
        ) {
          reschedule(task, byDays: 1, from: day.date)
        }
        Button(
          String(
            localized: "calendar.task.plan_week_later", defaultValue: "Plan a Week Later",
            table: "Localizable",
            bundle: LorvexL10n.bundle),
          systemImage: "arrow.right.to.line"
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
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      String(
        format: String(
          localized: "calendar.all_day.more.a11y", defaultValue: "%lld more all-day items",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        count))
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
        overflowRow(title: task.title, color: taskColor(task)) {
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

  func allDayPill(title: String, color: Color) -> some View {
    Text(title)
      .font(LorvexDesign.Typography.tertiaryText)
      .lineLimit(1)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
      .overlay(alignment: .leading) {
        Rectangle().fill(color).frame(width: 2)
          .clipShape(RoundedRectangle(cornerRadius: 1))
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
          .frame(width: gutterWidth - 6, height: hourHeight, alignment: .topTrailing)
          .modifier(WeekGridAnchorModifier(hour: hour))
      }
    }
    .frame(width: gutterWidth)
  }

  func nowLine(now: Date, isToday: Bool) -> some View {
    let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    let y = CGFloat(minutes) / 60 * hourHeight
    let lineColor = isToday ? Color.red : Color.secondary.opacity(0.22)
    return ZStack(alignment: .leading) {
      if isToday {
        Circle().fill(lineColor).frame(width: 7, height: 7).offset(x: -3)
      }
      Rectangle().fill(lineColor).frame(height: isToday ? 1.5 : 1)
    }
    .offset(y: y)
    .accessibilityHidden(true)
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
    return Self.hourFormatter.string(from: date)
  }

  func eventColor(_ event: CalendarTimelineEvent) -> Color {
    Color(lorvexHex: event.color) ?? .accentColor
  }

  /// A scheduled-task pill's tint: its owning list's color, resolved live from
  /// the loaded list catalog (the same recipe the task rows use), so a task
  /// reads as belonging to its list rather than an anonymous gray. Falls back to
  /// secondary for a task with no list or an unloaded catalog.
  func taskColor(_ task: LorvexTask) -> Color {
    guard let listID = task.listID,
      let list = store.lists?.lists.first(where: { $0.id == listID }),
      let color = Color(lorvexHex: list.color)
    else { return .secondary }
    return color
  }

  func headerAccessibilityLabel(_ date: Date) -> String {
    let base = Self.fullDateFormatter.string(from: date)
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

  // `static` so the SwiftUI View struct (rebuilt frequently) doesn't
  // re-allocate DateFormatters per render. These are display formatters,
  // intentionally locale-dependent unlike the POSIX data formatters.
  static let weekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE"
    return f
  }()
  static let dayNumberFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d"
    return f
  }()
  static let fullDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .full
    return f
  }()
  static let hourFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("j")
    return f
  }()
}
