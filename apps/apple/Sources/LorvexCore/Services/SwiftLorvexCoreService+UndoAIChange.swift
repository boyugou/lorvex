import GRDB
import LorvexDomain
import LorvexStore
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func undoAIChange(changelogID: String) async throws -> UndoAIChangeResult {
    try withWrite { db, hlc, deviceId in
      let change = try Self.recordedTaskUpdate(db, changelogID: changelogID)
      let taskID = TaskId(trusted: change.taskID)
      guard try TaskRepo.Read.getTask(db, taskId: taskID) != nil else {
        throw Self.undoRefusal("The task that change belongs to no longer exists.")
      }
      let current = try TaskResponse.loadEnrichedTaskJSON(db, taskId: taskID)
      guard case .object(let now) = current else {
        throw LorvexCoreError.malformedCoreData(path: "task", reason: "not an object")
      }

      var input = TaskUpdateInput(id: change.taskID)
      var reverted: [String] = []
      var kept: [String] = []
      for field in Self.undoableFields where field.moved(change.before, change.after) {
        // Only what the change set is put back: a field that holds something else now was
        // edited since, by a person or another assistant, and stays as it is.
        if field.holds(now, matching: change.after) {
          field.restore(from: change.before, into: &input)
          reverted.append(field.name)
        } else {
          kept.append(field.name)
        }
      }

      guard !reverted.isEmpty else {
        return UndoAIChangeResult(
          task: try SwiftLorvexTaskDeserializers.task(current), reverted: [], kept: kept)
      }
      let restored = try self.performTaskUpdate(db, hlc: hlc, deviceId: deviceId, input: input)
      return UndoAIChangeResult(task: restored, reverted: reverted, kept: kept)
    }
  }

  // MARK: - The recorded change

  private struct RecordedTaskUpdate {
    var taskID: String
    var before: [String: JSONValue]
    var after: [String: JSONValue]
  }

  /// The task update `changelogID` recorded, with the task as it was before and after. Anything
  /// else (no such row, another kind of change, no snapshot, a snapshot too large to be kept
  /// whole) is a refusal that says why.
  private static func recordedTaskUpdate(_ db: Database, changelogID: String) throws
    -> RecordedTaskUpdate
  {
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
    guard operation == "update", entityType == EntityName.task, let taskID: String = row["entity_id"]
    else {
      throw undoRefusal("Only an update to a task can be undone.")
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
    return RecordedTaskUpdate(taskID: taskID, before: before, after: after)
  }

  private static func undoRefusal(_ message: String) -> LorvexCoreError {
    LorvexCoreError.validation(field: "changelog_id", message: message)
  }

  // MARK: - The fields an undo can restore

  /// One task field (or a pair that only makes sense together) an undo can restore: its wire
  /// name, the keys it reads in the task JSON, and how a restore writes it.
  private struct UndoableField: Sendable {
    var name: String
    var keys: [String]
    var restore: @Sendable (_ before: [String: JSONValue], _ input: inout TaskUpdateInput) -> Void

    /// Whether the change moved this field.
    func moved(_ before: [String: JSONValue], _ after: [String: JSONValue]) -> Bool {
      keys.contains { Self.normalized(before[$0]) != Self.normalized(after[$0]) }
    }

    /// Whether `current` still holds the value `after` records for this field.
    func holds(_ current: [String: JSONValue], matching after: [String: JSONValue]) -> Bool {
      keys.allSatisfy { Self.normalized(current[$0]) == Self.normalized(after[$0]) }
    }

    func restore(from before: [String: JSONValue], into input: inout TaskUpdateInput) {
      restore(before, &input)
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

  private static let undoableFields: [UndoableField] = [
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
    UndoableField(name: "planned_date", keys: ["planned_date"]) { before, input in
      input.plannedDate = textPatch(before, "planned_date")
    },
    UndoableField(
      name: "planned_time", keys: ["planned_start_time", "planned_end_time"]
    ) { before, input in
      // The two ends are one value: both go back together, or both are cleared.
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
}
