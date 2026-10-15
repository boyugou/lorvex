import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func undoAIChange(changelogID: String) async throws -> UndoAIChangeResult {
    try withWrite { db, hlc, deviceId in
      let change = try Self.recordedUpdate(db, changelogID: changelogID)
      switch change.kind {
      case .task:
        return try self.undoTaskUpdate(db, hlc: hlc, deviceId: deviceId, change: change)
      case .calendarEvent:
        return try self.undoCalendarEventUpdate(db, hlc: hlc, deviceId: deviceId, change: change)
      }
    }
  }

  // MARK: - A task

  private func undoTaskUpdate(
    _ db: Database, hlc: HlcSession, deviceId: String, change: RecordedUpdate
  ) throws -> UndoAIChangeResult {
    let taskID = TaskId(trusted: change.entityID)
    guard try TaskRepo.Read.getTask(db, taskId: taskID) != nil else {
      throw Self.undoRefusal("The task that change belongs to no longer exists.")
    }
    let current = try TaskResponse.loadEnrichedTaskJSON(db, taskId: taskID)
    guard case .object(let now) = current else {
      throw LorvexCoreError.malformedCoreData(path: "task", reason: "not an object")
    }

    var input = TaskUpdateInput(id: change.entityID)
    let (reverted, kept) = Self.putBack(Self.undoableTaskFields, change, now: now, into: &input)
    guard !reverted.isEmpty else {
      return UndoAIChangeResult(
        task: try SwiftLorvexTaskDeserializers.task(current), reverted: [], kept: kept)
    }
    let restored = try self.performTaskUpdate(
      db, hlc: hlc, deviceId: deviceId, input: input,
      summary: { "Took back an earlier change to task '\($0)'" })
    return UndoAIChangeResult(task: restored, reverted: reverted, kept: kept)
  }

  // MARK: - A calendar event

  /// A one-off event only. Undoing a change to a repeating event or to one occurrence of a series
  /// would have to put back the series' bookkeeping with it (its occurrence grid, its decisions),
  /// which is not a field restore, so those stay refused.
  private func undoCalendarEventUpdate(
    _ db: Database, hlc: HlcSession, deviceId: String, change: RecordedUpdate
  ) throws -> UndoAIChangeResult {
    guard let row = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: change.entityID),
      let current = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: change.entityID),
      case .object(let now) = current
    else {
      throw Self.undoRefusal("The calendar event that change belongs to no longer exists.")
    }
    guard [change.before, change.after, now].allSatisfy(Self.isOneOffEvent) else {
      throw Self.undoRefusal(
        "Only an update to a one-off calendar event can be undone; this event repeats or belongs "
          + "to a series.")
    }

    var input = CalendarEventUpdateInput(id: change.entityID)
    let (reverted, kept) = Self.putBack(Self.undoableEventFields, change, now: now, into: &input)
    guard !reverted.isEmpty else {
      return UndoAIChangeResult(
        event: SwiftLorvexCalendarDeserializers.event(row), reverted: [], kept: kept)
    }
    let restored = try self.performCalendarEventUpdate(
      db, hlc: hlc, deviceId: deviceId, input: input, beforeRow: row, before: current,
      summary: { "Took back an earlier change to calendar event '\($0)'" })
    return UndoAIChangeResult(event: restored, reverted: reverted, kept: kept)
  }

  /// Series bookkeeping that makes an event more than a one-off: all of it absent.
  private static let seriesKeys = [
    "recurrence", "series_id", "series_cutover_id", "recurrence_instance_date", "occurrence_state",
  ]

  private static func isOneOffEvent(_ event: [String: JSONValue]) -> Bool {
    seriesKeys.allSatisfy { key in
      switch event[key] {
      case nil, .null?: return true
      default: return false
      }
    }
  }

  // MARK: - The recorded change

  private struct RecordedUpdate {
    enum Kind {
      case task, calendarEvent

      init?(entityType: String) {
        switch entityType {
        case EntityName.task: self = .task
        case EntityName.calendarEvent: self = .calendarEvent
        default: return nil
        }
      }
    }
    var kind: Kind
    var entityID: String
    var before: [String: JSONValue]
    var after: [String: JSONValue]
  }

  /// The update `changelogID` recorded, with the item as it was before and after. Anything else
  /// (no such row, another kind of change, no snapshot, a snapshot too large to be kept whole) is
  /// a refusal that says why.
  private static func recordedUpdate(_ db: Database, changelogID: String) throws -> RecordedUpdate {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT operation, entity_type, entity_id, initiated_by, before_json, after_json
          FROM ai_changelog WHERE id = ?
          """,
        arguments: [changelogID])
    else {
      throw undoRefusal("No change with that id was found. List changes with get_ai_changelog.")
    }
    let operation: String = row["operation"]
    let entityType: String = row["entity_type"]
    guard operation == "update", let kind = RecordedUpdate.Kind(entityType: entityType),
      let entityID: String = row["entity_id"]
    else {
      throw undoRefusal("Only an update to a task or a calendar event can be undone.")
    }
    // What a person did stays theirs: an assistant never undoes it.
    let initiator: String? = row["initiated_by"]
    guard initiator == ChangelogInitiator.assistant else {
      throw undoRefusal(
        "That change was not made by an assistant, so it cannot be undone this way.")
    }
    guard
      let beforeText: String = row["before_json"], let afterText: String = row["after_json"],
      case .object(let before)? = JSONValue.parse(beforeText),
      case .object(let after)? = JSONValue.parse(afterText)
    else {
      throw undoRefusal("That change recorded no before-and-after, so it cannot be undone.")
    }
    guard before["_lorvex_truncated"] == nil, after["_lorvex_truncated"] == nil else {
      throw undoRefusal("That change was too large to be recorded whole, so it cannot be undone.")
    }
    return RecordedUpdate(kind: kind, entityID: entityID, before: before, after: after)
  }

  private static func undoRefusal(_ message: String) -> LorvexCoreError {
    LorvexCoreError.validation(field: "changelog_id", message: message)
  }

  // MARK: - The fields an undo can restore

  /// One field (or a group that only makes sense together) an undo can restore: its wire name, the
  /// keys it reads in the recorded JSON, and how a restore writes it into the update's input.
  private struct UndoableField<Input>: Sendable {
    var name: String
    var keys: [String]
    var restore: @Sendable (_ before: [String: JSONValue], _ input: inout Input) -> Void

    /// Whether the change moved this field.
    func moved(_ before: [String: JSONValue], _ after: [String: JSONValue]) -> Bool {
      keys.contains { Self.normalized(before[$0]) != Self.normalized(after[$0]) }
    }

    /// Whether `current` still holds the value `after` records for this field.
    func holds(_ current: [String: JSONValue], matching after: [String: JSONValue]) -> Bool {
      keys.allSatisfy { Self.normalized(current[$0]) == Self.normalized(after[$0]) }
    }

    /// A missing key reads as null, and a list of names compares without regard to order.
    private static func normalized(_ value: JSONValue?) -> JSONValue {
      switch value ?? .null {
      case .array(let items):
        let names = items.compactMap { item -> String? in
          if case .string(let text) = item { return text }
          return nil
        }
        return names.count == items.count ? .array(names.sorted().map(JSONValue.string)) : .array(items)
      case let other:
        return other
      }
    }
  }

  /// Writes the earlier value of every field the change moved and `now` still holds as the change
  /// set it into `input`. A field edited since is not touched; both lists carry wire names.
  private static func putBack<Input>(
    _ fields: [UndoableField<Input>], _ change: RecordedUpdate, now: [String: JSONValue],
    into input: inout Input
  ) -> (reverted: [String], kept: [String]) {
    var reverted: [String] = []
    var kept: [String] = []
    for field in fields where field.moved(change.before, change.after) {
      // Only what the change set is put back: a field that holds something else now was
      // edited since, by a person or another assistant, and stays as it is.
      if field.holds(now, matching: change.after) {
        field.restore(change.before, &input)
        reverted.append(field.name)
      } else {
        kept.append(field.name)
      }
    }
    return (reverted, kept)
  }

  private static func text(_ value: JSONValue?) -> String? {
    if case .string(let text)? = value { return text }
    return nil
  }

  private static func integer(_ value: JSONValue?) -> Int64? {
    switch value {
    case .int(let number)?: return number
    case .uint(let number)?: return Int64(exactly: number)
    default: return nil
    }
  }

  private static func names(_ value: JSONValue?) -> [String]? {
    guard case .array(let items)? = value else { return nil }
    let names = items.compactMap(text)
    return names.count == items.count ? names : nil
  }

  private static func textPatch(_ before: [String: JSONValue], _ key: String) -> Patch<String> {
    if let value = text(before[key]) { return .set(value) }
    return .clear
  }

  private static let undoableTaskFields: [UndoableField<TaskUpdateInput>] = [
    UndoableField(name: "title", keys: ["title"]) { before, input in
      if let title = text(before["title"]) { input.title = .set(title) }
    },
    UndoableField(name: "notes", keys: ["body"]) { before, input in
      input.body = .set(text(before["body"]) ?? "")
    },
    UndoableField(name: "priority", keys: ["priority"]) { before, input in
      if let tier = integer(before["priority"]), let value = UInt8(exactly: tier) {
        input.priority = .set(value)
      } else {
        input.priority = .clear
      }
    },
    UndoableField(name: "estimated_minutes", keys: ["estimated_minutes"]) { before, input in
      if let minutes = integer(before["estimated_minutes"]), let value = UInt32(exactly: minutes) {
        input.estimatedMinutes = .set(value)
      } else {
        input.estimatedMinutes = .clear
      }
    },
    UndoableField(name: "due_date", keys: ["due_date"]) { before, input in
      input.dueDate = textPatch(before, "due_date")
    },
    UndoableField(
      name: "planned_date", keys: ["planned_date", "planned_start_time", "planned_end_time"]
    ) { before, input in
      // The day and its times are one value: a time belongs to its day, and moving the day
      // clears the time, so all three go back together, or none does.
      input.plannedDate = textPatch(before, "planned_date")
      input.plannedStartTime = textPatch(before, "planned_start_time")
      input.plannedEndTime = textPatch(before, "planned_end_time")
    },
    UndoableField(name: "available_from", keys: ["available_from"]) { before, input in
      input.availableFrom = textPatch(before, "available_from")
    },
    UndoableField(name: "tags", keys: ["tags"]) { before, input in
      input.tagsSet = names(before["tags"]) ?? []
    },
    UndoableField(name: "depends_on", keys: ["depends_on"]) { before, input in
      input.dependsOn = names(before["depends_on"]) ?? []
    },
  ]

  private static let undoableEventFields: [UndoableField<CalendarEventUpdateInput>] = [
    UndoableField(name: "title", keys: ["title"]) { before, input in
      if let title = text(before["title"]) { input.title = title }
    },
    UndoableField(name: "description", keys: ["description"]) { before, input in
      input.description = textPatch(before, "description")
    },
    UndoableField(
      name: "schedule",
      keys: ["start_date", "start_time", "end_date", "end_time", "all_day", "timezone"]
    ) { before, input in
      // Dates, times, the all-day flag, and the time zone are one value: a time is only valid
      // for the day, the flag, and the zone it was set with, so they all go back together.
      if let startDate = text(before["start_date"]) { input.startDate = .set(startDate) }
      input.startTime = textPatch(before, "start_time")
      input.endDate = textPatch(before, "end_date")
      input.endTime = textPatch(before, "end_time")
      if case .bool(let allDay)? = before["all_day"] { input.allDay = allDay }
      input.timezone = textPatch(before, "timezone")
    },
    UndoableField(name: "location", keys: ["location"]) { before, input in
      input.location = textPatch(before, "location")
    },
    UndoableField(name: "url", keys: ["url"]) { before, input in
      input.url = textPatch(before, "url")
    },
    UndoableField(name: "color", keys: ["color"]) { before, input in
      input.color = textPatch(before, "color")
    },
    UndoableField(name: "event_type", keys: ["event_type"]) { before, input in
      if let type = text(before["event_type"]).flatMap(CanonicalCalendarEventType.parse) {
        input.eventType = .set(type)
      }
    },
    UndoableField(name: "person_name", keys: ["person_name"]) { before, input in
      input.personName = textPatch(before, "person_name")
    },
    UndoableField(name: "attendees", keys: ["attendees"]) { before, input in
      guard case .array(let items)? = before["attendees"] else {
        input.attendees = .clear
        return
      }
      input.attendees = .set(
        items.compactMap { item in
          guard case .object(let person) = item else { return nil }
          return CalendarAttendeeInput(
            email: text(person["email"]) ?? "", name: text(person["name"]))
        })
    },
  ]
}
