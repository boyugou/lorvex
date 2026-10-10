#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import LorvexCore
  @testable import LorvexMobile

  /// The phone calendar's all-day strip takes the height its rows need, up to a
  /// limit, and leaves the rest to the hours below it. These tests host the
  /// strip beside a tall scroll view, as a day column lays it out, and read the
  /// height it takes after layout.
  @Suite("All-day strip height")
  @MainActor
  struct MobileCalendarAllDayStripLayoutTests {
    private final class Reading {
      var height: CGFloat = -1
    }

    /// The height `content` takes when its parent offers `offered` points.
    private func height(of content: some View, offered: CGFloat = 700) -> CGFloat {
      let reading = Reading()
      let hosting = NSHostingView(
        rootView: VStack(spacing: 0) {
          content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { reading.height = $0 }
          ScrollView { Color.clear.frame(height: 1_500) }
        }
        .frame(width: 402, height: offered))
      let size = NSSize(width: 402, height: offered)
      let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      hosting.frame = NSRect(origin: .zero, size: size)
      hosting.layoutSubtreeIfNeeded()
      // The measurement is read after layout and lands a turn later.
      for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
      window.contentView = nil
      return reading.height
    }

    private func event(_ id: String, day: String) -> CalendarTimelineEvent {
      CalendarTimelineEvent(
        id: id, title: "Event \(id)", source: "lorvex", editable: true, startDate: day,
        startTime: nil, endDate: nil, endTime: nil, allDay: true, location: nil, color: nil,
        eventType: "event", timezone: nil, isRecurring: false)
    }

    private func task(_ id: String) -> LorvexTask {
      LorvexTask(
        id: id, title: "Task \(id)", notes: "", priority: .p2, status: .open, dueDate: nil,
        estimatedMinutes: nil, tags: [])
    }

    /// `count` consecutive days from 2026-10-04, each with `events` all-day
    /// events and `tasks` unscheduled tasks.
    private func columns(_ count: Int, events: Int = 0, tasks: Int = 0) -> [CalendarGridDay] {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: "UTC")!
      let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4))!
      return (0..<count).map { index in
        let key = String(format: "2026-10-%02d", 4 + index)
        return CalendarGridDay(
          date: calendar.date(byAdding: .day, value: index, to: start)!, dayKey: key,
          timedBlocks: [],
          allDayEvents: (0..<events).map { event("\(index)-\($0)", day: key) },
          scheduledTasks: (0..<tasks).map { task("\(index)-\($0)") })
      }
    }

    private func strip(_ columns: [CalendarGridDay], sizeClass: UserInterfaceSizeClass) -> some View {
      MobileCalendarAllDayStrip(
        columns: columns, gutterWidth: 52, isCompact: columns.count > 1,
        eventColor: { _ in .blue }, onTapEvent: { _ in }, deletion: .inert,
        onTapTask: { _ in }, onToggleTask: { _ in }, onDropTask: { _, _ in }
      )
      .environment(\.horizontalSizeClass, sizeClass)
    }

    @Test("a strip with nothing in it takes its least height, not the limit")
    func emptyStripIsShort() {
      for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
        #expect(height(of: strip(columns(3), sizeClass: sizeClass)) == 24, "\(sizeClass)")
      }
    }

    @Test("a strip with one row of pills takes that row, not the limit")
    func oneRowHugsItsContent() {
      for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
        for days in [1, 3, 7] {
          let withEvents = height(of: strip(columns(days, events: 1), sizeClass: sizeClass))
          let withTasks = height(of: strip(columns(days, tasks: 1), sizeClass: sizeClass))
          #expect((24...40).contains(withEvents), "\(days) days, \(sizeClass): \(withEvents)")
          #expect((24...40).contains(withTasks), "\(days) days, \(sizeClass): \(withTasks)")
        }
      }
    }

    @Test("each added row of pills adds its height until the limit")
    func heightFollowsTheRows() {
      let one = height(of: strip(columns(3, events: 1), sizeClass: .regular))
      let two = height(of: strip(columns(3, events: 2), sizeClass: .regular))
      let four = height(of: strip(columns(3, events: 4), sizeClass: .regular))
      #expect(one < two && two < four, "\(one), \(two), \(four)")
      // A pill row and the gap above it, in the pills' small text.
      #expect((15...30).contains(two - one), "\(one), \(two), \(four)")
      #expect((30...60).contains(four - two), "\(one), \(two), \(four)")
    }

    @Test("a strip with more rows than fit stops at the limit: 124pt on a phone, twice that on a wide layout")
    func busyStripStopsAtTheLimit() {
      let limit = LorvexDesign.CalendarMetrics.allDayStripMaxHeight
      #expect(height(of: strip(columns(3, events: 20), sizeClass: .compact)) == limit)
      #expect(height(of: strip(columns(3, events: 20), sizeClass: .regular)) == 2 * limit)
    }

    @Test("a strip offered less room than the limit takes less than the limit")
    func stripTakesNoMoreThanItIsOffered() {
      let taken = height(of: strip(columns(3, events: 20), sizeClass: .regular), offered: 100)
      #expect(taken <= 100, "\(taken)")
    }
  }

  /// The scroll cap itself: a scroll view takes its content's height up to the
  /// cap, and scrolls within the cap beyond it.
  @Suite("Scroll cap layout")
  @MainActor
  struct MobileScrollCapLayoutTests {
    private final class Reading {
      var height: CGFloat = -1
    }

    private func fittingHeight(_ content: some View) -> CGFloat {
      NSHostingView(rootView: content.frame(width: 200)).fittingSize.height
    }

    private func laidOutHeight(_ content: some View, offered: CGFloat) -> CGFloat {
      let reading = Reading()
      let hosting = NSHostingView(
        rootView: content
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { reading.height = $0 }
          .frame(width: 200, height: offered, alignment: .top))
      let size = NSSize(width: 200, height: offered)
      let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = hosting
      hosting.frame = NSRect(origin: .zero, size: size)
      hosting.layoutSubtreeIfNeeded()
      for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
      window.contentView = nil
      return reading.height
    }

    private func scrolling(height: CGFloat) -> some View {
      ScrollView(.vertical) { Color.red.frame(height: height) }
    }

    @Test("a scroll view shorter than the cap keeps its content's height, however much room is offered")
    func shortContentKeepsItsHeight() {
      let layout = MobileScrollCapLayout(maxHeight: 120) { scrolling(height: 30) }
      #expect(laidOutHeight(layout, offered: 500) == 30)
    }

    @Test("a scroll view taller than the cap takes the cap")
    func tallContentTakesTheCap() {
      let layout = MobileScrollCapLayout(maxHeight: 120) { scrolling(height: 300) }
      #expect(laidOutHeight(layout, offered: 500) == 120)
    }

    @Test("a scroll view offered less room than the cap takes the room offered")
    func offeredRoomBelowTheCapWins() {
      let layout = MobileScrollCapLayout(maxHeight: 120) { scrolling(height: 300) }
      #expect(laidOutHeight(layout, offered: 80) == 80)
    }

    @Test("the ideal height is the content's, up to the cap")
    func idealHeightIsCapped() {
      #expect(fittingHeight(MobileScrollCapLayout(maxHeight: 120) { scrolling(height: 300) }) == 120)
      #expect(fittingHeight(MobileScrollCapLayout(maxHeight: 120) { scrolling(height: 30) }) == 30)
    }
  }
#endif
