import Foundation
import LorvexCore

extension LorvexTaskIntentRunner {
  public static func updateCalendarEvent(
    id: CalendarTimelineEvent.ID,
    title: String?,
    startDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool?,
    location: String?,
    notes: String?,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> CalendarTimelineEvent {
    try await LorvexSystemIntentRunner.updateCalendarEvent(
      id: id,
      title: title,
      startDate: startDate,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      location: location,
      notes: notes,
      core: core
    )
  }

  public static func deleteCalendarEvent(
    id: CalendarTimelineEvent.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> CalendarTimelineEvent.ID {
    try await LorvexSystemIntentRunner.deleteCalendarEvent(id: id, core: core)
  }
}
