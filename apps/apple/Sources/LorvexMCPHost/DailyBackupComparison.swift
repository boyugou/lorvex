import Foundation
import LorvexCore
import MCP

/// The difference between a daily backup and the current data, per category,
/// in the snake_case shape of the export records.
///
/// For each compared category: `removed` holds the records the backup has and
/// the current data does not, in full, so an assistant can create them again;
/// `added` holds a short summary of the records only the current data has;
/// `changed` holds, for a record in both, the short summary of its current
/// version and two partial records, `backup` and `now`, with only the fields
/// that differ. A list field of records (checklist items, reminders, habit
/// completions) shows only the entries one side has and the other lacks; a
/// list of plain values shows both whole lists. `updated_at`, at any depth,
/// never makes a record or a list entry changed.
enum DailyBackupComparison {
  /// The categories a comparison covers, by their export names. Preferences
  /// are left out: they are settings, not items to bring back.
  static let categories: [String] = [
    "tasks", "lists", "tags", "habits", "calendar_events", "task_calendar_event_links",
    "daily_reviews", "daily_briefings", "memory",
  ]

  /// Response keys of the comparison that hold user-written text beyond the
  /// shared ``SecurityFencing/userContentKeys``: a tag's display name and a
  /// memory entry's key. The comparison has no other field named `key`.
  static let extraUserContentKeys: Set<String> = ["display_name", "key"]

  struct Section {
    var removed: [Value] = []
    var added: [Value] = []
    var changed: [Value] = []
  }

  /// The export records of `payload` by category, as snake_case JSON values.
  /// The task graph, preferences, and series cutovers are not compared.
  static func records(of payload: LorvexDataExportPayload) throws -> [String: [Value]] {
    var trimmed = payload
    trimmed.nativeTaskGraph = nil
    trimmed.preferences = nil
    trimmed.calendarSeriesCutovers = nil
    trimmed.manifest = nil
    trimmed.formatVersion = nil
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .custom { path in
      SnakeCaseKey(stringValue: snakeCase(path.last?.stringValue ?? ""))
    }
    let value = try LiteralValue.decode(encoder.encode(trimmed))
    guard case .object(let object) = value else { return [:] }
    var result: [String: [Value]] = [:]
    for category in categories {
      if case .array(let rows)? = object[category] { result[category] = rows }
    }
    return result
  }

  /// Compares one category's records. `ids`, when given, limits the
  /// comparison to the records with those identities.
  static func compare(
    category: String, backup: [Value], now: [Value], ids: Set<String>?
  ) -> Section {
    let backupByID = index(backup, category: category, ids: ids)
    let nowByID = index(now, category: category, ids: ids)
    var section = Section()
    for id in backupByID.keys.sorted() {
      guard let old = backupByID[id] else { continue }
      guard let new = nowByID[id] else {
        section.removed.append(.object(old))
        continue
      }
      if let change = difference(old, new) {
        var entry = summary(new, category: category)
        entry["backup"] = .object(change.backup)
        entry["now"] = .object(change.now)
        section.changed.append(.object(entry))
      }
    }
    for id in nowByID.keys.sorted() where backupByID[id] == nil {
      if let new = nowByID[id] { section.added.append(.object(summary(new, category: category))) }
    }
    return section
  }

  /// `linkedTaskIDs` as `linked_task_ids`: an underscore before each capital
  /// that follows a lowercase letter or digit, then all lowercase. Foundation's
  /// `.convertToSnakeCase` splits a trailing `IDs` into `i_ds`.
  static func snakeCase(_ key: String) -> String {
    var result = ""
    var previous: Character?
    for character in key {
      if character.isUppercase, let previous, previous.isLowercase || previous.isNumber {
        result.append("_")
      }
      result.append(contentsOf: character.lowercased())
      previous = character
    }
    return result
  }

  private struct SnakeCaseKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  /// `value` without any `updated_at` field at any depth, for comparing.
  private static func ignoringUpdatedAt(_ value: Value) -> Value {
    switch value {
    case .object(let object):
      var result: [String: Value] = [:]
      for (key, field) in object where key != "updated_at" {
        result[key] = ignoringUpdatedAt(field)
      }
      return .object(result)
    case .array(let rows):
      return .array(rows.map(ignoringUpdatedAt))
    default:
      return value
    }
  }

  /// The identity of a record within its category.
  static func identity(_ record: [String: Value], category: String) -> String? {
    switch category {
    case "daily_reviews", "daily_briefings":
      return record["date"]?.stringValue
    case "memory":
      return record["key"]?.stringValue
    case "task_calendar_event_links":
      guard let task = record["task_id"]?.stringValue,
        let event = record["calendar_event_id"]?.stringValue
      else { return nil }
      return "\(task)|\(event)"
    default:
      return record["id"]?.stringValue
    }
  }

  /// The fields that name a record in `added` and `changed` entries.
  static func summaryFields(category: String) -> [String] {
    switch category {
    case "tasks": ["id", "title", "status"]
    case "lists", "habits": ["id", "name"]
    case "tags": ["id", "display_name"]
    case "calendar_events": ["id", "title", "start_date"]
    case "daily_reviews", "daily_briefings": ["date"]
    case "memory": ["key"]
    case "task_calendar_event_links": ["task_id", "calendar_event_id"]
    default: ["id"]
    }
  }

  private static func summary(_ record: [String: Value], category: String) -> [String: Value] {
    var result: [String: Value] = [:]
    for field in summaryFields(category: category) {
      if let value = record[field] { result[field] = value }
    }
    return result
  }

  private static func index(
    _ rows: [Value], category: String, ids: Set<String>?
  ) -> [String: [String: Value]] {
    var result: [String: [String: Value]] = [:]
    for row in rows {
      guard case .object(let record) = row, let id = identity(record, category: category)
      else { continue }
      if let ids {
        let matches =
          category == "task_calendar_event_links"
          ? id.split(separator: "|").contains { ids.contains(String($0)) } : ids.contains(id)
        guard matches else { continue }
      }
      result[id] = record
    }
    return result
  }

  /// The differing fields of two versions of a record, or `nil` when only
  /// `updated_at` differs. A field absent on one side is `null` there.
  private static func difference(
    _ old: [String: Value], _ new: [String: Value]
  ) -> (backup: [String: Value], now: [String: Value])? {
    var backup: [String: Value] = [:]
    var now: [String: Value] = [:]
    for field in Set(old.keys).union(new.keys).sorted() where field != "updated_at" {
      let before = old[field] ?? .null
      let after = new[field] ?? .null
      guard ignoringUpdatedAt(before) != ignoringUpdatedAt(after) else { continue }
      if case .array(let beforeRows) = before, case .array(let afterRows) = after,
        (beforeRows + afterRows).contains(where: { $0.objectValue != nil })
      {
        let beforeKeys = beforeRows.map(ignoringUpdatedAt)
        let afterKeys = afterRows.map(ignoringUpdatedAt)
        backup[field] = .array(
          zip(beforeRows, beforeKeys).filter { !afterKeys.contains($0.1) }.map(\.0))
        now[field] = .array(
          zip(afterRows, afterKeys).filter { !beforeKeys.contains($0.1) }.map(\.0))
      } else {
        backup[field] = before
        now[field] = after
      }
    }
    return backup.isEmpty && now.isEmpty ? nil : (backup, now)
  }
}
