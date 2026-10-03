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
    /// The habit's chosen `#RRGGBB` color, nil when it uses its automatic
    /// hue; ``LorvexHabitPalette/baseColor(id:color:)`` resolves either.
    public let color: String?

    enum CodingKeys: String, CodingKey {
      case id, name, icon
      case completedToday = "completed_today"
      case target
      case color
    }

    public init(
      id: String, name: String, icon: String?, completedToday: Int, target: Int, color: String? = nil
    ) {
      self.id = id
      self.name = name
      self.icon = icon
      self.completedToday = completedToday
      self.target = max(1, target)
      self.color = color
    }

    /// True when the habit's today completions meet or exceed its target.
    public var isDoneToday: Bool { completedToday >= target }
  }

  struct Stats: Codable, Equatable, Sendable {
    /// Tasks left on Today, uncapped: the length of the day's whole list, which
    /// a consumer holding a capped ``WidgetSnapshot/tasks`` still counts from.
    public let todayCount: Int
    public let overdueCount: Int
    public let dueTodayCount: Int
    public let attentionCount: Int
    /// Tasks completed today, counted by their completion instant
    /// (`completed_at`) read back in the user's local day — not by due date.
    public let completedTodayCount: Int

    enum CodingKeys: String, CodingKey {
      case todayCount = "today_count"
      case overdueCount = "overdue_count"
      case dueTodayCount = "due_today_count"
      case attentionCount = "attention_count"
      case completedTodayCount = "completed_today_count"
    }

    public init(
      todayCount: Int,
      overdueCount: Int,
      dueTodayCount: Int,
      attentionCount: Int? = nil,
      completedTodayCount: Int = 0
    ) {
      self.todayCount = max(0, todayCount)
      self.overdueCount = overdueCount
      self.dueTodayCount = dueTodayCount
      self.attentionCount = attentionCount ?? overdueCount + dueTodayCount
      self.completedTodayCount = max(0, completedTodayCount)
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      todayCount = try container.decode(Int.self, forKey: .todayCount)
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
      try container.encode(todayCount, forKey: .todayCount)
      try container.encode(overdueCount, forKey: .overdueCount)
      try container.encode(dueTodayCount, forKey: .dueTodayCount)
      try container.encode(attentionCount, forKey: .attentionCount)
      try container.encode(completedTodayCount, forKey: .completedTodayCount)
    }
  }

  /// One task on Today's list as glances draw it.
  struct TodayTask: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let status: String
    public let dueDate: String?
    public let priority: Int?
    public let listID: String?
    public let estimatedMinutes: Int?
    /// The task's saved time today as `HH:mm`, when it has one. A time that
    /// ends at midnight is `24:00`.
    public let scheduledStart: String?
    public let scheduledEnd: String?
    /// `true` when the task waits on an unfinished task, and absent otherwise:
    /// a task that waits on nothing carries no key, and a payload without the
    /// key reads as waiting on nothing (``isBlocked``), so a reader or writer
    /// that does not know the key exchanges the same tasks.
    private let blocked: Bool?

    enum CodingKeys: String, CodingKey {
      case id
      case title
      case status
      case dueDate = "due_date"
      case priority
      case listID = "list_id"
      case estimatedMinutes = "estimated_minutes"
      case scheduledStart = "scheduled_start"
      case scheduledEnd = "scheduled_end"
      case blocked
    }

    public init(
      id: String,
      title: String,
      status: String,
      dueDate: String?,
      priority: Int?,
      listID: String?,
      estimatedMinutes: Int?,
      scheduledStart: String? = nil,
      scheduledEnd: String? = nil,
      isBlocked: Bool = false
    ) {
      self.id = id
      self.title = title
      self.status = status
      self.dueDate = dueDate
      self.priority = priority
      self.listID = listID
      self.estimatedMinutes = estimatedMinutes
      self.scheduledStart = scheduledStart
      self.scheduledEnd = scheduledEnd
      self.blocked = isBlocked ? true : nil
    }

    /// True when the task waits on an unfinished task, so it cannot be
    /// started: glances say "Blocked", and the watch offers no Start.
    public var isBlocked: Bool { blocked == true }

    /// True when the task is actionable (`open` or `in_progress`). Widgets,
    /// complications, and the watch keep a started task visible just like the
    /// app's Today page does.
    public var isActionable: Bool {
      LorvexTask.Status(rawValue: status)?.isActionable == true
    }

    /// True when the task is started (`in_progress`).
    public var isStarted: Bool { status == LorvexTask.Status.inProgress.rawValue }

    public var taskURL: URL {
      LorvexDeepLinkContract.taskURL(id)
    }
  }

  /// Actionable tasks in Today's order. The single definition every widget,
  /// watch, and complication consumer reads, so none of them silently drops a
  /// started task after projection.
  var actionableTasks: [TodayTask] { tasks.filter(\.isActionable) }
}
