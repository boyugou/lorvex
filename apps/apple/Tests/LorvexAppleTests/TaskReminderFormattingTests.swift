import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@Test
func taskReminderDisplaySummaryFormatsISODate() {
  let reminder = TaskReminder(
    id: "reminder-format",
    reminderAt: "2026-05-24T12:00:00Z",
    status: "pending"
  )

  #expect(reminder.displaySummary.contains("2026"))
  #expect(!reminder.displaySummary.contains("T12:00:00Z"))
}

@Test
func taskReminderDisplaySummaryFallsBackToRawString() {
  let reminder = TaskReminder(
    id: "reminder-raw",
    reminderAt: "not-a-date",
    status: nil
  )

  #expect(reminder.displaySummary == "not-a-date")
}

@Test
func taskReminderDisplayUsesSuppliedProductTimezone() throws {
  let reminder = TaskReminder(
    id: "reminder-product-zone",
    reminderAt: "2026-07-22T16:00:00Z",
    status: "pending")
  let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
  let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
  let locale = Locale(identifier: "en_US_POSIX")

  let losAngelesDisplay = reminder.displaySummary(timeZone: losAngeles, locale: locale)
  let tokyoDisplay = reminder.displaySummary(timeZone: tokyo, locale: locale)

  #expect(losAngelesDisplay.contains("Jul 22"))
  #expect(losAngelesDisplay.contains("9:00"))
  #expect(tokyoDisplay.contains("Jul 23"))
  #expect(tokyoDisplay.contains("1:00"))
  #expect(losAngelesDisplay != tokyoDisplay)
}

@Test
func taskReminderTomorrowMorningIsProductWallTimeAcrossDST() throws {
  let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
  let now = try #require(LorvexDateFormatters.iso8601.date(from: "2026-03-07T17:00:00Z"))
  let tomorrow = TaskReminderDateTime.defaultDate(now: now, timeZone: losAngeles)
  let components = TaskReminderDateTime.calendar(timeZone: losAngeles)
    .dateComponents([.year, .month, .day, .hour, .minute], from: tomorrow)

  #expect(components.year == 2026)
  #expect(components.month == 3)
  #expect(components.day == 8)
  #expect(components.hour == 9)
  #expect(components.minute == 0)
  #expect(tomorrow.timeIntervalSince(now) == 23 * 3600)
}

@Test
func taskReminderEveningUsesProductWallTimeAcrossFallBack() throws {
  let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
  let now = try #require(LorvexDateFormatters.iso8601.date(from: "2026-11-01T08:30:00Z"))
  let evening = try #require(TaskReminderDateTime.presetDate(
    .thisEvening,
    now: now,
    timeZone: losAngeles))
  let components = TaskReminderDateTime.calendar(timeZone: losAngeles)
    .dateComponents([.year, .month, .day, .hour, .minute], from: evening)

  #expect(components.year == 2026)
  #expect(components.month == 11)
  #expect(components.day == 1)
  #expect(components.hour == 18)
  #expect(components.minute == 0)
}

@Test
func taskReminderInOneHourRemainsAbsoluteAcrossDST() throws {
  let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
  let now = try #require(LorvexDateFormatters.iso8601.date(from: "2026-11-01T08:30:00Z"))
  let oneHour = try #require(TaskReminderDateTime.presetDate(
    .inOneHour,
    now: now,
    timeZone: losAngeles))

  #expect(oneHour.timeIntervalSince(now) == 3600)
}

@MainActor
@Test
func appStoreReminderDefaultUsesTheLoadedTodayTimezone() throws {
  let store = AppStore(core: try makeInMemoryCore())
  let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
  let now = try #require(LorvexDateFormatters.iso8601.date(from: "2026-07-21T23:30:00Z"))
  store.today = TodaySnapshot(
    focusTitle: "Today",
    summary: "",
    tasks: [],
    logicalDay: "2026-07-22",
    timezone: tokyo.identifier,
    localChangeSequence: 0)

  store.resetTaskDetailReminderDate(now: now)
  let components = TaskReminderDateTime.calendar(timeZone: tokyo)
    .dateComponents([.year, .month, .day, .hour, .minute], from: store.taskDetailReminderDate)

  #expect(components.year == 2026)
  #expect(components.month == 7)
  #expect(components.day == 23)
  #expect(components.hour == 9)
  #expect(components.minute == 0)
}

@Test
func taskReminderSurfacesWireTheProductTimezoneAndNoDateOnlyDuePreset() throws {
  let appleRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let mobileComposer = try String(
    contentsOf: appleRoot.appending(path: "Sources/LorvexMobile/MobileTaskComposerRows.swift"),
    encoding: .utf8)
  let mobileDetail = try String(
    contentsOf: appleRoot.appending(path: "Sources/LorvexMobile/MobileTaskDetailContent.swift"),
    encoding: .utf8)
  let macReminder = try String(
    contentsOf: appleRoot.appending(path: "Sources/LorvexApple/Views/TaskDetailReminderSection.swift"),
    encoding: .utf8)

  #expect(mobileComposer.contains("TaskReminderDateTime.defaultDate(timeZone: timeZone)"))
  #expect(mobileComposer.contains(".environment(\\.timeZone, timeZone)"))
  #expect(!mobileComposer.contains("oneHourBeforeDue"))
  #expect(!mobileComposer.contains("let dueDate:"))
  #expect(mobileDetail.contains("MobileReminderComposerRow(timeZone: timeZone)"))
  #expect(mobileDetail.contains("reminder: reminder,\n              timeZone: timeZone"))
  #expect(macReminder.contains("timeZone: store.logicalTimeZone"))
  #expect(macReminder.contains(".environment(\\.timeZone, timeZone)"))
  #expect(macReminder.contains("reminder.displaySummary(timeZone: timeZone)"))
}
