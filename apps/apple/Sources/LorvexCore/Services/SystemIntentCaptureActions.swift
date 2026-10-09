import Foundation

extension LorvexSystemIntentRunner {
  public static func createList(
    name: String,
    description: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexList {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw LorvexCoreError.validation(field: "name", message: "A list name is required.")
    }
    return try await core.createList(name: trimmedName, description: description.trimmedNilIfEmpty)
  }

  public static func createHabit(
    name: String,
    cue: String?,
    targetCount: Int?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexHabit {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw LorvexCoreError.validation(field: "name", message: "A habit name is required.")
    }
    return try await core.createHabit(
      name: trimmedName,
      cue: cue.trimmedNilIfEmpty,
      targetCount: clampedHabitTargetCount(targetCount ?? 1)
    )
  }

  /// Create a calendar event on `startDate` (the logical today when nil).
  ///
  /// A start time makes the event timed even when `allDay` is true, since an
  /// all-day event would drop the time the person gave. A timed event whose
  /// end time is earlier than its start time ends on the following day.
  public static func createCalendarEvent(
    title: String,
    startDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?,
    core: any LorvexCoreServicing
  ) async throws -> CalendarTimelineEvent {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else {
      throw LorvexCoreError.validation(
        field: "title", message: "A calendar event title is required.")
    }
    let eventDate = try await logicalDay(startDate, core: core)
    let start = startTime.trimmedNilIfEmpty
    let end = endTime.trimmedNilIfEmpty
    let isAllDay = allDay && start == nil
    var endDate: String?
    if !isAllDay, let startMinutes = lorvexMinutesSinceMidnight(start),
      let endMinutes = lorvexMinutesSinceMidnight(end), endMinutes < startMinutes
    {
      endDate = LorvexDateFormatters.ymdUTCAddingDays(eventDate, days: 1)
    }
    return try await core.createCalendarEvent(
      title: trimmedTitle,
      startDate: eventDate,
      endDate: endDate,
      startTime: start,
      endTime: end,
      allDay: isAllDay,
      location: location.trimmedNilIfEmpty,
      notes: notes.trimmedNilIfEmpty
    )
  }
}
