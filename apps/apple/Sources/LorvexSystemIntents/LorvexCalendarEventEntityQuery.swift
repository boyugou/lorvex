import AppIntents
import Foundation
import LorvexCore

struct LorvexCalendarEventEntityQuery: EntityQuery, EntityStringQuery {
  func entities(for identifiers: [LorvexCalendarEventEntity.ID]) async throws
    -> [LorvexCalendarEventEntity]
  {
    try await Self.entities(
      for: identifiers, core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  func suggestedEntities() async throws -> [LorvexCalendarEventEntity] {
    try await Self.suggestedEntities(core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  func entities(matching string: String) async throws -> [LorvexCalendarEventEntity] {
    try await Self.entities(matching: string, core: LorvexCoreRuntimeFactory.makeForAppIntent())
  }

  static func suggestedEntities(core: any LorvexCoreServicing) async throws
    -> [LorvexCalendarEventEntity]
  {
    try await allCalendarEventEntities(core: core)
  }

  static func entities(
    for identifiers: [LorvexCalendarEventEntity.ID],
    core: any LorvexCoreServicing
  ) async throws -> [LorvexCalendarEventEntity] {
    var entities: [LorvexCalendarEventEntity] = []
    var seen = Set<LorvexCalendarEventEntity.ID>()
    entities.reserveCapacity(identifiers.count)
    for identifier in identifiers where seen.insert(identifier).inserted {
      guard let event = try await core.getCalendarEvent(id: identifier), event.editable else {
        continue
      }
      entities.append(LorvexCalendarEventEntity(event: event))
    }
    return entities
  }

  static func entities(
    matching string: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexCalendarEventEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let entities = try await allCalendarEventEntities(core: core)
    guard !query.isEmpty else { return entities }
    return entities.filter { entity in
      entity.title.localizedCaseInsensitiveContains(query)
        || entity.id.localizedCaseInsensitiveContains(query)
        || entity.scheduleSummary.localizedCaseInsensitiveContains(query)
    }
  }

  private static func allCalendarEventEntities(core: any LorvexCoreServicing) async throws
    -> [LorvexCalendarEventEntity]
  {
    let logicalDay = try await core.getSessionContext().date
    guard
      let from = LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: -30),
      let to = LorvexDateFormatters.ymdUTCAddingDays(logicalDay, days: 365)
    else {
      throw LorvexCoreError.validation(
        field: "date", message: "The configured logical day is invalid.")
    }
    let events = try await core.loadCalendarTimeline(from: from, to: to).events
      .filter(\.editable)
    let stableIDs = CalendarTimelineEvent.stableSourceRepresentatives(in: events)
      .map(\.eventID)
    // A window can contain only a moved/replaced occurrence. Rehydrate each
    // stable address from the canonical row so the entity's title and schedule
    // describe the same series segment that Update/Delete will mutate.
    return try await entities(for: stableIDs, core: core)
  }

}
