import Foundation
import LorvexCore

public extension WidgetSnapshot {
  /// A lightweight list summary for widget configuration. The widget stores only
  /// id/name/icon so AppIntent configuration can show native list choices
  /// without exposing the full list catalog in glance payloads.
  struct ListSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let icon: String?

    public init(id: String, name: String, icon: String?) {
      self.id = id
      self.name = name
      self.icon = icon
    }
  }

  struct ListStats: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let stats: Stats

    enum CodingKeys: String, CodingKey {
      case id = "list_id"
      case stats
    }

    public init(id: String, stats: Stats) {
      self.id = id
      self.stats = stats
    }
  }

  /// A single habit's today completion status for widget display.
  struct HabitSummary: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let icon: String?
    public let completedToday: Int
    public let target: Int

    enum CodingKeys: String, CodingKey {
      case id, name, icon
      case completedToday = "completed_today"
      case target
    }

    public init(id: String, name: String, icon: String?, completedToday: Int, target: Int) {
      self.id = id
      self.name = name
      self.icon = icon
      self.completedToday = completedToday
      self.target = max(1, target)
    }

    /// True when the habit's today completions meet or exceed its target.
    public var isDoneToday: Bool { completedToday >= target }
  }

  /// A single today-list task for widget display.
  struct TodayTask: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let dueDate: String?
    public let priority: Int?
    public let estimatedMinutes: Int?
    public let listID: String?

    enum CodingKeys: String, CodingKey {
      case id, title, priority
      case dueDate = "due_date"
      case estimatedMinutes = "estimated_minutes"
      case listID = "list_id"
    }

    public init(
      id: String,
      title: String,
      dueDate: String?,
      priority: Int?,
      estimatedMinutes: Int?,
      listID: String? = nil
    ) {
      self.id = id
      self.title = title
      self.dueDate = dueDate
      self.priority = priority
      self.estimatedMinutes = estimatedMinutes
      self.listID = listID
    }

    public var taskURL: URL {
      LorvexDeepLinkContract.taskURL(id)
    }
  }

  struct Stats: Codable, Equatable, Sendable {
    public let focusCount: Int
    public let overdueCount: Int
    public let dueTodayCount: Int
    public let attentionCount: Int
    /// Tasks completed today, counted by their completion instant
    /// (`completed_at`) read back in the user's local day — not by due date.
    public let completedTodayCount: Int

    enum CodingKeys: String, CodingKey {
      case focusCount = "focus_count"
      case overdueCount = "overdue_count"
      case dueTodayCount = "due_today_count"
      case attentionCount = "attention_count"
      case completedTodayCount = "completed_today_count"
    }

    public init(
      focusCount: Int,
      overdueCount: Int,
      dueTodayCount: Int,
      attentionCount: Int? = nil,
      completedTodayCount: Int = 0
    ) {
      self.focusCount = focusCount
      self.overdueCount = overdueCount
      self.dueTodayCount = dueTodayCount
      self.attentionCount = attentionCount ?? overdueCount + dueTodayCount
      self.completedTodayCount = max(0, completedTodayCount)
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      focusCount = try container.decode(Int.self, forKey: .focusCount)
      overdueCount = try container.decode(Int.self, forKey: .overdueCount)
      dueTodayCount = try container.decodeIfPresent(Int.self, forKey: .dueTodayCount) ?? 0
      attentionCount =
        try container.decodeIfPresent(Int.self, forKey: .attentionCount)
        ?? overdueCount + dueTodayCount
      completedTodayCount =
        try container.decodeIfPresent(Int.self, forKey: .completedTodayCount) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(focusCount, forKey: .focusCount)
      try container.encode(overdueCount, forKey: .overdueCount)
      try container.encode(dueTodayCount, forKey: .dueTodayCount)
      try container.encode(attentionCount, forKey: .attentionCount)
      try container.encode(completedTodayCount, forKey: .completedTodayCount)
    }
  }

  struct FocusTask: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: String
    public let dueDate: String?
    public let priority: Int?
    public let listID: String?
    public let estimatedMinutes: Int?

    enum CodingKeys: String, CodingKey {
      case id
      case title
      case status
      case dueDate = "due_date"
      case priority
      case listID = "list_id"
      case estimatedMinutes = "estimated_minutes"
    }

    public init(
      id: String,
      title: String,
      status: String,
      dueDate: String?,
      priority: Int?,
      listID: String?,
      estimatedMinutes: Int?
    ) {
      self.id = id
      self.title = title
      self.status = status
      self.dueDate = dueDate
      self.priority = priority
      self.listID = listID
      self.estimatedMinutes = estimatedMinutes
    }

    /// True when the task is actionable (`open` or `in_progress`). Widgets,
    /// complications, and the watch must keep a started task visible just like
    /// the app's Today and reminder surfaces do.
    public var isActionable: Bool {
      LorvexTask.Status(rawValue: status)?.isActionable == true
    }
  }

  /// Actionable focus tasks in snapshot order. The single definition used by
  /// every widget/watch/complication consumer prevents those downstream
  /// surfaces from silently dropping `in_progress` after projection.
  var actionableFocusTasks: [FocusTask] { focusTasks.filter(\.isActionable) }
}
