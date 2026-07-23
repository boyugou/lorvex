import Foundation
import XCTest

import LorvexCore

final class CalendarGridLayoutTests: XCTestCase {
  private typealias Interval = CalendarGridLayout.Interval
  private typealias Placed = CalendarGridLayout.Placed

  private func placed(_ intervals: [Interval]) -> [String: Placed] {
    Dictionary(
      uniqueKeysWithValues: CalendarGridLayout.layoutLanes(intervals).map { ($0.id, $0) }
    )
  }

  func testEmpty() {
    XCTAssertTrue(CalendarGridLayout.layoutLanes([]).isEmpty)
  }

  func testNonOverlappingEachGetsSingleLane() {
    let result = placed([
      Interval(id: "a", startMin: 0, endMin: 60),
      Interval(id: "b", startMin: 120, endMin: 180),
      Interval(id: "c", startMin: 300, endMin: 360),
    ])
    for id in ["a", "b", "c"] {
      XCTAssertEqual(result[id]?.lane, 0, "\(id) lane")
      XCTAssertEqual(result[id]?.laneCount, 1, "\(id) laneCount")
    }
  }

  func testFullyOverlappingNGetsNLanes() {
    let intervals = (0..<4).map { Interval(id: "e\($0)", startMin: 100, endMin: 200) }
    let result = placed(intervals)
    let lanes = Set(intervals.compactMap { result[$0.id]?.lane })
    XCTAssertEqual(lanes, Set(0..<4))
    for interval in intervals {
      XCTAssertEqual(result[interval.id]?.laneCount, 4)
    }
  }

  func testPartialChainSharesClusterLaneCount() {
    // A overlaps B, B overlaps C, but A and C are disjoint. All three form one
    // connected cluster, so all carry laneCount == 2.
    let result = placed([
      Interval(id: "a", startMin: 0, endMin: 60),
      Interval(id: "b", startMin: 30, endMin: 90),
      Interval(id: "c", startMin: 70, endMin: 120),
    ])
    XCTAssertEqual(result["a"]?.laneCount, 2)
    XCTAssertEqual(result["b"]?.laneCount, 2)
    XCTAssertEqual(result["c"]?.laneCount, 2)
    XCTAssertEqual(result["a"]?.lane, 0)
    XCTAssertEqual(result["b"]?.lane, 1)
    // C does not overlap A, so it reuses lane 0.
    XCTAssertEqual(result["c"]?.lane, 0)
  }

  func testBoundaryTouchSharesLane() {
    // A ends exactly when B starts -> adjacent, not overlapping -> same lane.
    let result = placed([
      Interval(id: "a", startMin: 540, endMin: 600),
      Interval(id: "b", startMin: 600, endMin: 660),
    ])
    XCTAssertEqual(result["a"]?.lane, 0)
    XCTAssertEqual(result["b"]?.lane, 0)
    XCTAssertEqual(result["a"]?.laneCount, 1)
    XCTAssertEqual(result["b"]?.laneCount, 1)
  }

  func testIndependentClustersDoNotShareLaneCount() {
    let result = placed([
      // cluster 1: two overlapping
      Interval(id: "a", startMin: 0, endMin: 60),
      Interval(id: "b", startMin: 30, endMin: 90),
      // cluster 2: single, disjoint
      Interval(id: "c", startMin: 200, endMin: 260),
    ])
    XCTAssertEqual(result["a"]?.laneCount, 2)
    XCTAssertEqual(result["b"]?.laneCount, 2)
    XCTAssertEqual(result["c"]?.laneCount, 1)
    XCTAssertEqual(result["c"]?.lane, 0)
  }

