import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Canonical sync-payload composition.
///
/// - ``buildAggregatePayload(_:entityType:entityId:)`` — aggregate roots whose
///   canonical sync payload needs dedicated composition
///   (`current_focus.task_ids`, `focus_schedule.blocks`,
///   `daily_review.linked_task_ids`/`linked_list_ids`,
///   `calendar_event.attendees`). Calendar attendees are a JSON-in-TEXT
///   base-table column that this builder parses into a real JSON array.
public enum PayloadBuild {
  /// Entity kinds whose canonical sync payload requires dedicated composition
  /// for an embedded child collection and/or a non-verbatim JSON projection.
  public static let aggregateRootKindsWithDedicatedComposition: [EntityKind] = [
    .currentFocus, .focusSchedule, .dailyReview, .calendarEvent,
  ]

  /// True when `kind` is an aggregate root whose payload needs dedicated
  /// composition.
  public static func kindNeedsDedicatedComposition(_ kind: EntityKind) -> Bool {
    switch kind {
    case .currentFocus, .focusSchedule, .dailyReview, .calendarEvent:
      return true
    default:
      return false
    }
  }

  /// Build the canonical sync payload for an aggregate root.
  ///
  /// - `.some(value)` — `entityType` is a registered aggregate AND its parent
  ///   header row exists for `entityId`: parent header columns + child arrays.
  /// - `nil` — either `entityType` is NOT a registered aggregate (caller falls
  ///   back to the bare-columns reader), or it IS registered but the parent
  ///   row is missing. The two are distinguished by
  ///   ``kindNeedsDedicatedComposition(_:)``.
  ///
  /// `entityId` is the natural key: the date for current_focus / focus_schedule
  /// / daily_review, the event UUID for calendar_event. No top-level `version`
  /// is included — the outbox inserts the canonical envelope version at write
  /// time, so emitting the local `version` here would risk shipping a stale one.
  public static func buildAggregatePayload(
    _ db: Database, entityType: String, entityId: String
  ) throws -> JSONValue? {
    guard let kind = EntityKind.parse(entityType) else { return nil }
    guard kindNeedsDedicatedComposition(kind) else { return nil }
    switch kind {
    case .currentFocus:
      return try buildCurrentFocusPayload(db, date: entityId)
    case .focusSchedule:
      return try buildFocusSchedulePayload(db, date: entityId)
    case .dailyReview:
      return try buildDailyReviewPayload(db, date: entityId)
    case .calendarEvent:
      return try buildCalendarEventPayload(db, eventId: entityId)
    default:
      // Statically unreachable: the gate above narrows to the four arms.
      throw StoreError.invariant(
        "entity_type \(kind.asString) is registered in "
          + "aggregateRootKindsWithDedicatedComposition but has no builder arm in "
          + "buildAggregatePayload — add the dispatch arm before registering a new "
          + "aggregate root")
    }
  }

  private static func buildCurrentFocusPayload(
    _ db: Database, date: String
  ) throws -> JSONValue? {
    guard
      let header = try Row.fetchOne(
        db,
        sql: "SELECT date, briefing, timezone, created_at, updated_at "
          + "FROM current_focus WHERE date = ?",
        arguments: [date])
    else { return nil }

    let resolvedDate: String = header["date"]
    let briefing: String? = header["briefing"]
    let timezone: String? = header["timezone"]
    let createdAt: String = header["created_at"]
    let updatedAt: String = header["updated_at"]

    let taskIds = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: resolvedDate)

