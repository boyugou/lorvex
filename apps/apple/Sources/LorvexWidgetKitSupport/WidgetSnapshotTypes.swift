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
    /// Today was set aside for the habit: neither done nor missed. A check-in
    /// lifts it, so it is never true together with ``isDoneToday``. A snapshot
    /// written without the value reads as false.
    public let isSkipped: Bool

    enum CodingKeys: String, CodingKey {
      case id, name, icon
      case completedToday = "completed_today"
      case target
      case color
      case isSkipped = "is_skipped"
    }

    public init(
      id: String, name: String, icon: String?, completedToday: Int, target: Int,
      color: String? = nil, isSkipped: Bool = false
    ) {
      self.id = id
      self.name = name
      self.icon = icon
      self.completedToday = completedToday
      self.target = max(1, target)
      self.color = color
      self.isSkipped = isSkipped
    }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(String.self, forKey: .id)
      name = try container.decode(String.self, forKey: .name)
      icon = try container.decodeIfPresent(String.self, forKey: .icon)
      completedToday = try container.decode(Int.self, forKey: .completedToday)
      target = try container.decode(Int.self, forKey: .target)
      color = try container.decodeIfPresent(String.self, forKey: .color)
      isSkipped = try container.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
    }

    /// True when the habit's today completions meet or exceed its target.
    public var isDoneToday: Bool { completedToday >= target }

    /// True while the habit still asks for a check-in today: its count is not
    /// met and the day was not set aside.
    public var isOpenToday: Bool { !isDoneToday && !isSkipped }
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
    /// The task's hand-off to the assistant as its state's raw value
    /// (``LorvexTaskDelegation/State``), absent for a task that is the
    /// person's own. Like `blocked`, a reader that does not know the key reads
    /// the task as the person's own, and a value it does not know reads the
    /// same way (``delegationMarker``).
    private let delegation: String?

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
      case delegation
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
      isBlocked: Bool = false,
      delegation: LorvexTaskDelegationMarker? = nil
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
      self.delegation = delegation.map {
        switch $0 {
        case .withAssistant: LorvexTaskDelegation.State.assistant.rawValue
        case .assistantReplied: LorvexTaskDelegation.State.returned.rawValue
        }
      }
    }

    /// True when the task waits on an unfinished task, so it cannot be
    /// started: glances say "Blocked", and the watch offers no Start.
    public var isBlocked: Bool { blocked == true }

    /// The task's hand-off marker: the assistant holds it, or it handed it
    /// back and the task waits on the person; nil for the person's own task.
    public var delegationMarker: LorvexTaskDelegationMarker? {
      switch delegation.flatMap(LorvexTaskDelegation.State.init(rawValue:)) {
      case .assistant: .withAssistant
      case .returned: .assistantReplied
      case nil: nil
      }
    }

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

  /// One of the day's calendar events as the Today widget draws it, measured
  /// on the snapshot's day (``WidgetSnapshot/logicalDay``): its share of that
  /// day's clock (``CalendarTimelineEvent/clockSpan(on:)``), or none for an
  /// all-day event and a day the event fills.
  struct TodayEvent: Codable, Equatable, Sendable, Identifiable {
    /// The occurrence's id; each occurrence of a repeating event has its own.
    public let id: String
    public let title: String
    /// The event's `#RRGGBB` color, nil when it has none.
    public let color: String?
    /// Minutes since midnight where the event's share of the day starts, nil
    /// for an all-day event and a day the event fills.
    public let startMinutes: Int?
    /// Minutes since midnight where its share ends: 1440 for a share that
    /// runs to midnight, nil when the event has no end time.
    public let endMinutes: Int?
    /// `true` on the last day of an event that began on an earlier day, whose
    /// share starts at midnight, and absent otherwise.
    private let carriedOver: Bool?

    enum CodingKeys: String, CodingKey {
      case id, title, color
      case startMinutes = "start_minutes"
      case endMinutes = "end_minutes"
      case carriedOver = "carried_over"
    }

    public init(
      id: String, title: String, color: String?, startMinutes: Int?, endMinutes: Int?,
      isCarriedOver: Bool = false
    ) {
      self.id = id
      self.title = title
      self.color = color
      self.startMinutes = startMinutes
      self.endMinutes = startMinutes == nil ? nil : endMinutes
      self.carriedOver = isCarriedOver ? true : nil
    }

    /// The event began on an earlier day, so it reads "Until" its end rather
    /// than a start of its own.
    public var isCarriedOver: Bool { carriedOver == true }

    /// The event has no place on the day's clock: it is all-day, or it fills
    /// the day.
    public var isAllDay: Bool { startMinutes == nil }

    /// Whether the clock at `nowMinutes` has cleared the event: its end, or
    /// its start when it has no end, is not after the clock. An all-day event
    /// never ends within its day.
    public func hasEnded(at nowMinutes: Int) -> Bool {
      guard let startMinutes else { return false }
      return (endMinutes ?? startMinutes) <= nowMinutes
    }

    /// Whether the event is under way at `nowMinutes`.
    public func isRunning(at nowMinutes: Int) -> Bool {
      guard let startMinutes, let endMinutes else { return false }
      return startMinutes <= nowMinutes && nowMinutes < endMinutes
    }
  }

  /// Actionable tasks in Today's order. The single definition every widget,
  /// watch, and complication consumer reads, so none of them silently drops a
  /// started task after projection.
  var actionableTasks: [TodayTask] { tasks.filter(\.isActionable) }
}
