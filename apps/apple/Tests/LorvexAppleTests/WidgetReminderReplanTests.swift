import Foundation
import LorvexCore
import LorvexDomain
import Testing
import UserNotifications

@testable import LorvexWidgetIntents

/// A widget's Complete runs in the widget extension while the app is suspended
/// or not running, so the widget re-plans the reminders itself
/// (`WidgetReminderReplan`) rather than leaving a repeat's next occurrence
/// unarmed until the app next runs.
@Suite("Widget reminder re-plan")
struct WidgetReminderReplanTests {
  private actor TaskSchedulerSpy: TaskReminderScheduling {
    private(set) var replacements: [[ScheduledTaskReminder]] = []
    func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async -> TaskReminderScheduleReport {
      replacements.append(reminders)
      return .scheduled(reminders.count)
    }
  }

  private actor HabitSchedulerSpy: HabitReminderScheduling {
    private(set) var replacements: [[DueHabitReminderOccurrence]] = []
    func replaceScheduledHabitReminders(
      for occurrences: [DueHabitReminderOccurrence]
    ) async -> TaskReminderScheduleReport {
      replacements.append(occurrences)
      return .scheduled(occurrences.count)
    }
  }

  private static let zone = TimeZone(identifier: "America/Los_Angeles") ?? .current

  private static func replan(
    status: UNAuthorizationStatus, tasks: TaskSchedulerSpy, habits: HabitSchedulerSpy,
    now: @escaping @Sendable () -> Date
  ) -> WidgetReminderReplan {
    WidgetReminderReplan(
      authorizationStatus: { status }, taskScheduler: { tasks }, habitScheduler: { habits },
      now: now)
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
  }

  /// `hour` o'clock on the day `clock` reads, in the seed's time zone.
  private static func time(_ hour: Int, on clock: () -> Date) -> Date {
    calendar.date(bySettingHour: hour, minute: 0, second: 0, of: clock()) ?? clock()
  }

  /// 08:00 in the seed's time zone on `day`, or on today when `day` is nil.
  private static func morningClock(on day: String?) -> @Sendable () -> Date {
    guard let day else { return seedMorningWallClock() }
    let parts = day.split(separator: "-").compactMap { Int($0) }
    let morning =
      calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 8))
      ?? Date()
    return { morning }
  }

  /// Today, and the day before the clocks go forward, when the next day's
  /// 10:00 is 23 hours away: the next occurrence keeps the wall-clock time.
  @Test(
    "a repeat completed from a widget has its next occurrence's reminder armed",
    arguments: [nil, "2027-03-13"] as [String?])
  func aRepeatCompletedFromAWidgetArmsItsNextOccurrence(day: String?) async throws {
    let clock = Self.morningClock(on: day)
    let core = try await makeSeededInMemoryCore(wallClock: clock)
    let repeating = try await core.createTask(
      TaskCreateDraft(
        title: "Water the plants", dueDate: clock(),
        recurrence: TaskRecurrenceRule(freq: .daily, interval: 1)))
    let other = try await core.createTask(title: "Call the bank", notes: "")
    let iso = LorvexDateFormatters.iso8601
    _ = try await core.setTaskReminders(
      taskID: repeating.id, reminderAts: [iso.string(from: Self.time(10, on: clock))])
    _ = try await core.setTaskReminders(
      taskID: other.id, reminderAts: [iso.string(from: Self.time(11, on: clock))])

    _ = try await LorvexSystemIntentRunner.completeTask(id: repeating.id, core: core)
    let tasks = TaskSchedulerSpy()
    let outcome = await Self.replan(
      status: .authorized, tasks: tasks, habits: HabitSchedulerSpy(), now: clock
    ).run(core: core)

    #expect(outcome?.taskReport.status == .scheduled)
    let armed = try #require(await tasks.replacements.last)
    // The pass replaces the whole pending set, so it keeps the other task's
    // reminder beside the new occurrence's.
    #expect(armed.contains { $0.taskID == other.id })
    #expect(!armed.contains { $0.taskID == repeating.id })
    let next = try #require(armed.first { $0.title == "Water the plants" })
    #expect(next.fireDate == Self.calendar.date(byAdding: .day, value: 1, to: Self.time(10, on: clock)))
  }

  @Test("a task's notes become the reminder's body only where this device allows it")
  func notesFollowThisDevicesPreference() async throws {
    let clock = seedMorningWallClock()
    let core = try await makeSeededInMemoryCore(wallClock: clock)
    let task = try await core.createTask(title: "Renew passport", notes: "Bring the old one")
    _ = try await core.setTaskReminders(
      taskID: task.id,
      reminderAts: [LorvexDateFormatters.iso8601.string(from: Self.time(10, on: clock))])

    func armedBody() async throws -> String? {
      let tasks = TaskSchedulerSpy()
      await Self.replan(status: .authorized, tasks: tasks, habits: HabitSchedulerSpy(), now: clock)
        .run(core: core)
      return try #require(await tasks.replacements.last).first { $0.taskID == task.id }?.body
    }

    #expect(try await armedBody() != "Bring the old one")
    _ = try await core.setPreference(
      key: PreferenceKeys.prefNotificationShowTaskNotes, value: "true")
    #expect(try await armedBody() == "Bring the old one")
  }

  /// Before the person has answered, arming would ask for permission, which
  /// the app's setup asks at a moment of its own; after a refusal there is
  /// nothing to arm, and the pending set is the app's to clear.
  @Test("without notifications allowed the pass touches nothing", arguments: [
    UNAuthorizationStatus.notDetermined, .denied,
  ])
  func withoutPermissionNothingIsTouched(status: UNAuthorizationStatus) async throws {
    let core = try await makeSeededInMemoryCore()
    let tasks = TaskSchedulerSpy()
    let habits = HabitSchedulerSpy()

    let outcome = await Self.replan(status: status, tasks: tasks, habits: habits, now: Date.init)
      .run(core: core)

    #expect(outcome == nil)
    #expect(await tasks.replacements.isEmpty)
    #expect(await habits.replacements.isEmpty)
  }

  @Test("a pass may arm once notifications are allowed, outright or quietly")
  func allowedStatuses() {
    #expect(WidgetReminderReplan.allowsArming(.authorized))
    #expect(WidgetReminderReplan.allowsArming(.provisional))
    #expect(!WidgetReminderReplan.allowsArming(.notDetermined))
    #expect(!WidgetReminderReplan.allowsArming(.denied))
  }

  /// Registering categories replaces the app's whole set, whose buttons the
  /// app titled in its own language. The notification center is unavailable
  /// to the test runner, so building this scheduler here also proves it does
  /// not reach for the center to register anything.
  @Test("the widget's task scheduler leaves the app's notification categories alone")
  func theWidgetsSchedulerRegistersNothing() {
    let scheduler = UserNotificationTaskReminderScheduler.outsideTheApp(fallbackBody: "Reminder")
    #expect(scheduler.candidates(for: [], includeNotes: false).isEmpty)
  }
}