    return .object([
      "date": .string(resolvedDate),
      "task_ids": .array(taskIds.map(JSONValue.string)),
      "briefing": briefing.map(JSONValue.string) ?? .null,
      "timezone": timezone.map(JSONValue.string) ?? .null,
      "created_at": .string(createdAt),
      "updated_at": .string(updatedAt),
    ])
  }

  private static func buildFocusSchedulePayload(
    _ db: Database, date: String
  ) throws -> JSONValue? {
    guard
      let header = try Row.fetchOne(
        db,
        sql: "SELECT date, rationale, timezone, created_at, updated_at "
          + "FROM focus_schedule WHERE date = ?",
        arguments: [date])
    else { return nil }

    let resolvedDate: String = header["date"]
    let rationale: String? = header["rationale"]
    let timezone: String? = header["timezone"]
    let createdAt: String = header["created_at"]
    let updatedAt: String = header["updated_at"]

    let blocks = try FocusScheduleSnapshot.serializeBlocksForSync(db, date: resolvedDate)

    return .object([
      "date": .string(resolvedDate),
      "blocks": .array(blocks),
      "rationale": rationale.map(JSONValue.string) ?? .null,
      "timezone": timezone.map(JSONValue.string) ?? .null,
      "created_at": .string(createdAt),
      "updated_at": .string(updatedAt),
    ])
  }

  private static func buildDailyReviewPayload(
    _ db: Database, date: String
  ) throws -> JSONValue? {
    guard
      let header = try Row.fetchOne(
        db,
        sql: "SELECT date, summary, mood, energy_level, wins, blockers, learnings, "
          + "timezone, created_at, updated_at "
          + "FROM daily_reviews WHERE date = ?",
        arguments: [date])
    else { return nil }

    let resolvedDate: String = header["date"]
    let summary: String = header["summary"]
    let mood: Int64? = header["mood"]
    let energyLevel: Int64? = header["energy_level"]
    let wins: String? = header["wins"]
    let blockers: String? = header["blockers"]
    let learnings: String? = header["learnings"]
    let timezone: String? = header["timezone"]
    let createdAt: String = header["created_at"]
    let updatedAt: String = header["updated_at"]

    let taskIds = try String.fetchAll(
      db,
      sql: "SELECT task_id FROM daily_review_task_links WHERE review_date = ? "
        + "ORDER BY task_id ASC",
      arguments: [resolvedDate])
    let listIds = try String.fetchAll(
      db,
      sql: "SELECT list_id FROM daily_review_list_links WHERE review_date = ? "
        + "ORDER BY list_id ASC",
      arguments: [resolvedDate])

    return .object([
      "date": .string(resolvedDate),
      "summary": .string(summary),
      "mood": mood.map(JSONValue.int) ?? .null,
      "energy_level": energyLevel.map(JSONValue.int) ?? .null,
      "wins": wins.map(JSONValue.string) ?? .null,
      "blockers": blockers.map(JSONValue.string) ?? .null,
      "learnings": learnings.map(JSONValue.string) ?? .null,
      "timezone": timezone.map(JSONValue.string) ?? .null,
      "created_at": .string(createdAt),
      "updated_at": .string(updatedAt),
      "linked_task_ids": .array(taskIds.map(JSONValue.string)),
      "linked_list_ids": .array(listIds.map(JSONValue.string)),
    ])
  }

  private static func buildCalendarEventPayload(
    _ db: Database, eventId: String
  ) throws -> JSONValue? {
    // `recurrence_end_date` is intentionally NOT projected (STORED generated
    // column; every peer recomputes it from `recurrence`). `all_day` is read as
    // an integer and rewritten as a JSON bool to match the canonical wire shape.
    guard
      let row = try Row.fetchOne(
        db,
        sql: "SELECT id, title, description, start_date, start_time, end_date, end_time, "
          + "all_day, location, url, color, recurrence, timezone, event_type, person_name, "
          + "created_at, updated_at, series_id, recurrence_instance_date, occurrence_state, "
          + "recurrence_generation, content_version, recurrence_topology_version, attendees, "
          + "series_cutover_id "
          + "FROM calendar_events WHERE id = ?",
        arguments: [eventId])
    else { return nil }

    let id: String = row["id"]
    let title: String = row["title"]
    let description: String? = row["description"]
    let startDate: String = row["start_date"]
    let startTime: String? = row["start_time"]
    let endDate: String? = row["end_date"]
    let endTime: String? = row["end_time"]
    let allDay: Int64 = row["all_day"]
    let location: String? = row["location"]
    let url: String? = row["url"]
    let color: String? = row["color"]
    let recurrence: String? = row["recurrence"]
    let timezone: String? = row["timezone"]
    let eventType: String = row["event_type"]
    let personName: String? = row["person_name"]
    let seriesId: String? = row["series_id"]
    let recurrenceInstanceDate: String? = row["recurrence_instance_date"]
    let occurrenceState: String? = row["occurrence_state"]
    let recurrenceGeneration: String? = row["recurrence_generation"]
    let contentVersion: String? = row["content_version"]
    let recurrenceTopologyVersion: String? = row["recurrence_topology_version"]
    let seriesCutoverId: String? = row["series_cutover_id"]
    let createdAt: String = row["created_at"]
    let updatedAt: String = row["updated_at"]

    // `attendees` is a plain JSON-in-TEXT column stored verbatim (canonicalized);
    // emit the parsed array so the wire shape is a real array, NULL for none.
    let attendeesText: String? = row["attendees"]
    let attendeesValue: JSONValue = attendeesText.flatMap(JSONValue.parse) ?? .null

    func str(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }

    var obj: [String: JSONValue] = [:]
    obj["id"] = .string(id)
    obj["title"] = .string(title)
    obj["description"] = str(description)
    obj["start_date"] = .string(startDate)
    obj["start_time"] = str(startTime)
    obj["end_date"] = str(endDate)
    obj["end_time"] = str(endTime)
    obj["all_day"] = .bool(allDay != 0)
    obj["location"] = str(location)
    obj["url"] = str(url)
    obj["color"] = str(color)
    obj["recurrence"] = str(recurrence)
    obj["timezone"] = str(timezone)
    obj["event_type"] = .string(eventType)
    obj["person_name"] = str(personName)
    obj["series_cutover_id"] = str(seriesCutoverId)
    obj["series_id"] = str(seriesId)
    obj["recurrence_instance_date"] = str(recurrenceInstanceDate)
    obj["occurrence_state"] = str(occurrenceState)
    obj["recurrence_generation"] = str(recurrenceGeneration)
    obj["content_version"] = str(contentVersion)
    obj["recurrence_topology_version"] = str(recurrenceTopologyVersion)
    obj["created_at"] = .string(createdAt)
    obj["updated_at"] = .string(updatedAt)
    obj["attendees"] = attendeesValue
    return .object(obj)
  }
}
