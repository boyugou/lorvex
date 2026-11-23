import Foundation
import LorvexCore
import MCP

extension ToolRegistry {
  func listDailyBackupsResult() async throws -> CallTool.Result {
    guard let service = coreBridge.service as? any LorvexDailyBackupServicing else {
      return Self.noDailyBackupsResult(toolName: "list_daily_backups")
    }
    let enabled = try await service.dailyBackupsEnabled()
    let backups = try service.dailyBackups()
    let text: String
    if let newest = backups.first {
      text = "\(backups.count) daily backups; the newest is from \(newest.day)."
    } else {
      text = enabled ? "No daily backups yet." : "Daily backups are turned off on this Mac."
    }
    return fencedReadResult(
      text: text,
      value: .object([
        "enabled": .bool(enabled),
        "kept_days": .int(LorvexDailyBackups.keptDays),
        "kept_weeks": .int(LorvexDailyBackups.keptWeeks),
        "backups": .array(backups.map(Self.backupRow)),
      ]))
  }

  func compareWithDailyBackupResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let toolName = "compare_with_daily_backup"
    guard let service = coreBridge.service as? any LorvexDailyBackupServicing else {
      return Self.noDailyBackupsResult(toolName: toolName)
    }
    let day = try StrictScalarArguments.optionalString(arguments["day"], field: "day") ?? ""
    guard let date = LorvexDateFormatters.ymdUTC.date(from: day),
      LorvexDateFormatters.ymdUTC.string(from: date) == day
    else {
      return Self.errorResult(
        code: "validation", message: "day is required, as YYYY-MM-DD.", toolName: toolName)
    }
    let categories =
      try StrictArgumentArray.optionalStrings(arguments["entities"], field: "entities")
      ?? DailyBackupComparison.categories
    guard !categories.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "entities must name at least one category, or be left out.",
        toolName: toolName)
    }
    if let unknown = categories.first(where: { !DailyBackupComparison.categories.contains($0) }) {
      return Self.errorResult(
        code: "validation",
        message:
          "Unknown category '\(unknown)'. Use any of: "
          + DailyBackupComparison.categories.joined(separator: ", ") + ".",
        toolName: toolName)
    }
    let ids = try StrictArgumentArray.optionalStrings(arguments["ids"], field: "ids").map(Set.init)
    let limit =
      try StrictScalarArguments.optionalInt(arguments["limit"], field: "limit")
      ?? DailyBackupToolLimits.defaultLimit
    guard (1...DailyBackupToolLimits.maximum).contains(limit) else {
      return Self.errorResult(
        code: "validation",
        message: "limit must be between 1 and \(DailyBackupToolLimits.maximum).",
        toolName: toolName)
    }

    let backupPayload = try service.dailyBackupPayload(day: day)
    let takenAt = try service.dailyBackups().first(where: { $0.day == day })?.takenAt
    let current = try await coreBridge.service.loadSnapshotForDataExport(
      entities: categories, includeNativeTaskGraph: false)
    let backupRecords = try DailyBackupComparison.records(of: backupPayload)
    let currentRecords = try DailyBackupComparison.records(of: current.payload)

    var byCategory: [String: Value] = [:]
    var changedCategories: [String] = []
    var truncated = false
    for category in DailyBackupComparison.categories where categories.contains(category) {
      let section = DailyBackupComparison.compare(
        category: category, backup: backupRecords[category] ?? [],
        now: currentRecords[category] ?? [], ids: ids)
      let counts = (section.removed.count, section.added.count, section.changed.count)
      if counts.0 + counts.1 + counts.2 > 0 {
        changedCategories.append(
          "\(category): \(counts.0) removed, \(counts.1) added, \(counts.2) changed")
      }
      truncated =
        truncated || max(counts.0, counts.1, counts.2) > limit
      byCategory[category] = .object([
        "removed": .array(Array(section.removed.prefix(limit))),
        "added": .array(Array(section.added.prefix(limit))),
        "changed": .array(Array(section.changed.prefix(limit))),
        "removed_count": .int(counts.0),
        "added_count": .int(counts.1),
        "changed_count": .int(counts.2),
      ])
    }

    var structured: [String: Value] = [
      "day": .string(day),
      "categories": .object(byCategory),
      "truncated": .bool(truncated),
    ]
    if let takenAt {
      structured["backup_taken_at"] = .string(LorvexDateFormatters.iso8601.string(from: takenAt))
    }
    let text =
      changedCategories.isEmpty
      ? "No differences from the backup from \(day) in the compared categories."
      : "Compared with the backup from \(day): " + changedCategories.joined(separator: "; ") + "."
    return fencedReadResult(text: text, value: .object(structured))
  }

  private static func backupRow(_ backup: LorvexDailyBackup) -> Value {
    var row: [String: Value] = ["day": .string(backup.day), "byte_count": .int(backup.byteCount)]
    if let takenAt = backup.takenAt {
      row["taken_at"] = .string(LorvexDateFormatters.iso8601.string(from: takenAt))
    }
    return .object(row)
  }

  private static func noDailyBackupsResult(toolName: String) -> CallTool.Result {
    errorResult(
      code: "validation", message: "This Lorvex store keeps no daily backups.",
      toolName: toolName)
  }
}
