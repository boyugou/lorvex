import Foundation

extension LorvexSystemIntentRunner {
  /// Patch a calendar event: each nil argument leaves its field alone.
  ///
  /// A new start time with no all-day choice makes the event timed, so a time
  /// given to an all-day event is kept rather than ignored. The end date
  /// follows the patch as ``patchedEndDate(of:startDate:startTime:endTime:allDay:)``
  /// describes, so a night event and a moved multi-day event keep their shape.
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
    let eventID = try validatedCalendarEventID(id)
    let day = startDate.trimmedNilIfEmpty
    let start = startTime.trimmedNilIfEmpty
    let end = endTime.trimmedNilIfEmpty
    var endDate: String?
    if day != nil || (start != nil && end != nil),
      let event = try await core.getCalendarEvent(id: eventID)
    {
      endDate = patchedEndDate(
        of: event, startDate: day, startTime: start, endTime: end, allDay: allDay)
    }
    return try await core.updateCalendarEvent(
      id: eventID,
      title: title.trimmedNilIfEmpty,
      startDate: day,
      endDate: endDate,
      startTime: start,
      endTime: end,
      allDay: allDay ?? (start == nil ? nil : false),
      location: location.trimmedNilIfEmpty,
      notes: notes.trimmedNilIfEmpty
    )
  }

  /// The end date an update of `event` writes, or nil to keep the stored one.
  ///
  /// Naming both times runs a timed event from its start to the next time the
  /// end time comes round: the same day, or the following day when the end
  /// time is earlier than the start time. Otherwise, moving the start date
  /// carries a multi-day event's length in days along, as the app's event
  /// editors do.
  static func patchedEndDate(
    of event: CalendarTimelineEvent,
    startDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool?
  ) -> String? {
    let day = startDate ?? event.startDate
    if allDay != true, let startMinutes = lorvexMinutesSinceMidnight(startTime),
      let endMinutes = lorvexMinutesSinceMidnight(endTime)
    {
      if endMinutes < startMinutes {
        return LorvexDateFormatters.ymdUTCAddingDays(day, days: 1)
      }
      return event.endDate == nil ? nil : day
    }
    guard startDate != nil, let storedEnd = event.endDate,
      let storedStart = LorvexDateFormatters.ymdUTC.date(from: event.startDate),
      let storedEndDay = LorvexDateFormatters.ymdUTC.date(from: storedEnd)
    else { return nil }
    let lengthInDays = Int((storedEndDay.timeIntervalSince(storedStart) / 86_400).rounded())
    return LorvexDateFormatters.ymdUTCAddingDays(day, days: lengthInDays)
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
