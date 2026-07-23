import Foundation

extension LorvexSystemIntentRunner {
  public static func createList(
    name: String,
    description: String?,
    core: any LorvexCoreServicing
  ) async throws -> LorvexList {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw LorvexCoreError.emptyTitle }
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
      targetCount: max(1, targetCount ?? 1)
    )
  }

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
    return try await core.createCalendarEvent(
      title: trimmedTitle,
      startDate: eventDate,
      endDate: nil,
      startTime: startTime.trimmedNilIfEmpty,
      endTime: endTime.trimmedNilIfEmpty,
      allDay: allDay,
      location: location.trimmedNilIfEmpty,
      notes: notes.trimmedNilIfEmpty
    )
  }
}
