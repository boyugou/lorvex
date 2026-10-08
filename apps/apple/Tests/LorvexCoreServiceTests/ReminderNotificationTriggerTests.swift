import Foundation
import Testing
import UserNotifications

@testable import LorvexCore

/// A reminder fires at the instant it stores. Components that name no zone are
/// read again in the zone the device is in when the trigger fires, so a reminder
/// armed in Los Angeles and delivered after a flight to New York would arrive
/// three hours before its instant; a trigger pinned to UTC does not move.
@Suite("Reminder notification trigger")
struct ReminderNotificationTriggerTests {
  private let instantText = "2099-06-15T16:00:00Z"

  private func instant() throws -> Date {
    try #require(ISO8601DateFormatter().date(from: instantText))
  }

  private func expectPinned(_ trigger: UNNotificationTrigger?, to instant: Date) throws {
    let calendarTrigger = try #require(trigger as? UNCalendarNotificationTrigger)
    let components = calendarTrigger.dateComponents

    #expect(!calendarTrigger.repeats)
    #expect(components.timeZone?.secondsFromGMT() == 0)
    #expect(components.calendar?.identifier == .gregorian)
    #expect(
      [components.year, components.month, components.day, components.hour, components.minute, components.second]
        == [2099, 6, 15, 16, 0, 0])
    #expect(calendarTrigger.nextTriggerDate() == instant)
  }

  @Test("A task reminder's trigger is pinned to its instant in UTC")
  func taskReminderTriggerIsPinned() throws {
    let task = LorvexTask(
      id: "task-1", title: "Call", notes: "", priority: .p2, status: .open,
      dueDate: nil, estimatedMinutes: nil, tags: [],
      reminders: [TaskReminder(id: "r-1", reminderAt: instantText, status: nil)])
    let reminder = try #require(ScheduledTaskReminder.reminders(for: [task]).first)

    try expectPinned(reminder.notificationRequest.trigger, to: try instant())
  }

  @Test("A habit reminder's trigger is pinned to its instant in UTC")
  func habitReminderTriggerIsPinned() throws {
    let occurrence = DueHabitReminderOccurrence(
      policy: HabitReminderPolicy(
        id: "p1", habitID: "h1", habitName: "Stretch", reminderTime: "09:00", enabled: true,
        createdAt: "", updatedAt: ""),
      fireDate: try instant())
    let reminder = ScheduledHabitReminder(occurrence: occurrence, body: "Time for your habit")

    try expectPinned(reminder.notificationRequest.trigger, to: try instant())
  }

  @Test("A fraction of a second in the instant is dropped, never rounded up")
  func subsecondsAreDropped() throws {
    let trigger = UNCalendarNotificationTrigger.oneShot(at: try instant().addingTimeInterval(0.75))

    #expect(trigger.nextTriggerDate() == (try instant()))
  }
}