  func testLanesReusedAcrossGapWithinCluster() {
    // a (0-60) and b (0-120) overlap -> lanes 0,1. c (70-130) overlaps b but
    // not a, reuses lane 0. All connected -> laneCount 2.
    let result = placed([
      Interval(id: "a", startMin: 0, endMin: 60),
      Interval(id: "b", startMin: 0, endMin: 120),
      Interval(id: "c", startMin: 70, endMin: 130),
    ])
    XCTAssertEqual(result["a"]?.lane, 1)  // shorter, sorts after b at same start
    XCTAssertEqual(result["b"]?.lane, 0)
    XCTAssertEqual(result["c"]?.lane, 1)
    for id in ["a", "b", "c"] { XCTAssertEqual(result[id]?.laneCount, 2) }
  }
}

final class CalendarGridModelDayTests: XCTestCase {
  private var calendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    return cal
  }

  private static let keyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "America/New_York")!
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  private func date(_ ymd: String) -> Date {
    Self.keyFormatter.date(from: ymd)!
  }

  private func event(
    id: String,
    startDate: String,
    startTime: String?,
    endDate: String? = nil,
    endTime: String?,
    allDay: Bool
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id,
      title: id,
      source: "lorvex",
      editable: true,
      startDate: startDate,
      startTime: startTime,
      endDate: endDate,
      endTime: endTime,
      allDay: allDay,
      location: nil,
      color: nil,
      eventType: "event",
      timezone: nil,
      isRecurring: false
    )
  }

  /// A single-day build (`dayCount: 1`) keeps only the anchor day's events:
  /// the timed event becomes a positioned block, the all-day event routes to
  /// the strip, and an event on a neighbouring day is dropped entirely.
  func testSingleDayFiltersAndRoutes() {
    let anchor = date("2026-05-27")
    let events = [
      event(id: "timed", startDate: "2026-05-27", startTime: "09:00", endTime: "10:30", allDay: false),
      event(id: "allday", startDate: "2026-05-27", startTime: nil, endTime: nil, allDay: true),
      event(id: "other", startDate: "2026-05-28", startTime: "09:00", endTime: "10:00", allDay: false),
    ]
    let days = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 1,
      calendar: calendar,
      events: events,
      tasks: [],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )

    XCTAssertEqual(days.count, 1)
    let day = days[0]
    XCTAssertEqual(day.dayKey, "2026-05-27")
    XCTAssertEqual(day.timedBlocks.map(\.event.id), ["timed"])
    XCTAssertEqual(day.timedBlocks.first?.startMin, 540)  // 09:00
    XCTAssertEqual(day.timedBlocks.first?.endMin, 630)  // 10:30
    XCTAssertEqual(day.allDayEvents.map(\.id), ["allday"])
  }

  /// A multi-day timed event clipped to one visible day still yields exactly
  /// one block, clipped to that day's bounds (the spanning event starts the day
  /// before and ends mid-anchor-day).
  func testMultiDayClipsToVisibleDay() {
    let anchor = date("2026-05-27")
    let events = [
      event(
        id: "overnight",
        startDate: "2026-05-26",
        startTime: "22:00",
        endDate: "2026-05-27",
        endTime: "01:00",
        allDay: false
      )
    ]
    let days = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 1,
      calendar: calendar,
      events: events,
      tasks: [],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )

    let day = days[0]
    XCTAssertEqual(day.timedBlocks.count, 1)
    XCTAssertEqual(day.timedBlocks.first?.startMin, 0)  // clipped to midnight
    XCTAssertEqual(day.timedBlocks.first?.endMin, 60)  // 01:00
  }

  /// A due-dated task on the anchor day routes to that day's all-day strip
  /// (`scheduledTasks`), never as a positioned block; a task due elsewhere is
  /// dropped.
  func testDueDatedTaskRoutesToAllDayStrip() {
    let anchor = date("2026-05-27")
    let onDay = LorvexTask(
      id: "t1",
      title: "Due today",
      notes: "",
      priority: .p2,
      status: .open,
      dueDate: calendar.date(byAdding: .hour, value: 14, to: anchor),
      estimatedMinutes: 30,
      tags: []
    )
    let elsewhere = LorvexTask(
      id: "t2",
      title: "Due tomorrow",
      notes: "",
      priority: .p2,
      status: .open,
      dueDate: calendar.date(byAdding: .day, value: 1, to: anchor),
      estimatedMinutes: 30,
      tags: []
    )
    let days = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 1,
      calendar: calendar,
      events: [],
      tasks: [onDay, elsewhere],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )

    let day = days[0]
    XCTAssertTrue(day.timedBlocks.isEmpty)
    XCTAssertEqual(day.scheduledTasks.map(\.id), ["t1"])
  }

  func testInitialScrollAnchorStartsAtMidnightForEarlyTimedContent() {
    let anchor = date("2026-05-27")
    let days = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 1,
      calendar: calendar,
      events: [
        event(
          id: "flight",
          startDate: "2026-05-27",
          startTime: "04:20",
          endTime: "06:20",
          allDay: false
        )
      ],
      tasks: [],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )

    XCTAssertEqual(CalendarGridModel.initialScrollAnchorHour(for: days), 0)
  }

  func testInitialScrollAnchorStartsAtMidnightForEarlyTimedContentAcrossWeek() {
    let anchor = date("2026-05-24")
    let days = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 7,
      calendar: calendar,
      events: [
        event(
          id: "weekly",
          startDate: "2026-05-25",
          startTime: "09:05",
          endTime: "10:05",
          allDay: false
        ),
        event(
          id: "airport",
          startDate: "2026-05-29",
          startTime: "04:22",
          endTime: "06:22",
          allDay: false
        ),
      ],
      tasks: [],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )

    XCTAssertEqual(CalendarGridModel.initialScrollAnchorHour(for: days), 0)
  }

  func testInitialScrollAnchorStartsAtMidnightForBoundaryBeforeFallbackHour() {
    let anchor = date("2026-05-27")
    let days = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 1,
      calendar: calendar,
      events: [
        event(
          id: "early",
          startDate: "2026-05-27",
          startTime: "07:59",
          endTime: "08:30",
          allDay: false
        )
      ],
      tasks: [],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )

    XCTAssertEqual(CalendarGridModel.initialScrollAnchorHour(for: days), 0)
  }

  func testInitialScrollAnchorKeepsWorkStartForNormalOrEmptyDays() {
    let anchor = date("2026-05-27")
    let normalDays = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 1,
      calendar: calendar,
      events: [
        event(
          id: "standup",
          startDate: "2026-05-27",
          startTime: "09:05",
          endTime: "10:05",
          allDay: false
        )
      ],
      tasks: [],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )
    let emptyDays = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 1,
      calendar: calendar,
      events: [],
      tasks: [],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )

    XCTAssertEqual(CalendarGridModel.initialScrollAnchorHour(for: normalDays), 8)
    XCTAssertEqual(CalendarGridModel.initialScrollAnchorHour(for: emptyDays), 8)
  }

  func testInitialScrollAnchorOpensNearNowWhenTodayVisible() {
    let anchor = date("2026-05-27")
    let days = CalendarGridModel.buildDays(
      rangeStart: anchor,
      dayCount: 1,
      calendar: calendar,
      events: [],
      tasks: [],
      dayKeyFor: { Self.keyFormatter.string(from: $0) }
    )

    // Today visible + known now → one hour of lead-in above the current time.
    XCTAssertEqual(
      CalendarGridModel.initialScrollAnchorHour(
        for: days, todayKey: "2026-05-27", nowMinute: 14 * 60 + 30),
      13
    )
    // Pre-dawn now clamps at midnight, never negative.
    XCTAssertEqual(
      CalendarGridModel.initialScrollAnchorHour(
        for: days, todayKey: "2026-05-27", nowMinute: 30),
      0
    )
    // Today not among the visible days → falls back to the content/work-start
    // behavior (empty day → fallback hour 8), ignoring `nowMinute`.
    XCTAssertEqual(
      CalendarGridModel.initialScrollAnchorHour(
        for: days, todayKey: "2026-05-20", nowMinute: 14 * 60 + 30),
      8
    )
  }
}
