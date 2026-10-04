import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile
@testable import LorvexSystemIntents

private func summary(_ tokens: [String], locale identifier: String = "en_US") -> String {
  let locale = Locale(identifier: identifier)
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = locale
  return LorvexRecurrenceWeekdays.summary(tokens, calendar: calendar, locale: locale)
}

/// Weekdays read in the picker's Monday-first order as the language's own
/// narrow list, whatever order the rule stores them in.
@Test func recurrenceWeekdaysReadAsTheLanguagesList() {
  #expect(summary(["FR", "MO", "WE"]) == "Mon, Wed, Fri")
  #expect(summary(["FR", "MO", "WE"], locale: "es_ES") == "lun, mié y vie")
  #expect(summary(["FR", "MO", "WE"], locale: "zh_Hans_CN") == "周一、周三和周五")
  #expect(summary(["SU"]) == "Sun")
}

/// Plain weekdays start from the region's first weekday: Sunday in the
/// United States, Monday in Britain, Saturday in Egypt.
@Test func recurrenceWeekdaysStartTheWeekWhereTheRegionDoes() {
  #expect(summary(["MO", "SU", "SA"]) == "Sun, Mon, Sat")
  #expect(summary(["MO", "SU", "SA"], locale: "en_GB") == "Mon, Sat, Sun")
  #expect(summary(["MO", "SU", "SA"], locale: "en_US@fw=mon") == "Mon, Sat, Sun")
  let locale = Locale(identifier: "en_EG")
  var egypt = Calendar(identifier: .gregorian)
  egypt.locale = locale
  egypt.firstWeekday = 7
  #expect(LorvexRecurrenceWeekdays.summary(["MO", "SU", "SA"], calendar: egypt, locale: locale) == "Sat, Sun, Mon")
}

/// A habit's Monday-first weekday indices read like the same rule's codes.
@Test func recurrenceWeekdaysReadMondayFirstIndices() {
  let locale = Locale(identifier: "en_US")
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = locale
  #expect(
    LorvexRecurrenceWeekdays.summary(mondayFirst: [4, 0, 6], calendar: calendar, locale: locale)
      == "Sun, Mon, Fri")
  #expect(
    LorvexRecurrenceWeekdays.summary(mondayFirst: [9, 2], calendar: calendar, locale: locale) == "Wed",
    "an index outside the week is skipped")
}

/// The shown week's order, as Monday-first indices.
@Test func weekdayOrderStartsOnTheFirstWeekday() {
  func calendar(firstWeekday: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = firstWeekday
    return calendar
  }
  #expect(LorvexWeekdayOrder.mondayFirstIndices(calendar: calendar(firstWeekday: 1)) == [6, 0, 1, 2, 3, 4, 5])
  #expect(LorvexWeekdayOrder.mondayFirstIndices(calendar: calendar(firstWeekday: 2)) == [0, 1, 2, 3, 4, 5, 6])
  #expect(LorvexWeekdayOrder.mondayFirstIndices(calendar: calendar(firstWeekday: 7)) == [5, 6, 0, 1, 2, 3, 4])
  #expect(LorvexWeekdayOrder.sorted([0, 6, 5], calendar: calendar(firstWeekday: 1)) == [6, 0, 5])
  #expect(LorvexWeekdayOrder.sorted([0, 6, 5], calendar: calendar(firstWeekday: 7)) == [5, 6, 0])
}

/// A monthly or yearly rule's positioned weekdays read as "1st Mon" and "last
/// Fri", after the plain weekdays; an unreadable token stays as written, last.
@Test func recurrenceWeekdaysNamePositionedWeekdays() {
  #expect(summary(["1MO"]) == "1st Mon")
  #expect(summary(["+3WE"]) == "3rd Wed")
  #expect(summary(["-1FR"]) == "last Fri")
  #expect(summary(["-2FR"]) == "2nd-to-last Fri")
  #expect(summary(["-1FR", "2TU", "XX", "MO"]) == "Mon, 2nd Tue, last Fri, XX")
  #expect(summary(["0MO"]) == "0MO", "position 0 is not a position")
}

/// A Siri list names five results, then the count of the rest as its last item,
/// so the conjunction comes once. The list's separators follow the test
/// machine's region, so the expectations are built with the same list style.
@Test func siriListsNameFiveThenTheRest() {
  func list(_ items: [String]) -> String { items.formatted(.list(type: .and)) }
  let titles = ["A", "B", "C", "D", "E", "F", "G"]
  #expect(SystemIntentListSummary.names(Array(titles.prefix(2)), total: 2) == list(["A", "B"]))
  #expect(
    SystemIntentListSummary.names(Array(titles.prefix(5)), total: 5)
      == list(["A", "B", "C", "D", "E"]))
  #expect(
    SystemIntentListSummary.names(titles, total: 7) == list(["A", "B", "C", "D", "E", "2 more"]))
  #expect(
    SystemIntentListSummary.names(Array(titles.prefix(3)), total: 40)
      == list(["A", "B", "C", "37 more"]),
    "a page of results still counts every match")
  #expect(SystemIntentListSummary.names(titles, total: 7, shown: 7) == list(titles))
}

/// The task detail's one-line repeat label (the rule's cadence) names its
/// weekdays the same way as the full summary, which starts with it.
@Test func recurrenceCadenceNamesWeekdaysLikeTheSummary() {
  let weekly = TaskRecurrenceRule(freq: .weekly, byDay: ["FR", "MO"], count: 4)
  #expect(weekly.localizedCadence.hasSuffix(" · " + LorvexRecurrenceWeekdays.summary(["FR", "MO"])))
  #expect(weekly.localizedDisplaySummary().hasPrefix(weekly.localizedCadence))
  let monthly = TaskRecurrenceRule(freq: .monthly, byDay: ["-1FR"])
  #expect(monthly.localizedCadence.hasSuffix(" · " + LorvexRecurrenceWeekdays.summary(["-1FR"])))
}

/// A phrase that follows other words starts a row with a capital, by the
/// rules of the given language; a script without case is unchanged.
@MainActor
@Test func sentenceCaseFollowsTheLanguage() {
  let english = Locale(identifier: "en_US")
  let turkish = Locale(identifier: "tr_TR")
  #expect(TaskDetailView.sentenceCased("the same day", locale: english) == "The same day")
  #expect(TaskDetailView.sentenceCased("iki gün önce", locale: turkish) == "İki gün önce")
  #expect(MobileTaskProperties.sentenceCased("iki gün önce", locale: turkish) == "İki gün önce")
  #expect(MobileTaskProperties.sentenceCased("当天", locale: english) == "当天")
}
