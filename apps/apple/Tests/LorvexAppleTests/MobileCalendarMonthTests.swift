import CoreGraphics
import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// The iPhone and iPad calendar's Month mode: which month a day pages to,
/// which day a swipe chooses, where the agenda stands, how much the window
/// loads, and how a cell shows its entries.
@Suite("Calendar month mode")
struct MobileCalendarMonthTests {
  private static func calendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    calendar.firstWeekday = 1
    return calendar
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
    try #require(
      calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
  }

  @Test("A day pages to its month, counted from today's month")
  func monthOffsetCountsMonthsFromTodaysMonth() throws {
    let calendar = try Self.calendar()
    let october = try Self.date(2026, 10, 1)
    #expect(
      MobileCalendarMonthView.monthOffset(
        showing: try Self.date(2026, 10, 31), currentMonthStart: october, calendar: calendar) == 0)
    #expect(
      MobileCalendarMonthView.monthOffset(
        showing: try Self.date(2026, 12, 15), currentMonthStart: october, calendar: calendar) == 2)
    #expect(
      MobileCalendarMonthView.monthOffset(
        showing: try Self.date(2026, 8, 31), currentMonthStart: october, calendar: calendar) == -2)
    #expect(
      MobileCalendarMonthView.monthOffset(
        showing: try Self.date(2027, 1, 1), currentMonthStart: october, calendar: calendar) == 3)
  }

  @Test("A swipe chooses today in today's month and the first day elsewhere")
  func swipeChoosesTodayOrTheFirstDay() throws {
    let calendar = try Self.calendar()
    let today = try Self.date(2026, 10, 14, hour: 15)
    #expect(
      MobileCalendarMonthView.defaultSelection(
        forMonthStarting: try Self.date(2026, 10, 1), today: today, calendar: calendar)
        == (try Self.date(2026, 10, 14)))
    #expect(
      MobileCalendarMonthView.defaultSelection(
        forMonthStarting: try Self.date(2026, 11, 1), today: today, calendar: calendar)
        == (try Self.date(2026, 11, 1)))
  }

  @Test("The agenda stands beside the grid on a wide iPad and a phone on its side, under it elsewhere")
  func agendaPlacementFollowsWidthAndHeight() {
    // An upright phone and an iPad's narrower window stack the agenda.
    #expect(!MobileCalendarMonthView.usesSideAgenda(width: 402, isRegularWidth: false, isCompactHeight: false))
    #expect(!MobileCalendarMonthView.usesSideAgenda(width: 834, isRegularWidth: true, isCompactHeight: false))
    // A wide iPad, and every phone on its side, stand it beside the grid.
    #expect(MobileCalendarMonthView.usesSideAgenda(width: 1032, isRegularWidth: true, isCompactHeight: false))
    #expect(MobileCalendarMonthView.usesSideAgenda(width: 750, isRegularWidth: false, isCompactHeight: true))
    #expect(MobileCalendarMonthView.usesSideAgenda(width: 830, isRegularWidth: true, isCompactHeight: true))
  }

  @Test("The window loads the previous and next months' grids around the visible one")
  func windowSpansBothNeighboringGrids() throws {
    let calendar = try Self.calendar()
    // September 2026 starts on a Tuesday, so its Sunday-first grid starts on
    // August 30; November 2026 starts on a Sunday, so its six-row grid runs
    // through December 12.
    let window = MobileCalendarMonthView.loadWindow(
      forMonthStarting: try Self.date(2026, 10, 1), weeks: 6, calendar: calendar)
    #expect(window.from == (try Self.date(2026, 8, 30)))
    #expect(window.through == (try Self.date(2026, 12, 12)))
  }

  @Test("A small cell marks its entries; a tall, wide one names as many as fit")
  func cellStyleFollowsTheCellSize() {
    // An upright phone's fixed rows, and a phone on its side.
    #expect(
      MobileCalendarMonthGrid.cellStyle(rowHeight: 46, cellWidth: 57, dayNumberSize: 28, chipHeight: 17)
        == .marks)
    #expect(
      MobileCalendarMonthGrid.cellStyle(rowHeight: 40, cellWidth: 53, dayNumberSize: 28, chipHeight: 17)
        == .marks)
    // An iPad cell: (120 - 6 - 28) / (17 + 2) holds four chips.
    #expect(
      MobileCalendarMonthGrid.cellStyle(rowHeight: 120, cellWidth: 136, dayNumberSize: 28, chipHeight: 17)
        == .titled(maxChips: 4))
    // Too narrow to name anything, or too short for two chips.
    #expect(
      MobileCalendarMonthGrid.cellStyle(rowHeight: 120, cellWidth: 60, dayNumberSize: 28, chipHeight: 17)
        == .marks)
    #expect(
      MobileCalendarMonthGrid.cellStyle(rowHeight: 60, cellWidth: 100, dayNumberSize: 28, chipHeight: 17)
        == .marks)
  }

  @Test("A tap on a titled cell lands on the chip under it, and on no chip anywhere else")
  func tapResolvesToTheChipUnderIt() {
    // With a 28-point day number and 17-point chips, the first chip spans 33
    // to 50 points below the cell's top (3 of inset, the number, 2 of space)
    // and each next one starts 19 points after the one before.
    func chip(_ y: CGFloat, count: Int = 3, number: CGFloat = 28, height: CGFloat = 17) -> Int? {
      MobileCalendarMonthDayCell.chipIndex(
        atY: y, dayNumberSize: number, chipHeight: height, count: count)
    }
    #expect(chip(10) == nil)
    #expect(chip(32.9) == nil)
    #expect(chip(33) == 0)
    #expect(chip(49.9) == 0)
    #expect(chip(50) == nil)
    #expect(chip(51.9) == nil)
    #expect(chip(52) == 1)
    #expect(chip(71) == 2)
    #expect(chip(87.9) == 2)
    // The row after the last chip (the "+N" row), the empty area under the
    // stack, and a cell without chips choose the day.
    #expect(chip(90) == nil)
    #expect(chip(71, count: 2) == nil)
    #expect(chip(33, count: 0) == nil)
    // A point above the cell, or one that is not a position, is on nothing.
    #expect(chip(-4) == nil)
    #expect(chip(.nan) == nil)
    #expect(chip(.infinity) == nil)
    #expect(chip(1e30) == nil)
    // Larger text scales the number and the chips together.
    #expect(chip(40.9, number: 36, height: 22) == nil)
    #expect(chip(41, number: 36, height: 22) == 0)
    #expect(chip(65, number: 36, height: 22) == 1)
  }

  @Test("A month cell has one tap, which resolves the chip itself, and no button around a chip")
  func monthCellResolvesItsOwnTaps() throws {
    let source = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/LorvexMobile/MobileCalendarMonthDayCell.swift"),
      encoding: .utf8)
    // A button around a 17-point chip takes touches well beyond its frame
    // and swallows the cell's tap, so a day that holds chips could not be
    // chosen by tapping near them; the cell maps the tap's position instead.
    #expect(source.contains(".onTapGesture(coordinateSpace: .local) { tap(at: $0) }"))
    #expect(!source.contains(".buttonStyle("))
    #expect(source.contains(".padding(.top, Self.titledTopInset)"))
    #expect(source.contains("VStack(spacing: Self.chipSpacing)"))
  }

  @Test("The chosen day keeps its agenda section while free")
  func pinnedDayStaysListedWhileFree() {
    let free = MobileCalendarAgendaDay(
      date: Date(timeIntervalSince1970: 0), key: "2026-10-20", events: [], tasks: [])
    #expect(MobileCalendarAgendaDay.listed([free], todayKey: "2026-10-14").isEmpty)
    #expect(
      MobileCalendarAgendaDay.listed([free], todayKey: "2026-10-14", pinnedDayKey: "2026-10-20")
        .map(\.key) == ["2026-10-20"])
  }

  @Test("The agenda leaves out a cancelled task, as the calendar grids do")
  func agendaDaysSkipCancelledTasks() throws {
    let key = "2026-10-20"
    let plannedDay = LorvexDateFormatters.ymdUTC.date(from: key)
    func task(_ id: String, _ status: LorvexTask.Status) -> LorvexTask {
      LorvexTask(
        id: id, title: id, notes: "", priority: .p2, status: status, dueDate: nil,
        plannedDate: plannedDay, plannedTime: nil, estimatedMinutes: nil, tags: [])
    }
    let days = MobileCalendarAgendaDay.days(
      for: [try Self.date(2026, 10, 20)], events: [],
      tasks: [task("open", .open), task("done", .completed), task("cancelled", .cancelled)],
      keyFor: { _ in key })
    #expect(days.map(\.key) == [key])
    #expect(Set(days[0].tasks.map(\.id)) == ["open", "done"])
  }

  @Test("New Event starts at the next full hour today and at 9:00 on another day")
  func newEventDefaultTime() throws {
    let calendar = try Self.calendar()
    let now = try Self.date(2026, 10, 14, hour: 15).addingTimeInterval(20 * 60)
    let today = MobileCalendarDraft.timedDefault(on: try Self.date(2026, 10, 14), now: now, calendar: calendar)
    #expect(today.timing.start == (try Self.date(2026, 10, 14, hour: 16)))
    #expect(today.timing.end == (try Self.date(2026, 10, 14, hour: 17)))
    let later = MobileCalendarDraft.timedDefault(on: try Self.date(2026, 10, 20), now: now, calendar: calendar)
    #expect(later.timing.start == (try Self.date(2026, 10, 20, hour: 9)))
    #expect(!later.timing.allDay)
  }
}
