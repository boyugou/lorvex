import Foundation

extension LorvexSystemIntentRunner {
  public static func updateCalendarEvent(
    id: CalendarTimelineEvent.ID,
    title: String?,
    startDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool?,
    location: String?,
    notes: String?,
    core: any LorvexCoreServicing
  ) async throws -> CalendarTimelineEvent {
    try await core.updateCalendarEvent(
      id: validatedCalendarEventID(id),
      title: title.trimmedNilIfEmpty,
      startDate: startDate.trimmedNilIfEmpty,
      endDate: nil,
      startTime: startTime.trimmedNilIfEmpty,
      endTime: endTime.trimmedNilIfEmpty,
      allDay: allDay,
      location: location.trimmedNilIfEmpty,
      notes: notes.trimmedNilIfEmpty
    )
  }

  public static func deleteCalendarEvent(
    id: CalendarTimelineEvent.ID,
    core: any LorvexCoreServicing
  ) async throws -> CalendarTimelineEvent.ID {
    let eventID = try validatedCalendarEventID(id)
    try await core.deleteCalendarEvent(id: eventID)
    return eventID
  }

  public static func validatedCalendarEventID(_ id: CalendarTimelineEvent.ID) throws
    -> CalendarTimelineEvent.ID
  {
    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(
        field: "event_id", message: "A calendar event ID is required.")
    }
    return trimmed
  }
}
