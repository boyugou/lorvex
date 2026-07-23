import Foundation
import LorvexDomain
import LorvexStore
import Testing

@testable import LorvexApple

// MARK: - EventKitIngest tier redaction (pure function)

private func sampleFetched() -> [EventKitFetchedEvent] {
  [
    EventKitFetchedEvent(
      key: "ek-1", title: "Dentist", notes: "bring x-rays",
      startDate: "2026-06-01", startTime: "10:00",
      endDate: "2026-06-01", endTime: "10:30",
      allDay: false, location: "123 Main St", timezone: "America/Los_Angeles"),
    EventKitFetchedEvent(
      key: "ek-2", title: "Offsite", notes: nil,
      startDate: "2026-06-10", startTime: nil,
      endDate: "2026-06-11", endTime: nil,
      allDay: true, location: nil, timezone: nil),
  ]
}

@Test
func ingestOffTierMirrorsNothing() {
  let rows = EventKitIngest.providerRows(
    from: sampleFetched(), scope: "device", accessMode: .off)
  #expect(rows.isEmpty)
}

@Test
func ingestBusyOnlyRedactsTitleLocationAndNotes() {
  let rows = EventKitIngest.providerRows(
    from: sampleFetched(), scope: "device", accessMode: .busyOnly)
  #expect(rows.count == 2)
  for row in rows {
    #expect(row.title == "Busy")
    #expect(row.location == nil)
    #expect(row.description == nil)
    #expect(row.providerKind == "eventkit")
    #expect(row.providerScope == "device")
  }
  // Occupancy (times / all-day) is preserved verbatim in busy-only.
  #expect(rows[0].startTime == "10:00")
  #expect(rows[0].endTime == "10:30")
  #expect(rows[0].allDay == false)
  #expect(rows[1].allDay == true)
}

@Test
func ingestFullDetailsPassesThroughVerbatim() {
  let rows = EventKitIngest.providerRows(
    from: sampleFetched(), scope: "device", accessMode: .fullDetails)
  #expect(rows.count == 2)
  #expect(rows[0].title == "Dentist")
  #expect(rows[0].location == "123 Main St")
  #expect(rows[0].description == "bring x-rays")
  #expect(rows[0].sourceTimeKind == "tzid")
  #expect(rows[0].sourceTzid == "America/Los_Angeles")
  #expect(rows[1].title == "Offsite")
  #expect(rows[1].allDay == true)
}

@Test
func ingestPreservesEventKitRecurrenceRule() {
  let fetched = EventKitFetchedEvent(
    key: "ek-recurring",
    title: "Weekly design review",
    notes: nil,
    startDate: "2026-06-01",
    startTime: "10:00",
    endDate: "2026-06-01",
    endTime: "10:30",
    allDay: false,
    location: nil,
    timezone: "America/Los_Angeles",
    recurrence: #"{"FREQ":"WEEKLY","BYDAY":["MO"],"INTERVAL":1}"#)

  let rows = EventKitIngest.providerRows(
    from: [fetched], scope: "device", accessMode: .busyOnly)

  #expect(rows.first?.recurrence == fetched.recurrence)
}

@Test
func ingestUsesProvidedScope() {
  let rows = EventKitIngest.providerRows(
    from: sampleFetched(), scope: "custom-scope", accessMode: .busyOnly)
  #expect(rows.allSatisfy { $0.providerScope == "custom-scope" })
}

// MARK: - Titleless coalescing + attendee serialization

private func attendeeFetched() -> EventKitFetchedEvent {
  EventKitFetchedEvent(
    key: "ek-att", title: "Design sync", notes: nil,
    startDate: "2026-06-04", startTime: "11:00", endDate: "2026-06-04", endTime: "12:00",
    allDay: false, location: nil, timezone: "America/Los_Angeles",
    organizerEmail: "alice@example.com",
    attendees: [
      EventKitFetchedAttendee(email: "alice@example.com", name: "Alice", status: .accepted),
      EventKitFetchedAttendee(email: "bob@example.com", status: .needsAction),
    ])
}

@Test
func ingestFullDetailsCoalescesTitlelessEvent() {
  let titleless = EventKitFetchedEvent(
    key: "ek-untitled", title: nil, notes: nil,
    startDate: "2026-06-03", startTime: "09:00", endDate: "2026-06-03", endTime: "09:30",
    allDay: false, location: nil, timezone: "America/Los_Angeles")
  let full = EventKitIngest.providerRows(
    from: [titleless], scope: "device", accessMode: .fullDetails)
  #expect(full.first?.title == "(untitled)")
  let busy = EventKitIngest.providerRows(
    from: [titleless], scope: "device", accessMode: .busyOnly)
  #expect(busy.first?.title == "Busy")
}

@Test
func ingestFullDetailsSerializesAttendeesAndOrganizer() {
  let rows = EventKitIngest.providerRows(
    from: [attendeeFetched()], scope: "device", accessMode: .fullDetails)
  #expect(rows.first?.organizerEmail == "alice@example.com")
  #expect(
    rows.first?.attendeesJson
      == #"[{"email":"alice@example.com","name":"Alice","status":"accepted"},"#
        + #"{"email":"bob@example.com","status":"needs-action"}]"#)
}

@Test
func ingestBusyOnlyDropsAttendeesAndOrganizer() {
  let rows = EventKitIngest.providerRows(
    from: [attendeeFetched()], scope: "device", accessMode: .busyOnly)
  #expect(rows.first?.attendeesJson == nil)
  #expect(rows.first?.organizerEmail == nil)
}
