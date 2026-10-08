import LorvexCore
import SwiftUI

/// One page of the iPhone calendar: an all-day strip plus a vertical
/// scrollable time axis rendering `dayCount` (1, 2, 3, or 7) day columns. Builds its
/// layout from the pure `CalendarGridModel` lane packer. A live red now-line
/// sits on today's column; the gutter labels the hours.
@MainActor
struct MobileCalendarDayColumn: View {
  let startDate: Date
  let dayCount: Int
  /// When false, the per-column day headers are suppressed (the week view renders
  /// them as a fixed header outside the pager instead, which keeps them pinned and
  /// avoids the `.page` TabView floating the column's content mid-screen).
  var showsHeaders: Bool = true
  /// Whether the headers draw today's date in a filled circle; false under
  /// the week strip, which circles the chosen day itself.
  var circlesTodayInHeaders = true
  let events: [CalendarTimelineEvent]
  /// The window's tasks: a task with a time on a visible day is drawn on that
  /// day's time axis, any other in the all-day strip of its day.
  let tasks: [LorvexTask]
  let calendar: Calendar
  /// When set, each day's header is a button that opens that day; week mode
  /// uses it to open a day in Day mode.
  var onOpenDay: ((Date) -> Void)? = nil
  let onTapEvent: (CalendarTimelineEvent) -> Void
  let onDeleteEvent: (CalendarTimelineEvent) async -> Bool
  let onTapTask: (LorvexTask) -> Void
  let onDropTask: (LorvexTaskRef, Date) -> Void
  let onTapEmpty: (Date, Int) -> Void
  /// Drag-to-reschedule commit callback. Called with the event, the target
  /// day (one of the visible columns; same as the source day on 1-day or
  /// pure-vertical drags), and the new start-minute-of-day.
  /// `nil` to disable drag-to-move.
  let onReschedule: ((CalendarTimelineEvent, Date, Int) -> Void)?
  /// Completes a task on the grid, a timed block or an all-day pill, or
  /// reopens a done one. The block or pill itself opens the task through
  /// `onTapTask`.
  var onToggleTask: (LorvexTask) -> Void = { _ in }
  /// Whether the clock sits inside the block on today's column — the time
  /// Today shows as running — which draws it with a solid frame.
  var isRunningNow: (CalendarGridTaskBlock, CalendarGridDay) -> Bool = { _, _ in false }

  /// The width of the page the column fills, as the pager measures it. The
  /// all-day strip goes compact when the day columns it spans are narrow. It
  /// is 0 until the pager has measured, which keeps the strip full-size.
  var pageWidth: CGFloat = 0

  let hourHeight: CGFloat = 56
  /// Widens with the footnote style of the hour labels, so "10 AM" and the
  /// all-day label stay on one line at every size the grid draws.
  /// Scales the hour gutter with the footnote style, as its labels scale.
  @ScaledMetric(relativeTo: .footnote) private var gutterScale: CGFloat = 1
  /// Wide enough for the widest hour label on one line at any text size.
  private var gutterWidth: CGFloat { MobileCalendarHourGutter.baseWidth(calendar: calendar) * gutterScale }
  static let snapMinutes: Int = 15

