import Foundation
import LorvexCore
import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreCreatesCalendarEventThroughCore() async throws {
  let date = Date(timeIntervalSince1970: 1_779_494_400)
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" }, now: { date })

  await store.refresh()
  store.calendarDraft = MobileCalendarDraft(
    title: "  Product Review  ",
    date: date,
    startTime: Date(timeIntervalSince1970: 1_779_530_400),
    endTime: Date(timeIntervalSince1970: 1_779_534_000),
    allDay: false,
    location: "  Studio  ",
    notes: "  Bring notes  "
  )

  let created = await store.createDraftCalendarEvent()
  let event = try #require(store.calendarTimeline?.events.first { $0.title == "Product Review" })

  #expect(created)
  #expect(event.allDay == false)
  #expect(event.startTime != nil)
  #expect(event.endTime != nil)
  #expect(event.location == "Studio")
  #expect(store.calendarDraft == MobileCalendarDraft(now: { date }))
  #expect(store.errorMessage == nil)
  #expect(store.isMutatingCalendarEvent == false)
}

@MainActor
@Test
func mobileStoreDeletesEditableCalendarEventThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let event = try await core.createCalendarEvent(
    title: "Delete from mobile",
    startDate: "2026-05-24",
    endDate: nil,
    startTime: nil,
    endTime: nil,
    allDay: true,
    location: nil,
    notes: nil
  )
  await store.refresh()

  let deleted = await store.deleteCalendarEvent(event)
  let matches = try await core.searchCalendarEvents(
    query: "Delete from mobile",
    from: "2026-05-23",
    to: "2026-06-06",
    limit: 10
  )

  #expect(deleted)
  #expect(store.calendarTimeline?.events.contains(where: { $0.id == event.id }) == false)
  #expect(matches.isEmpty)
  #expect(store.errorMessage == nil)
  #expect(store.isMutatingCalendarEvent == false)
}

@MainActor
@Test
func calendarServiceRoundTripsMultiDayEndDate() async throws {
  let core = try await makeSeededInMemoryCore()

  let created = try await core.createCalendarEvent(
    title: "Conference trip",
    startDate: "2026-06-01",
    endDate: "2026-06-03",
    startTime: nil,
    endTime: nil,
    allDay: true,
    location: nil,
    notes: nil
  )
  #expect(created.startDate == "2026-06-01")
  #expect(created.endDate == "2026-06-03")

  let extended = try await core.updateCalendarEvent(
    id: created.id,
    title: nil,
    startDate: nil,
    endDate: "2026-06-05",
    startTime: nil,
    endTime: nil,
    allDay: nil,
    location: nil,
    notes: nil
  )
  #expect(extended.endDate == "2026-06-05")
  #expect(extended.startDate == "2026-06-01")

  // A nil endDate on update leaves the existing multi-day span untouched.
  let untouched = try await core.updateCalendarEvent(
    id: created.id,
    title: "Conference trip (final)",
    startDate: nil,
    endDate: nil,
    startTime: nil,
    endTime: nil,
    allDay: nil,
    location: nil,
    notes: nil
  )
  #expect(untouched.endDate == "2026-06-05")
  #expect(untouched.title == "Conference trip (final)")
}

@MainActor
@Test
func mobileStoreUpdatesEditableCalendarEventThroughCore() async throws {
  let date = Date(timeIntervalSince1970: 1_779_494_400)
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try #require(try await core.loadToday().logicalDay)
  let eventDay = try #require(LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: 1))
  let store = MobileStore(core: core, todayString: { logicalDay }, now: { date })

  let event = try await core.createCalendarEvent(
    title: "Draft review",
    startDate: eventDay,
    endDate: nil,
    startTime: nil,
    endTime: nil,
    allDay: true,
    location: "Desk",
    notes: nil
  )
  await store.refresh()
  store.prepareCalendarDraft(for: event)
  store.calendarDraft.title = "  Updated review  "
  store.calendarDraft.location = "  Studio  "

  let updated = await store.updateCalendarEvent(event)
  let eventAfterUpdate = try #require(
    store.calendarTimeline?.events.first { $0.id == event.id }
  )

  #expect(updated)
  #expect(eventAfterUpdate.title == "Updated review")
  #expect(eventAfterUpdate.location == "Studio")
  #expect(store.calendarDraft == MobileCalendarDraft(now: { date }))
  #expect(store.errorMessage == nil)
  #expect(store.isMutatingCalendarEvent == false)
}

@MainActor
@Test
func mobileStoreExportsCalendarICSThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try #require(try await core.loadToday().logicalDay)
  let eventDay = try #require(LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: 1))
  let store = MobileStore(core: core, todayString: { logicalDay })

  await store.refresh()
  _ = try await core.createCalendarEvent(
    title: "Mobile ICS export",
    startDate: eventDay,
    endDate: nil,
    startTime: "09:00",
    endTime: "09:30",
    allDay: false,
    location: "Studio",
    notes: nil
  )
  let ics = try #require(await store.exportCalendarICS())

  #expect(ics.contains("BEGIN:VCALENDAR"))
  #expect(ics.contains("END:VCALENDAR"))
  #expect(ics.contains("Mobile ICS export"))
  #expect(store.errorMessage == nil)
  #expect(store.isExportingCalendarICS == false)
}

@MainActor
@Test
func mobileStoreLoadsScheduledTasksForCalendarGrid() async throws {
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try #require(try await core.loadToday().logicalDay)
  let store = MobileStore(core: core, todayString: { logicalDay })
  let plannedDate = try #require(
    PlannedDayBridge.storageDate(forLogicalDay: logicalDay, addingDays: 1))

  let task = try await core.importRemoteTask(
    id: UUID().uuidString.lowercased(),
    title: "Scheduled from mobile calendar",
    notes: "",
    aiNotes: nil,
    priority: .p2,
    status: .open,
    estimatedMinutes: nil,
    plannedDate: plannedDate,
    tags: [],
    dependsOn: []
  )

  await store.refresh()

  #expect(store.calendarScheduledTasks.contains { $0.id == task.id })
}

