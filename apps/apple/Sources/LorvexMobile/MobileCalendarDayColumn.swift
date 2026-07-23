import LorvexCore
import SwiftUI

/// One page of the iPhone calendar: an all-day strip plus a vertical
/// scrollable time axis rendering `dayCount` (1 or 3) day columns. Builds its
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
  let events: [CalendarTimelineEvent]
  let tasks: [LorvexTask]
  let calendar: Calendar
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

  let hourHeight: CGFloat = 56
  private let gutterWidth: CGFloat = 52
  static let snapMinutes: Int = 15

  /// Tracks an in-flight drag on a block: the event being moved + its
  /// in-progress translation in points. Long-press latches the gesture
  /// before the user starts moving so it doesn't fight the parent
  /// `ScrollView`'s vertical pan or the day-pager's horizontal swipe.
  @State var dragState: DragState? = nil
  @State private var userHasScrolledTimeAxis = false

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
    let now = Date()
    let todayKey = Self.keyFormatter.string(from: now)
    let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    let anchorHour = CalendarGridModel.initialScrollAnchorHour(
      for: columns, todayKey: todayKey, nowMinute: nowMinute)
    let scrollSignature = scrollAnchorSignature(columns: columns, anchorHour: anchorHour)
    VStack(spacing: 0) {
      if dayCount > 1 && showsHeaders {
        MobileCalendarColumnHeaders(
          columns: columns,
          calendar: calendar,
          gutterWidth: gutterWidth
        )
        Divider()
      }
      MobileCalendarAllDayStrip(
        columns: columns,
        gutterWidth: gutterWidth,
        eventColor: eventColor,
        onTapEvent: onTapEvent,
        onDeleteEvent: onDeleteEvent,
        onTapTask: onTapTask,
        onDropTask: onDropTask
      )
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          HStack(alignment: .top, spacing: 0) {
            MobileCalendarHourGutter(
              calendar: calendar,
              gutterWidth: gutterWidth,
              hourHeight: hourHeight,
              anchorHour: anchorHour
            )
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, day in
              timeColumn(day, dayIndex: index, allDays: columns)
              if index < columns.count - 1 { Divider() }
            }
          }
          .frame(height: totalHeight)
        }
        .simultaneousGesture(
          DragGesture(minimumDistance: 8)
            .onChanged { _ in userHasScrolledTimeAxis = true }
        )
        .onAppear { proxy.scrollTo(MobileDayScrollAnchor.hour(anchorHour), anchor: .top) }
        .onChange(of: startDate) { _, _ in userHasScrolledTimeAxis = false }
        .onChange(of: dayCount) { _, _ in userHasScrolledTimeAxis = false }
        .onChange(of: scrollSignature) { _, _ in
          if !userHasScrolledTimeAxis {
            withAnimation(.snappy(duration: 0.18)) {
              proxy.scrollTo(MobileDayScrollAnchor.hour(anchorHour), anchor: .top)
            }
          }
        }
      }
    }
  }

  // MARK: Time column

  private func timeColumn(
    _ day: CalendarGridDay, dayIndex: Int, allDays: [CalendarGridDay]
  ) -> some View {
    GeometryReader { geo in
      let width = geo.size.width
      ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
          ForEach(0..<24, id: \.self) { hour in
            Rectangle()
              .fill(Color.clear)
              .frame(height: hourHeight)
              .contentShape(Rectangle())
              .overlay(alignment: .top) { Divider().opacity(0.5) }
              .onTapGesture { onTapEmpty(day.date, hour * 60) }
          }
        }
        // Tap-an-empty-hour to create is a pointer/touch shortcut only. Exposing
        // 24 blank slots per day as VoiceOver create-actions would bury the real
        // content (event blocks, now-line) in noise; the toolbar ＋ ("New Event")
        // is the accessible create path.
        .accessibilityHidden(true)
        ForEach(day.timedBlocks) { block in
          eventBlock(
            block,
            day: day,
            dayIndex: dayIndex,
            allDays: allDays,
            columnWidth: width)
        }
        if isToday(day.date) {
          // Scoped to the now-line only: the per-minute tick rebuilds this thin
          // overlay without re-running the lane-packer or re-laying-out the day.
          TimelineView(.periodic(from: .now, by: 60)) { context in
            nowLine(now: context.date)
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func nowLine(now: Date) -> some View {
    let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    let y = CGFloat(minutes) / 60 * hourHeight
    return ZStack(alignment: .leading) {
      Circle().fill(Color.red).frame(width: 7, height: 7).offset(x: -3)
      Rectangle().fill(Color.red).frame(height: 1.5)
    }
    .offset(y: y)
    .accessibilityHidden(true)
  }

  // MARK: Helpers

  private func isToday(_ date: Date) -> Bool { calendar.isDateInToday(date) }

  private func scrollAnchorSignature(columns: [CalendarGridDay], anchorHour: Int) -> String {
    let timedIDs = columns.flatMap { day in
      day.timedBlocks.map { "\($0.event.id):\($0.startMin):\($0.endMin)" }
    }
    return ([Self.keyFormatter.string(from: startDate), "\(dayCount)", "\(anchorHour)"] + timedIDs)
      .joined(separator: "|")
  }

  private static var keyFormatter: DateFormatter { LorvexDateFormatters.ymd }
}
