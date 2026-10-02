import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

/// Switching the calendar between its modes keeps the day the person was
/// looking at: every mode shows the period that holds it, and paging keeps
/// its weekday.
struct CalendarModeSwitchTests {
  /// Thursday, October 1, 2026, on a Gregorian calendar in UTC.
  private static let thursday = day(2026, 10, 1)

  private static func calendar(firstWeekday: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    calendar.firstWeekday = firstWeekday
    return calendar
  }

  private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar(firstWeekday: 2).date(from: DateComponents(year: year, month: month, day: day))
      ?? .distantPast
  }

  @Test("Mac: after ten days of stepping in Day mode, Week and Month show that day's period")
  func macModesShowThePeriodHoldingTheAnchor() {
    let calendar = Self.calendar(firstWeekday: 2)
    var anchor = Self.thursday
    for _ in 0..<10 {
      anchor = CalendarPresentationMode.day.anchor(anchor, steppedBy: 1, calendar: calendar)
    }
    #expect(anchor == Self.day(2026, 10, 11))
    #expect(
      CalendarVisiblePeriod(mode: .week, anchor: anchor, calendar: calendar).start
        == Self.day(2026, 10, 5))
    #expect(
      CalendarVisiblePeriod(mode: .month, anchor: anchor, calendar: calendar).start
        == Self.day(2026, 10, 1))
    // A Sunday-first week starts on the Sunday itself.
    #expect(
      CalendarVisiblePeriod(mode: .week, anchor: anchor, calendar: Self.calendar(firstWeekday: 1))
        .start == Self.day(2026, 10, 11))
  }

  @Test("Mac: a week step keeps the weekday and a month step clamps to the month's length")
  func macStepsKeepTheDay() {
    let calendar = Self.calendar(firstWeekday: 2)
    #expect(
      CalendarPresentationMode.week.anchor(Self.thursday, steppedBy: 1, calendar: calendar)
        == Self.day(2026, 10, 8))
    #expect(
      CalendarPresentationMode.week.anchor(Self.thursday, steppedBy: -2, calendar: calendar)
        == Self.day(2026, 9, 17))
    #expect(
      CalendarPresentationMode.month.anchor(Self.day(2026, 1, 31), steppedBy: 1, calendar: calendar)
        == Self.day(2026, 2, 28))
  }

  @Test("Mac: another day in the visible period leaves the period equal, so nothing refetches")
  func macPeriodIgnoresDaysInsideIt() {
    let calendar = Self.calendar(firstWeekday: 2)
    let week = CalendarVisiblePeriod(mode: .week, anchor: Self.thursday, calendar: calendar)
    #expect(week == CalendarVisiblePeriod(mode: .week, anchor: Self.day(2026, 10, 4), calendar: calendar))
    #expect(week != CalendarVisiblePeriod(mode: .week, anchor: Self.day(2026, 10, 5), calendar: calendar))
    #expect(week != CalendarVisiblePeriod(mode: .month, anchor: Self.thursday, calendar: calendar))
  }

  @Test("iOS: a day handed from Day mode to Week mode and back opens the same day")
  func mobileRoundTripKeepsTheDay() {
    let calendar = Self.calendar(firstWeekday: 2)
    let today = Self.thursday
    let viewed = Self.day(2026, 10, 11)
    #expect(
      MobileCalendarDayView.pageOffset(showing: viewed, weekMode: false, today: today, calendar: calendar)
        == 10)

    let weekPage = MobileCalendarDayView.pageOffset(
      showing: viewed, weekMode: true, today: today, calendar: calendar)
    #expect(weekPage == 1)
    let index = MobileCalendarDayView.dayIndexInWeek(of: viewed, calendar: calendar)
    #expect(index == 6)

    let visibleWeekStart = Self.day(2026, 10, 5)
    let handedBack = MobileCalendarDayView.modeSwitchDay(
      weekMode: true, visibleDate: visibleWeekStart, weekDayIndex: index, calendar: calendar)
    #expect(handedBack == viewed)
  }

  @Test("iOS: paging weeks keeps the focused weekday")
  func mobileWeekPagingKeepsTheWeekday() {
    let calendar = Self.calendar(firstWeekday: 2)
    let index = MobileCalendarDayView.dayIndexInWeek(of: Self.thursday, calendar: calendar)
    #expect(index == 3)
    // Two weeks on, the week starts on Monday, October 12.
    let handedOver = MobileCalendarDayView.modeSwitchDay(
      weekMode: true, visibleDate: Self.day(2026, 10, 12), weekDayIndex: index, calendar: calendar)
    #expect(handedOver == Self.day(2026, 10, 15))
    // Day mode hands over its first visible day as is.
    #expect(
      MobileCalendarDayView.modeSwitchDay(
        weekMode: false, visibleDate: Self.day(2026, 10, 12), weekDayIndex: index, calendar: calendar)
        == Self.day(2026, 10, 12))
  }

  @Test("iOS: week pages count whole weeks by the calendar's first weekday, before and after today")
  func mobileWeekPagesFollowTheFirstWeekday() {
    let sundayFirst = Self.calendar(firstWeekday: 1)
    let sunday = Self.day(2026, 10, 11)
    #expect(
      MobileCalendarDayView.pageOffset(showing: sunday, weekMode: true, today: Self.thursday, calendar: sundayFirst)
        == 2)
    #expect(MobileCalendarDayView.dayIndexInWeek(of: sunday, calendar: sundayFirst) == 0)
    #expect(
      MobileCalendarDayView.pageOffset(
        showing: Self.day(2026, 9, 20), weekMode: true, today: Self.thursday,
        calendar: Self.calendar(firstWeekday: 2)) == -2)
  }
}