  /// Tracks an in-flight drag on a block: the event being moved + its
  /// in-progress translation in points. Long-press latches the gesture
  /// before the user starts moving so it doesn't fight the parent
  /// `ScrollView`'s vertical pan or the day-pager's horizontal swipe.
  @State var dragState: DragState? = nil
  @State private var userHasScrolledTimeAxis = false
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.displayScale) private var displayScale

  /// Whether the page shows its all-day strip. A single day on a phone shows
  /// it only when the day has something in it, as Calendar does, so an empty
  /// band never sits over the hours. A multi-day page keeps it as the grid's
  /// row for undated items, and a wide layout keeps it as the place to drop
  /// a task dragged from beside the calendar.
  private func showsAllDayStrip(_ columns: [CalendarGridDay]) -> Bool {
    dayCount > 1 || horizontalSizeClass == .regular
      || MobileCalendarAllDayStrip.hasContent(columns)
  }

  /// Whether a day column is narrower than a full block layout needs — the
  /// seven-day week on a phone — so the all-day strip goes compact as the
  /// timed blocks do (``LorvexDesign/CalendarMetrics/compactLaneWidth``).
  /// `gutter` is the hour gutter's width.
  private func hasNarrowColumns(gutter: CGFloat) -> Bool {
    pageWidth > 0
      && (pageWidth - gutter) / CGFloat(dayCount) < LorvexDesign.CalendarMetrics.compactLaneWidth
  }

  struct DragState: Equatable {
    let eventID: String
    var translationX: CGFloat
    var translationY: CGFloat
  }

  private var days: [CalendarGridDay] {
    CalendarGridModel.buildDays(
      rangeStart: startDate,
      dayCount: dayCount,
      calendar: calendar,
      events: events,
      tasks: tasks,
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )
  }

  private var totalHeight: CGFloat { hourHeight * 24 }

  var body: some View {
    let columns = days
    let now = LorvexPreviewClock.now(in: calendar)
    let todayKey = Self.keyFormatter.string(from: now)
    let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    let anchorHour = CalendarGridModel.initialScrollAnchorHour(
      for: columns, todayKey: todayKey, nowMinute: nowMinute)
    let scrollSignature = scrollAnchorSignature(columns: columns, anchorHour: anchorHour)
    let gutter = gutterWidth
    VStack(spacing: 0) {
      if dayCount > 1 && showsHeaders {
        MobileCalendarColumnHeaders(
          columns: columns,
          calendar: calendar,
          gutterWidth: gutter,
          circlesToday: circlesTodayInHeaders,
          onOpenDay: onOpenDay
        )
        .mobileCalendarPageReachability()
        Divider()
      }
      if showsAllDayStrip(columns) {
        MobileCalendarAllDayStrip(
          columns: columns,
          gutterWidth: gutter,
          isCompact: hasNarrowColumns(gutter: gutter),
          eventColor: eventColor,
          onTapEvent: onTapEvent,
          onDeleteEvent: onDeleteEvent,
          onTapTask: onTapTask,
          onToggleTask: onToggleTask,
          onDropTask: onDropTask
        )
        Divider()
      }
      ScrollViewReader { proxy in
        ScrollView {
          HStack(alignment: .top, spacing: 0) {
            // The hour labels are a picture of the time axis: every block
            // says its own time, and 24 extra stops would sit between them.
            MobileCalendarHourGutter(
              calendar: calendar,
              gutterWidth: gutter,
              hourHeight: hourHeight,
              anchorHour: anchorHour
            )
            .accessibilityHidden(true)
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, day in
              timeColumn(day, dayIndex: index, allDays: columns)
              if index < columns.count - 1 { Divider() }
            }
          }
          .frame(height: totalHeight)
        }
        // A scroll to the anchor hour stops this far below the divider.
        .contentMargins(.top, MobileDayScrollAnchor.topClearance, for: .scrollContent)
        .simultaneousGesture(
          DragGesture(minimumDistance: 8)
            .onChanged { _ in userHasScrolledTimeAxis = true }
        )
        .onAppear { proxy.scrollTo(MobileDayScrollAnchor.hour(anchorHour), anchor: .top) }
        .onChange(of: startDate) { _, _ in userHasScrolledTimeAxis = false }
        .onChange(of: dayCount) { _, _ in userHasScrolledTimeAxis = false }
        .onChange(of: scrollSignature) { _, _ in
          if !userHasScrolledTimeAxis {
            lorvexAnimated(.snappy(duration: 0.18)) {
              proxy.scrollTo(MobileDayScrollAnchor.hour(anchorHour), anchor: .top)
            }
          }
        }
      }
      .mobileCalendarPageReachability()
    }
  }

  // MARK: Time column

  private func timeColumn(
    _ day: CalendarGridDay, dayIndex: Int, allDays: [CalendarGridDay]
  ) -> some View {
    GeometryReader { geo in
      let width = geo.size.width
      ZStack(alignment: .topLeading) {
        hourLines(tapping: day.date)
        if isToday(day.date) {
          // Under the blocks (their zIndex lifts them above it), which are
          // opaque, so the line runs through the free time and never across a
          // block's title. Scoped to the now-line only: the per-minute tick
          // rebuilds this thin overlay without re-running the lane-packer or
          // re-laying-out the day.
          TimelineView(.periodic(from: .now, by: 60)) { context in
            nowLine(now: LorvexPreviewClock.now(in: calendar, tick: context.date))
          }
          .allowsHitTesting(false)
        }
        ForEach(day.timedBlocks) { block in
          eventBlock(
            block,
            day: day,
            dayIndex: dayIndex,
            allDays: allDays,
            columnWidth: width)
        }
        ForEach(day.taskBlocks) { block in
          taskBlock(block, day: day, columnWidth: width)
        }
        if isToday(day.date) {
          // The dot draws above the blocks, which sit at zIndex 1, so one that
          // spans the current time never covers it; the line itself runs under
          // them.
          TimelineView(.periodic(from: .now, by: 60)) { context in
            nowDot(now: LorvexPreviewClock.now(in: calendar, tick: context.date))
          }
          .allowsHitTesting(false)
          .zIndex(2)
        }
      }
      // One container per day, so the blocks' sort priorities order a day's
      // blocks among themselves and never across the columns of a week.
      .accessibilityElement(children: .contain)
    }
    .frame(maxWidth: .infinity)
  }

  /// The column's 24 hour lines, drawn as one shape, and the tap on an empty
  /// hour that starts a new event there. The lines are one shape and the tap
  /// one gesture, not a view and a gesture per hour: the pager builds a page
  /// ahead of the swipe that shows it, and a seven-day page would otherwise
  /// hold 168 of each. Not a `Canvas`: it draws the same lines but made the
  /// swipe that first shows its page measurably slower.
  private func hourLines(tapping date: Date) -> some View {
    MobileHourLinesShape(hourHeight: hourHeight, thickness: 1 / displayScale)
      .fill(.separator.opacity(0.5))
      .contentShape(Rectangle())
      .onTapGesture { point in
        onTapEmpty(date, Self.hour(atY: point.y, hourHeight: hourHeight) * 60)
      }
      // Tap-an-empty-hour to create is a pointer/touch shortcut only. Exposing
      // 24 blank slots per day as VoiceOver create-actions would bury the real
      // content (event blocks, now-line) in noise; the toolbar ＋ ("New Event")
      // is the accessible create path.
      .accessibilityHidden(true)
  }

  /// The hour whose row holds the point `y` below the top of a day column,
  /// held to the day's 24 hours.
  nonisolated static func hour(atY y: CGFloat, hourHeight: CGFloat) -> Int {
    min(max(Int(y / hourHeight), 0), 23)
  }

  /// The now line across the column, centered on `now`'s time of day. Drawn
  /// under the blocks; its dot is ``nowDot(now:)``, drawn above them.
  private func nowLine(now: Date) -> some View {
    Rectangle().fill(LorvexDesign.Palette.nowIndicator).frame(height: 1.5)
      .offset(y: nowOffset(now) - 0.75)
      .accessibilityHidden(true)
  }

  /// The now dot, centered on the column's leading edge at `now`'s time of day.
  /// Drawn above the blocks, so a block that spans the current time never
  /// covers it while the line itself runs beneath them.
  private func nowDot(now: Date) -> some View {
    Circle().fill(LorvexDesign.Palette.nowIndicator).frame(width: 7, height: 7)
      .offset(x: -3.5, y: nowOffset(now) - 3.5)
      .accessibilityHidden(true)
  }

  /// The distance from the column's midnight line to `now`'s time of day.
  private func nowOffset(_ now: Date) -> CGFloat {
    let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    return CGFloat(minutes) / 60 * hourHeight
  }

  // MARK: Helpers

  private func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }

  private func scrollAnchorSignature(columns: [CalendarGridDay], anchorHour: Int) -> String {
    let timedIDs = columns.flatMap { day in
      day.timedBlocks.map { "\($0.event.id):\($0.startMin):\($0.endMin)" }
        + day.taskBlocks.map(\.id)
    }
    return ([Self.keyFormatter.string(from: startDate), "\(dayCount)", "\(anchorHour)"] + timedIDs)
      .joined(separator: "|")
  }

  private static var keyFormatter: DateFormatter { LorvexDateFormatters.ymd }
}

/// The hairlines at the top of a day column's 24 hour rows, one rectangle of
/// `thickness` per hour across the shape's width.
private struct MobileHourLinesShape: Shape {
  let hourHeight: CGFloat
  let thickness: CGFloat

  func path(in rect: CGRect) -> Path {
    var lines = Path()
    for hour in 0..<24 {
      lines.addRect(
        CGRect(
          x: rect.minX, y: rect.minY + CGFloat(hour) * hourHeight, width: rect.width,
          height: thickness))
    }
    return lines
  }
}
