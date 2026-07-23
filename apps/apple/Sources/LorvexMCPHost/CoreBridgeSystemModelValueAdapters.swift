import Foundation
import LorvexCore
import MCP

/// Maps the `LorvexCore` system snapshot model types (preferences, overview,
/// session context) onto the MCP `Value` JSON shapes the system tool handlers
/// return. Field names and shapes mirror the contract expected by existing MCP
/// clients, so external integrations see stable objects while the implementation
/// stays pure Swift.
extension CoreBridgeClient {
  static func preferencesValue(from snapshot: PreferencesSnapshot) -> Value {
    var preferences: [String: Value] = [:]
    for (key, raw) in snapshot.values {
      preferences[key] = SecurityFencing.fencePreferenceValue(key: key, value: jsonStringValue(raw))
    }
    return .object(["preferences": .object(preferences)])
  }

  static func overviewCompactValue(from snapshot: OverviewCompactSnapshot) -> Value {
    .object([
      "date": .string(snapshot.date),
      "stats": .object([
        "open_count": .int(snapshot.stats.openCount),
        "overdue_count": .int(snapshot.stats.overdueCount),
        "today_pool_count": .int(snapshot.stats.todayPoolCount),
        "attention_count": .int(snapshot.stats.attentionCount),
        "upcoming_week_count": .int(snapshot.stats.upcomingWeekCount),
      ]),
      "top_tasks": .array(
        snapshot.topTasks.map { task in
          slimTaskSummaryValue(
            id: task.id, title: task.title, status: task.status,
            listID: task.listID, priority: task.priority, dueDate: task.dueDate,
            plannedDate: nil)
        }),
      "current_focus_task_count": .int(snapshot.currentFocusTaskCount),
    ])
  }

  static func sessionContextValue(from snapshot: SessionContextSnapshot) -> Value {
    .object([
      "date": .string(snapshot.date),
      "device_id": snapshot.deviceID.map(Value.string) ?? .null,
      "sync_backend": .string(snapshot.syncBackend),
      "timezone": .string(snapshot.timezone),
      "working_hours": snapshot.workingHours.map(Value.string) ?? .null,
    ])
  }

  /// Renders a stored preference value (canonical JSON or plain string) as a
  /// `Value`: parse JSON when the string decodes, otherwise keep it as a string.
  static func jsonStringValue(_ raw: String) -> Value {
    guard
      let data = raw.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else {
      return .string(raw)
    }
    return anyValue(from: object)
  }
}