@MainActor
@Test
func mobileStorePlansDroppedTaskOntoCalendarDay() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  let targetDay = try #require(ISO8601DateFormatter().date(from: "2026-06-02T12:00:00Z"))

  await store.refresh()
  await store.planTask(LorvexPreviewSeedID.venueTask, on: targetDay)

  #expect(store.errorMessage == nil)
  #expect(store.isMutatingTask == false)
  let planned = try await core.loadTask(id: LorvexPreviewSeedID.venueTask)
  // The planned date is storage-frame (the user's local day at UTC midnight):
  // its UTC day must equal the local day the drop targeted.
  #expect(
    planned.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:))
      == LorvexDateFormatters.ymd.string(from: targetDay))
  #expect(planned.id == LorvexPreviewSeedID.venueTask)
}

// MARK: - Drag-to-reschedule (iPhone day-view long-press-then-drag)

@MainActor
@Test
func mobileStoreReschedulesTimedEventPreservingDuration() async throws {
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try #require(try await core.loadToday().logicalDay)
  let store = MobileStore(core: core, todayString: { logicalDay })
  await store.refresh()
  let original = try await core.createCalendarEvent(
    title: "Strategy session",
    startDate: logicalDay,
    endDate: nil,
    startTime: "09:00",
    endTime: "10:30",
    allDay: false,
    location: nil,
    notes: nil
  )
  await store.refresh()

  let newStart = try localDate(on: logicalDay, hour: 14, minute: 0)
  let newEnd = try localDate(on: logicalDay, hour: 15, minute: 30)

  let ok = await store.rescheduleCalendarEvent(original, newStart: newStart, newEnd: newEnd)
  #expect(ok)
  let updated = try #require(store.calendarTimeline?.events.first { $0.id == original.id })
  #expect(updated.startTime == "14:00")
  #expect(updated.endTime == "15:30")
  #expect(updated.title == "Strategy session")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreReschedulesEventAcrossDays() async throws {
  // Cross-column drag on the iPad 3-day variant: a Tuesday block dragged
  // onto Wednesday must land on Wednesday, not still on Tuesday. The store
  // takes raw newStart / newEnd Dates so it doesn't itself constrain to the
  // event's original date — guards against a future refactor that mistakenly
  // pins startDate to the input event.
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try #require(try await core.loadToday().logicalDay)
  let targetDay = try #require(LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: 1))
  let store = MobileStore(core: core, todayString: { logicalDay })
  await store.refresh()
  let original = try await core.createCalendarEvent(
    title: "Cross-day move",
    startDate: logicalDay,
    endDate: nil,
    startTime: "09:00",
    endTime: "10:00",
    allDay: false,
    location: nil,
    notes: nil
  )
  await store.refresh()

  let newStart = try localDate(on: targetDay, hour: 14, minute: 0)
  let newEnd = try localDate(on: targetDay, hour: 15, minute: 0)

  let ok = await store.rescheduleCalendarEvent(original, newStart: newStart, newEnd: newEnd)
  #expect(ok)
  let updated = try #require(store.calendarTimeline?.events.first { $0.id == original.id })
  #expect(updated.startDate == targetDay)
  #expect(updated.startTime == "14:00")
  #expect(updated.endTime == "15:00")
}

private func localDate(on logicalDay: String, hour: Int, minute: Int) throws -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .autoupdatingCurrent
  let day = try #require(
    PlannedDayBridge.displayDate(forLogicalDay: logicalDay, calendar: calendar))
  return try #require(
    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day))
}

@MainActor
@Test
func mobileStoreRescheduleSkipsMultiDayEvent() async throws {
  // Mobile path is doubly load-bearing here — the duration calculation
  // (end-minute - start-minute in same-day minutes) goes negative for an
  // event spanning midnight, which would produce newEnd < newStart.
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-22" })
  await store.refresh()
  let multiDay = CalendarTimelineEvent(
    id: "overnight", title: "Late session", source: "lorvex", editable: true,
    startDate: "2026-05-22", startTime: "23:00", endDate: "2026-05-23", endTime: "01:00",
    allDay: false, location: nil, color: nil, eventType: "event",
    timezone: nil, isRecurring: false)
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian); comps.timeZone = .current
  comps.year = 2026; comps.month = 5; comps.day = 22; comps.hour = 11; comps.minute = 0
  let newStart = try #require(comps.date)
  comps.hour = 12; comps.minute = 0
  let newEnd = try #require(comps.date)

  let ok = await store.rescheduleCalendarEvent(multiDay, newStart: newStart, newEnd: newEnd)
  #expect(ok == false)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreRescheduleSkipsRecurringEvent() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let recurring = CalendarTimelineEvent(
    id: "weekly", title: "Standup", source: "lorvex", editable: true,
    startDate: "2026-05-23", startTime: "09:00", endDate: nil, endTime: "09:30",
    allDay: false, location: nil, color: nil, eventType: "event",
    timezone: nil, isRecurring: true)
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian); comps.timeZone = .current
  comps.year = 2026; comps.month = 5; comps.day = 23; comps.hour = 11; comps.minute = 0
  let newStart = try #require(comps.date)
  comps.hour = 11; comps.minute = 30
  let newEnd = try #require(comps.date)

  let ok = await store.rescheduleCalendarEvent(recurring, newStart: newStart, newEnd: newEnd)
  #expect(ok == false)
  #expect(store.errorMessage == nil)
}
