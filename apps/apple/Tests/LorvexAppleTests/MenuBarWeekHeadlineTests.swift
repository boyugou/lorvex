import Foundation
import Testing

@testable import LorvexApple

/// The menu bar's Next 7 Days headline counts what the seven days after today
/// hold, so switching scope never leaves today's sentence over the week's list.
@Suite("Menu bar week headline")
struct MenuBarWeekHeadlineTests {
  @Test
  func namesAnEmptyWeek() {
    #expect(TodayCalmCopy.weekSentence(tasks: 0, events: 0) == "Nothing planned for the next 7 days.")
  }

  @Test
  func countsOnlyWhatTheWeekHolds() {
    #expect(TodayCalmCopy.weekSentence(tasks: 1, events: 0) == "1 task in the next 7 days.")
    #expect(TodayCalmCopy.weekSentence(tasks: 0, events: 3) == "3 events in the next 7 days.")
  }

  @Test
  func joinsTasksAndEvents() {
    #expect(TodayCalmCopy.weekSentence(tasks: 2, events: 1) == "2 tasks and 1 event in the next 7 days.")
  }
}
