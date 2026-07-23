import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple

@Suite("Calendar ICS export")
struct CalendarICSExportTests {
  @Test
  func exportProducesValidICSEnvelope() async throws {
    let core = try await makeSeededInMemoryCore()
    let ics = try await core.exportCalendarICS(from: nil, to: nil)
    #expect(ics.hasPrefix("BEGIN:VCALENDAR"))
    #expect(ics.contains("END:VCALENDAR"))
    #expect(ics.contains("VERSION:2.0"))
  }

  @Test
  func exportWithExplicitRangeFiltersEvents() async throws {
    let core = try await makeSeededInMemoryCore()
    // The seeded core carries a calendar event; export a narrow past range
    // to confirm an empty range still produces valid ICS structure.
    let ics = try await core.exportCalendarICS(from: "1990-01-01", to: "1990-01-31")
    #expect(ics.hasPrefix("BEGIN:VCALENDAR"))
    #expect(ics.contains("END:VCALENDAR"))
    #expect(!ics.contains("BEGIN:VEVENT"), "No events expected in 1990 date range")
  }

  @Test
  func defaultExportWindowUsesConfiguredProductDay() async throws {
    let core = try makeInMemoryCore()
    let now = Date()
    let deviceDay = LorvexDateFormatters.ymd.string(from: now)
    let candidates = ["Pacific/Kiritimati", "Pacific/Pago_Pago"]
    let selected = try #require(candidates.compactMap { name -> (String, String)? in
      let day = Timezone.todayYmdForTimezoneName(
        now: now, timezoneName: name, systemFallback: .current)
      return day == deviceDay ? nil : (name, day)
    }.first)
    _ = try await core.setPreference(key: "timezone", value: selected.0)

    // Pick the product-window boundary that lies outside the old device-local
    // default: day 0 when product time is behind, day 30 when it is ahead.
    let eventDay = selected.1 < deviceDay
      ? selected.1
      : try #require(LorvexDateFormatters.ymdUTCAddingDays(selected.1, days: 30))
    let event = try await core.createCalendarEvent(
      title: "Product-zone boundary", startDate: eventDay, endDate: nil,
      startTime: nil, endTime: nil, allDay: true,
      location: nil, notes: nil, recurrence: nil, timezone: selected.0,
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)

    let ics = try await core.exportCalendarICS(from: nil, to: nil)
    #expect(ics.contains("UID:\(event.id)@lorvex"))
  }

  @Test
  func exportPreservesRecurringReplacementIdentityAndOnlyExdatesCancellations() async throws {
    let core = try await makeSeededInMemoryCore()
    let master = try await core.createCalendarEvent(
      title: "Daily planning",
      startDate: "2030-01-01",
      endDate: nil,
      startTime: "09:00",
      endTime: "09:30",
      allDay: false,
      location: nil,
      notes: nil,
      recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "UTC",
      url: nil,
      color: nil,
      eventType: nil,
      personName: nil,
      attendees: nil)

    _ = try await core.editScopedCalendarEvent(
      eventID: master.id,
      occurrenceDate: "2030-01-02",
      scope: "this_only",
      updates: ScopedCalendarEventUpdates(
        title: "Moved planning",
        startDate: "2030-01-04",
        startTime: "11:00",
        endTime: "11:30"))
    _ = try await core.deleteScopedCalendarEvent(
      eventID: master.id,
      occurrenceDate: "2030-01-03",
      scope: "this_only")

    let ics = try await core.exportCalendarICS(
      from: "2030-01-01", to: "2030-01-10")

    #expect(ics.contains("UID:\(master.id)@lorvex"))
    #expect(ics.contains("RECURRENCE-ID:20300102T090000Z"))
    #expect(ics.contains("DTSTART:20300104T110000Z"))
    #expect(!ics.contains("EXDATE:20300102T090000Z"))
    #expect(ics.contains("EXDATE:20300103T090000Z"))
  }

  @Test
  func timedReplacementMovedOutOfRangeKeepsItsRecurrenceComponent() async throws {
    let core = try await makeSeededInMemoryCore()
    let master = try await core.createCalendarEvent(
      title: "Daily sync", startDate: "2031-01-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    _ = try await core.editScopedCalendarEvent(
      eventID: master.eventID, occurrenceDate: "2031-01-02", scope: "this_only",
      updates: ScopedCalendarEventUpdates(
        title: "Moved out", startDate: "2031-02-01", startTime: "14:00",
        endTime: "14:30"))

    let ics = try await core.exportCalendarICS(from: "2031-01-01", to: "2031-01-10")

    #expect(ics.contains("RECURRENCE-ID:20310102T090000Z"))
    #expect(ics.contains("DTSTART:20310201T140000Z"))
    #expect(!ics.contains("EXDATE:20310102T090000Z"))
  }

  @Test
  func allDayReplacementMovedIntoRangeIncludesItsMasterComponent() async throws {
    let core = try await makeSeededInMemoryCore()
    let master = try await core.createCalendarEvent(
      title: "Weekly checkpoint", startDate: "2031-03-20", endDate: nil,
      startTime: nil, endTime: nil, allDay: true,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .weekly),
      timezone: nil, url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    _ = try await core.editScopedCalendarEvent(
      eventID: master.eventID, occurrenceDate: "2031-03-20", scope: "this_only",
      updates: ScopedCalendarEventUpdates(
        title: "Moved in", startDate: "2031-03-05"))

    let ics = try await core.exportCalendarICS(from: "2031-03-01", to: "2031-03-10")

    #expect(ics.contains("RECURRENCE-ID;VALUE=DATE:20310320"))
    #expect(ics.contains("DTSTART;VALUE=DATE:20310305"))
    #expect(ics.contains("RRULE:FREQ=WEEKLY"))
    #expect(ics.components(separatedBy: "UID:\(master.eventID)@lorvex").count - 1 == 2)
  }

  @Test
  func selectedSeriesExportsItsWholeDecisionComponentBeyondRequestedRange() async throws {
    let core = try await makeSeededInMemoryCore()
    let master = try await core.createCalendarEvent(
      title: "Daily component", startDate: "2032-01-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    _ = try await core.editScopedCalendarEvent(
      eventID: master.eventID, occurrenceDate: "2032-03-01", scope: "this_only",
      updates: ScopedCalendarEventUpdates(
        title: "Far replacement", startDate: "2032-04-01", startTime: "12:00",
        endTime: "12:30"))
    _ = try await core.deleteScopedCalendarEvent(
      eventID: master.eventID, occurrenceDate: "2032-05-01", scope: "this_only")

    let ics = try await core.exportCalendarICS(from: "2032-01-01", to: "2032-01-07")

    #expect(ics.contains("RECURRENCE-ID:20320301T090000Z"))
    #expect(ics.contains("DTSTART:20320401T120000Z"))
    #expect(ics.contains("EXDATE:20320501T090000Z"))
  }

  @Test
  func endedSeriesDoesNotConsumeRangeSelectionOrOrphanSelectedDecisions() async throws {
    let core = try await makeSeededInMemoryCore()
    let ended = try await core.createCalendarEvent(
      title: "Ended history", startDate: "2029-01-01", endDate: nil,
      startTime: "08:00", endTime: "08:30", allDay: false,
      location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .daily, until: "2029-01-02"),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    let selected = try await core.createCalendarEvent(
      title: "Current component", startDate: "2030-01-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .daily, until: "2030-01-05"),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    _ = try await core.editScopedCalendarEvent(
      eventID: selected.eventID, occurrenceDate: "2030-01-02", scope: "this_only",
      updates: ScopedCalendarEventUpdates(
        title: "Moved current occurrence", startDate: "2030-02-01",
        startTime: "12:00", endTime: "12:30"))
    _ = try await core.deleteScopedCalendarEvent(
      eventID: selected.eventID, occurrenceDate: "2030-01-03", scope: "this_only")

    let ics = try await core.exportCalendarICS(from: "2030-01-01", to: "2030-01-05")

    #expect(!ics.contains("UID:\(ended.eventID)@lorvex"))
    #expect(ics.contains("UID:\(selected.eventID)@lorvex"))
    #expect(ics.contains("RECURRENCE-ID:20300102T090000Z"))
    #expect(ics.contains("DTSTART:20300201T120000Z"))
    #expect(ics.contains("EXDATE:20300103T090000Z"))
  }

  @Test
  func exportClipsEachSegmentAtItsNextDurableCutoverWithoutChangingStoredRecurrence()
    async throws
  {
    let core = try await makeSeededInMemoryCore()
    let root = try await core.createCalendarEvent(
      title: "Root cadence", startDate: "2033-01-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    let firstSplit = try await core.editScopedCalendarEvent(
      eventID: root.eventID, occurrenceDate: "2033-01-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "First tail"))
    let firstTail = try #require(firstSplit.replacementEvent)
    let secondSplit = try await core.editScopedCalendarEvent(
      eventID: firstTail.eventID, occurrenceDate: "2033-01-05", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Second tail"))
    let secondTail = try #require(secondSplit.replacementEvent)

    let storedRoot = try #require(try await core.getCalendarEvent(id: root.eventID))
    let storedFirst = try #require(try await core.getCalendarEvent(id: firstTail.eventID))
    #expect(storedRoot.recurrenceRule?.contains(#""UNTIL""#) == false)
    #expect(storedFirst.recurrenceRule?.contains(#""UNTIL""#) == false)

    let ics = try await core.exportCalendarICS(from: "2033-01-01", to: "2033-01-10")
    let rootComponent = try #require(icsVevent(ics, uid: root.eventID))
    let firstComponent = try #require(icsVevent(ics, uid: firstTail.eventID))
    let secondComponent = try #require(icsVevent(ics, uid: secondTail.eventID))
    #expect(rootComponent.contains("RRULE:FREQ=DAILY;UNTIL=20330102T235959Z"))
    #expect(firstComponent.contains("RRULE:FREQ=DAILY;UNTIL=20330104T235959Z"))
    #expect(secondComponent.contains("RRULE:FREQ=DAILY"))
    #expect(!secondComponent.contains(";UNTIL="))
  }

  @Test
  func exportRebasesCountAcrossNestedCutoversWithoutIntroducingUntil() async throws {
    let core = try await makeSeededInMemoryCore()
    let root = try await core.createCalendarEvent(
      title: "Seven-day cadence", startDate: "2034-01-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .daily, count: 7),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    let split = try await core.editScopedCalendarEvent(
      eventID: root.eventID, occurrenceDate: "2034-01-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Remaining cadence"))
    let firstTail = try #require(split.replacementEvent)
    let nestedSplit = try await core.editScopedCalendarEvent(
      eventID: firstTail.eventID, occurrenceDate: "2034-01-05", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Final cadence"))
    let finalTail = try #require(nestedSplit.replacementEvent)

    let storedRoot = try #require(try await core.getCalendarEvent(id: root.eventID))
    let storedFirst = try #require(try await core.getCalendarEvent(id: firstTail.eventID))
    let storedFinal = try #require(try await core.getCalendarEvent(id: finalTail.eventID))
    #expect(storedRoot.recurrenceRule?.contains(#""COUNT":7"#) == true)
    #expect(storedRoot.recurrenceRule?.contains(#""UNTIL""#) == false)
    #expect(storedFirst.recurrenceRule?.contains(#""COUNT":5"#) == true)
    #expect(storedFirst.recurrenceRule?.contains(#""UNTIL""#) == false)
    #expect(storedFinal.recurrenceRule?.contains(#""COUNT":3"#) == true)
    #expect(storedFinal.recurrenceRule?.contains(#""UNTIL""#) == false)

    let ics = try await core.exportCalendarICS(from: "2034-01-01", to: "2034-01-10")
    let rootComponent = try #require(icsVevent(ics, uid: root.eventID))
    let firstComponent = try #require(icsVevent(ics, uid: firstTail.eventID))
    let finalComponent = try #require(icsVevent(ics, uid: finalTail.eventID))
    #expect(rootComponent.contains("RRULE:FREQ=DAILY;COUNT=2"))
    #expect(!rootComponent.contains(";UNTIL="))
    #expect(firstComponent.contains("RRULE:FREQ=DAILY;COUNT=2"))
    #expect(!firstComponent.contains(";UNTIL="))
    #expect(finalComponent.contains("RRULE:FREQ=DAILY;COUNT=3"))
    #expect(!finalComponent.contains(";UNTIL="))
  }

  @Test
  func exportOneOffTailKeepsItsLogicalCutoverWhileOnlyPredecessorGetsUntil() async throws {
    let core = try await makeSeededInMemoryCore()
    let root = try await core.createCalendarEvent(
      title: "Daily cadence", startDate: "2035-01-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil, recurrence: TaskRecurrenceRule(freq: .daily),
      timezone: "UTC", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
    let split = try await core.editScopedCalendarEvent(
      eventID: root.eventID, occurrenceDate: "2035-01-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(
        title: "One-off finish", startDate: "2035-01-06", recurrence: .clear))
    let tail = try #require(split.replacementEvent)
    #expect(tail.recurrenceRule == nil)

    let storedRoot = try #require(try await core.getCalendarEvent(id: root.eventID))
    #expect(storedRoot.recurrenceRule?.contains(#""UNTIL""#) == false)

    let ics = try await core.exportCalendarICS(from: "2035-01-01", to: "2035-01-10")
    let rootComponent = try #require(icsVevent(ics, uid: root.eventID))
    let tailComponent = try #require(icsVevent(ics, uid: tail.eventID))
    #expect(rootComponent.contains("RRULE:FREQ=DAILY;UNTIL=20350102T235959Z"))
    #expect(tailComponent.contains("DTSTART:20350106T090000Z"))
    #expect(!tailComponent.contains("RRULE:"))
  }

  @Test
  func defaultICSWindowsDoNotUseOptionalCalendarFallbacks() throws {
    let root = packageRoot()
    let files = [
      "Sources/LorvexCore/Services/SwiftLorvexCoreService+CalendarExportLinks.swift",
      "Sources/LorvexMCPHost/IcsExportToolHandlers.swift",
    ]

    for file in files {
      let source = try String(contentsOf: root.appending(path: file), encoding: .utf8)
      #expect(
        !source.contains("date(byAdding: .day"),
        "\(file) should use canonical YMD arithmetic for default ICS windows")
      #expect(
        !source.contains("addingTimeInterval(TimeInterval(days)"),
        "\(file) must not use fixed-second arithmetic for civil-day windows")
      #expect(
        !source.contains("?? Date()"),
        "\(file) should not silently collapse default ICS windows to today")
    }
    let coreSource = try String(
      contentsOf: root.appending(
        path: "Sources/LorvexCore/Services/SwiftLorvexCoreService+CalendarExportLinks.swift"),
      encoding: .utf8)
    #expect(coreSource.contains("WorkflowTimezone.todayYmdForConn(db)"))
    #expect(coreSource.contains("ymdUTCAddingDays(logicalToday, days: 30)"))
  }
}

private func packageRoot() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  while url.lastPathComponent != "apps" {
    url.deleteLastPathComponent()
  }
  return url.appending(path: "apple")
}

private func icsVevent(_ ics: String, uid: String) -> String? {
  ics.components(separatedBy: "BEGIN:VEVENT\r\n")
    .first { $0.contains("UID:\(uid)@lorvex") }
}
