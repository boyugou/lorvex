import CoreGraphics
import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// The calendar pagers' rules for which pages hold content, the policy that
/// loads the month window, and the equality that lets SwiftUI skip a page or a
/// cell whose data did not change.
@Suite("Calendar pagers")
@MainActor
struct MobileCalendarPagerTests {
  private static func calendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    calendar.firstWeekday = 1
    return calendar
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
    try #require(calendar().date(from: DateComponents(year: year, month: month, day: day)))
  }

  private static func event(_ id: String, on day: String = "2026-10-14") -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, title: id, source: "lorvex", editable: true,
      startDate: day, startTime: "09:00", endDate: nil, endTime: "10:00",
      allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
      isRecurring: false)
  }

  /// Counts what the closures of a page's actions or a cell are called for, so
  /// two values built from the same data can differ in their closures.
  private final class Recorder {
    var calls = 0
  }

  // MARK: Live pages

  @Test("The visible page and the two on each side hold content; farther pages do not")
  func pagesNearTheVisibleOneHoldContent() {
    for visible in [-3, 0, 5] {
      for distance in -2...2 {
        #expect(MobileLivePages.holdsContent(offset: visible + distance, visibleOffset: visible))
      }
      #expect(!MobileLivePages.holdsContent(offset: visible + 3, visibleOffset: visible))
      #expect(!MobileLivePages.holdsContent(offset: visible - 3, visibleOffset: visible))
    }
  }

  @Test("A jump slides only within the pages that hold content, and never blanks the page it leaves")
  func jumpsSlideOnlyWithinTheKeptPages() {
    #expect(MobileLivePages.slides(from: 0, to: 0))
    #expect(MobileLivePages.slides(from: 0, to: 2))
    #expect(MobileLivePages.slides(from: 0, to: -2))
    #expect(!MobileLivePages.slides(from: 0, to: 3))
    #expect(!MobileLivePages.slides(from: 0, to: -3))
    #expect(!MobileLivePages.slides(from: 10, to: 0))
    // When a slide's target becomes the visible page, the page the slide left
    // still holds content, so it is not an empty placeholder mid-animation.
    for target in -6...6 where MobileLivePages.slides(from: 0, to: target) {
      #expect(MobileLivePages.holdsContent(offset: 0, visibleOffset: target))
    }
  }

  // MARK: Month indexes and the chosen day

  @Test("Month indexes make the distance between two months a subtraction across a year")
  func monthIndexesCountMonthsAcrossYears() throws {
    let calendar = try Self.calendar()
    let december = MobileCalendarMonthView.monthIndex(of: try Self.date(2026, 12, 31), calendar: calendar)
    let january = MobileCalendarMonthView.monthIndex(of: try Self.date(2027, 1, 1), calendar: calendar)
    #expect(january - december == 1)
    #expect(
      MobileCalendarMonthView.monthIndex(of: try Self.date(2026, 10, 1), calendar: calendar)
        == MobileCalendarMonthView.monthIndex(of: try Self.date(2026, 10, 31), calendar: calendar))
  }

  @Test("A month's grid shows the chosen day when it lies in that month or the one before or after")
  func gridShowsTheChosenDayWithinOneMonth() throws {
    let calendar = try Self.calendar()
    let current = MobileCalendarMonthView.monthIndex(of: try Self.date(2026, 10, 14), calendar: calendar)
    func key(chosen: Date, offset: Int) -> String {
      MobileCalendarMonthPage.selectedKey(
        "chosen", chosenMonthIndex: MobileCalendarMonthView.monthIndex(of: chosen, calendar: calendar),
        offset: offset, currentMonthIndex: current)
    }
    // Offset 0 is October: September 30 and November 1 pad its first and last weeks.
    #expect(key(chosen: try Self.date(2026, 10, 31), offset: 0) == "chosen")
    #expect(key(chosen: try Self.date(2026, 9, 30), offset: 0) == "chosen")
    #expect(key(chosen: try Self.date(2026, 11, 1), offset: 0) == "chosen")
    #expect(key(chosen: try Self.date(2026, 8, 31), offset: 0).isEmpty)
    #expect(key(chosen: try Self.date(2026, 12, 1), offset: 0).isEmpty)
    // Offset -2 is August.
    #expect(key(chosen: try Self.date(2026, 9, 15), offset: -2) == "chosen")
    #expect(key(chosen: try Self.date(2026, 10, 1), offset: -2).isEmpty)
  }

  @Test("A grid of six rows reaches no month beyond the one before and the one after its own")
  func gridNeverReachesPastTheNeighboringMonths() throws {
    var calendar = try Self.calendar()
    let first = try Self.date(2025, 1, 1)
    for firstWeekday in 1...7 {
      calendar.firstWeekday = firstWeekday
      for months in 0..<36 {
        let month = try #require(calendar.date(byAdding: .month, value: months, to: first))
        let range = CalendarMonthGridModel.gridRange(
          forMonthContaining: month, calendar: calendar, minimumWeeks: 6)
        let last = try #require(calendar.date(byAdding: .day, value: range.dayCount - 1, to: range.start))
        let index = MobileCalendarMonthView.monthIndex(of: month, calendar: calendar)
        #expect(MobileCalendarMonthView.monthIndex(of: range.start, calendar: calendar) >= index - 1)
        #expect(MobileCalendarMonthView.monthIndex(of: last, calendar: calendar) <= index + 1)
      }
    }
  }

  // MARK: Calendar window

  @Test("Two neighboring months each way load the grids two months before and after the visible one")
  func windowSpansTwoNeighborsEachWay() throws {
    let calendar = try Self.calendar()
    // August 2026 starts on a Saturday, so its Sunday-first grid starts on
    // July 26; December 2026 starts on a Tuesday, so its six-row grid runs
    // from November 29 through January 9.
    let window = MobileCalendarMonthView.loadWindow(
      forMonthStarting: try Self.date(2026, 10, 1), weeks: 6, neighborMonths: 2, calendar: calendar)
    #expect(window.from == (try Self.date(2026, 7, 26)))
    #expect(window.through == (try Self.date(2027, 1, 9)))
  }

  private static func bounds(
    aroundMonthStarting monthStart: Date, neighborMonths: Int, calendar: Calendar
  ) -> (from: String, to: String) {
    let window = MobileCalendarMonthView.loadWindow(
      forMonthStarting: monthStart, weeks: 6, neighborMonths: neighborMonths, calendar: calendar)
    return (LorvexDateFormatters.ymdUTC.string(from: window.from),
      LorvexDateFormatters.ymdUTC.string(from: window.through))
  }

  private static func windowLoad(
    visible: Date, loaded: (from: String, to: String)?, calendar: Calendar
  ) -> MobileCalendarMonthView.WindowLoad {
    MobileCalendarMonthView.windowLoad(
      loaded: loaded, visibleMonthStart: visible, weeks: 6, calendar: calendar,
      dayKey: { LorvexDateFormatters.ymdUTC.string(from: $0) })
  }

  @Test("The window loads at once when the visible month's own days are not loaded")
  func windowLoadsAtOnceForAnUncoveredMonth() throws {
    let calendar = try Self.calendar()
    let october = try Self.date(2026, 10, 1)
    // October 2026's grid runs from September 27 through November 7.
    #expect(Self.windowLoad(visible: october, loaded: nil, calendar: calendar) == .now)
    #expect(
      Self.windowLoad(
        visible: october,
        loaded: Self.bounds(
          aroundMonthStarting: try Self.date(2026, 4, 1), neighborMonths: 2, calendar: calendar),
        calendar: calendar) == .now)
    #expect(
      Self.windowLoad(
        visible: october, loaded: (from: "2026-09-27", to: "2026-11-06"), calendar: calendar) == .now)
    #expect(
      Self.windowLoad(
        visible: october, loaded: (from: "2026-09-28", to: "2026-11-07"), calendar: calendar) == .now)
  }

  @Test("The window waits for the swipe to settle when only a neighboring month is missing")
  func windowWaitsWhenOnlyANeighborIsMissing() throws {
    let calendar = try Self.calendar()
    let october = try Self.date(2026, 10, 1)
    #expect(
      Self.windowLoad(
        visible: october, loaded: (from: "2026-09-27", to: "2026-11-07"), calendar: calendar)
        == .afterSettling)
  }

  @Test("Nothing loads while the visible month and both months a swipe reveals are loaded")
  func windowIsLeftAloneWhenItCoversTheNeighbors() throws {
    let calendar = try Self.calendar()
    let october = try Self.date(2026, 10, 1)
    #expect(
      Self.windowLoad(
        visible: october,
        loaded: Self.bounds(aroundMonthStarting: october, neighborMonths: 1, calendar: calendar),
        calendar: calendar) == .none)
    #expect(
      Self.windowLoad(
        visible: october,
        loaded: Self.bounds(aroundMonthStarting: october, neighborMonths: 2, calendar: calendar),
        calendar: calendar) == .none)
  }

  @Test("After a load two months wide, the first swipe loads nothing and the next waits to settle")
  func windowAfterALoadServesTheFirstSwipe() throws {
    let calendar = try Self.calendar()
    let loaded = Self.bounds(
      aroundMonthStarting: try Self.date(2026, 10, 1), neighborMonths: 2, calendar: calendar)
    #expect(Self.windowLoad(visible: try Self.date(2026, 11, 1), loaded: loaded, calendar: calendar) == .none)
    #expect(
      Self.windowLoad(visible: try Self.date(2026, 12, 1), loaded: loaded, calendar: calendar)
        == .afterSettling)
    #expect(Self.windowLoad(visible: try Self.date(2027, 1, 1), loaded: loaded, calendar: calendar) == .now)
  }

  // MARK: Page and cell equality

  private static func actions(_ recorder: Recorder = Recorder()) -> MobileCalendarMonthGridActions {
    MobileCalendarMonthGridActions(
      choose: { _ in recorder.calls += 1 }, openEvent: { _ in recorder.calls += 1 },
      openTask: { _ in recorder.calls += 1 }, createEvent: { _ in recorder.calls += 1 },
      dropTasks: { _, _ in recorder.calls += 1 })
  }

  private static func monthSource(
    events: [CalendarTimelineEvent] = [], todayKey: String = "2026-10-14", calendar: Calendar
  ) throws -> MobileCalendarMonthPageSource {
    MobileCalendarMonthPageSource(
      events: events, tasks: [], currentMonthStart: try date(2026, 10, 1), weeks: 6,
      todayKey: todayKey, calendar: calendar)
  }

  @Test("A month page is the same page for the same month, source, and chosen day, whatever its actions")
  func monthPageEqualityComparesWhatItDraws() throws {
    let calendar = try Self.calendar()
    let source = try Self.monthSource(calendar: calendar)
    let page = MobileCalendarMonthPage(
      offset: 1, source: source, selectedKey: "2026-10-14", actions: Self.actions())
    #expect(
      page
        == MobileCalendarMonthPage(
          offset: 1, source: source, selectedKey: "2026-10-14", actions: Self.actions(Recorder())))
    #expect(
      page
        != MobileCalendarMonthPage(
          offset: 2, source: source, selectedKey: "2026-10-14", actions: Self.actions()))
    #expect(
      page
        != MobileCalendarMonthPage(
          offset: 1, source: source, selectedKey: "2026-10-15", actions: Self.actions()))
    #expect(
      page
        != MobileCalendarMonthPage(
          offset: 1, source: nil, selectedKey: "2026-10-14", actions: Self.actions()))
    #expect(
      page
        != MobileCalendarMonthPage(
          offset: 1, source: try Self.monthSource(todayKey: "2026-10-15", calendar: calendar),
          selectedKey: "2026-10-14", actions: Self.actions()))
    #expect(
      page
        != MobileCalendarMonthPage(
          offset: 1, source: try Self.monthSource(events: [Self.event("standup")], calendar: calendar),
          selectedKey: "2026-10-14", actions: Self.actions()))
  }

  @Test("Two placeholder pages of one month are the same page")
  func placeholderMonthPagesAreEqual() {
    #expect(
      MobileCalendarMonthPage(offset: 7, source: nil, selectedKey: "", actions: Self.actions())
        == MobileCalendarMonthPage(offset: 7, source: nil, selectedKey: "", actions: Self.actions()))
  }

  private static func cell(
    day: CalendarMonthGridDay, isToday: Bool = false, isSelected: Bool = false,
    style: MobileCalendarMonthCellStyle = .marks, dayNumberSize: CGFloat = 28,
    chipHeight: CGFloat = 17, recorder: Recorder = Recorder(), calendar: Calendar
  ) -> MobileCalendarMonthDayCell {
    MobileCalendarMonthDayCell(
      day: day, isToday: isToday, isSelected: isSelected, style: style,
      dayNumberSize: dayNumberSize, chipHeight: chipHeight, calendar: calendar,
      choose: { recorder.calls += 1 }, openEvent: { _ in recorder.calls += 1 },
      openTask: { _ in recorder.calls += 1 }, createEvent: { recorder.calls += 1 },
      dropTasks: { _ in recorder.calls += 1 })
  }

  @Test("A month cell is the same cell for the same day in the same state at the same size")
  func monthCellEqualityComparesWhatItDraws() throws {
    let calendar = try Self.calendar()
    let date = try Self.date(2026, 10, 14)
    let free = CalendarMonthGridDay(
      date: date, dayKey: "2026-10-14", isCurrentMonth: true, events: [], scheduledTasks: [])
    let busy = CalendarMonthGridDay(
      date: date, dayKey: "2026-10-14", isCurrentMonth: true, events: [Self.event("standup")],
      scheduledTasks: [])
    let cell = Self.cell(day: free, calendar: calendar)
    #expect(cell == Self.cell(day: free, recorder: Recorder(), calendar: calendar))
    #expect(cell != Self.cell(day: busy, calendar: calendar))
    #expect(cell != Self.cell(day: free, isToday: true, calendar: calendar))
    #expect(cell != Self.cell(day: free, isSelected: true, calendar: calendar))
    #expect(cell != Self.cell(day: free, style: .titled(maxChips: 3), calendar: calendar))
    #expect(cell != Self.cell(day: free, dayNumberSize: 32, calendar: calendar))
    #expect(cell != Self.cell(day: free, chipHeight: 20, calendar: calendar))
  }

  private static func dayInputs(
    startDate: Date, dayCount: Int = 1, events: [CalendarTimelineEvent] = [],
    pageWidth: CGFloat = 0, openDeletion: String? = nil, calendar: Calendar
  ) -> MobileCalendarDayPage.Inputs {
    MobileCalendarDayPage.Inputs(
      startDate: startDate, dayCount: dayCount, showsHeaders: true, circlesTodayInHeaders: true,
      opensDays: false, events: events, tasks: [], pageWidth: pageWidth, openDeletion: openDeletion,
      calendar: calendar)
  }

  private static func dayPage(
    _ inputs: MobileCalendarDayPage.Inputs, recorder: Recorder = Recorder()
  ) -> MobileCalendarDayPage {
    MobileCalendarDayPage(inputs: inputs) {
      MobileCalendarDayColumn(
        startDate: inputs.startDate, dayCount: inputs.dayCount, events: inputs.events,
        tasks: inputs.tasks, calendar: inputs.calendar,
        onTapEvent: { _ in recorder.calls += 1 }, deletion: .inert,
        onTapTask: { _ in recorder.calls += 1 }, onDropTask: { _, _ in recorder.calls += 1 },
        onTapEmpty: { _, _ in recorder.calls += 1 }, onReschedule: nil)
    }
  }

  @Test("A day page is the same page for the same days, events, and tasks, whatever its column's closures")
  func dayPageEqualityComparesWhatItDraws() throws {
    let calendar = try Self.calendar()
    let start = try Self.date(2026, 10, 14)
    let inputs = Self.dayInputs(startDate: start, calendar: calendar)
    let page = Self.dayPage(inputs)
    #expect(page == Self.dayPage(inputs, recorder: Recorder()))
    #expect(page != Self.dayPage(Self.dayInputs(startDate: try Self.date(2026, 10, 15), calendar: calendar)))
    #expect(page != Self.dayPage(Self.dayInputs(startDate: start, dayCount: 3, calendar: calendar)))
    #expect(
      page
        != Self.dayPage(
          Self.dayInputs(startDate: start, events: [Self.event("standup")], calendar: calendar)))
    // A page is built for the width its pager measured, so a new width redraws it.
    #expect(
      page != Self.dayPage(Self.dayInputs(startDate: start, pageWidth: 402, calendar: calendar)))
    // A deletion question opens and closes inside the column's dialogs, which
    // only a rebuilt column reads.
    let asking = Self.dayPage(
      Self.dayInputs(startDate: start, openDeletion: "2026-10-14/2026-10-14/standup", calendar: calendar))
    #expect(page != asking)
    #expect(
      asking
        == Self.dayPage(
          Self.dayInputs(
            startDate: start, openDeletion: "2026-10-14/2026-10-14/standup", calendar: calendar)))
  }

  @Test("A day page without a column differs from one with a column and equals another without")
  func placeholderDayPagesAreEqual() throws {
    let calendar = try Self.calendar()
    let live = Self.dayPage(Self.dayInputs(startDate: try Self.date(2026, 10, 14), calendar: calendar))
    #expect(MobileCalendarDayPage() == MobileCalendarDayPage())
    #expect(MobileCalendarDayPage() != live)
  }
}
