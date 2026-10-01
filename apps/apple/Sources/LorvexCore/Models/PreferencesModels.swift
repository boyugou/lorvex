import Foundation

/// Snapshot of the full preferences key/value map.
///
/// Keys are user-facing preference identifiers (e.g. `working_hours`,
/// `default_list_id`, `theme`, `setup_completed`); values are the JSON-encoded
/// payloads serialised back to strings so callers can decode per-key shapes
/// without leaking `Any` across the actor boundary.
public struct PreferencesSnapshot: Equatable, Sendable {
  public var values: [String: String]

  public init(values: [String: String]) {
    self.values = values
  }

  public subscript(key: String) -> String? { values[key] }
}

/// The full-shape overview, read in one transaction: the top open tasks across
/// the workspace, the day's list, and the day's briefing, paired with the day
/// and local change sequence they were read at.
///
/// ``tasks`` and ``todayTasks`` answer different questions and stay separate.
/// ``tasks`` answers "what matters most overall", so it is capped and admits
/// undated and future-dated work; ``todayTasks`` answers "what does today
/// hold", so it is date-bounded and uncapped. A single field serving both would
/// silently narrow whichever consumer did not ask for the change.
public struct OverviewTaskListSnapshot: Equatable, Sendable {
  public var logicalDay: String
  public var localChangeSequence: Int
  /// The most important open tasks across the workspace, capped.
  public var tasks: [LorvexTask]
  /// The day's list in Today's order: started tasks first, then canonical
  /// order. Uncapped.
  public var todayTasks: [LorvexTask]
  /// The assistant's briefing for ``logicalDay``, or nil when there is none.
  public var briefing: String?

  public init(
    logicalDay: String, localChangeSequence: Int, tasks: [LorvexTask],
    todayTasks: [LorvexTask] = [], briefing: String? = nil
  ) {
    self.logicalDay = logicalDay
    self.localChangeSequence = localChangeSequence
    self.tasks = tasks
    self.todayTasks = todayTasks
    self.briefing = briefing
  }
}

/// Compact today-style overview returned by `overview.compact`.
///
/// A bounded subset of the overview intended for session-start context: top
/// priority tasks and headline counters. Designed to fit a small assistant
/// context budget.
public struct OverviewCompactSnapshot: Equatable, Sendable {
  public struct Stats: Equatable, Sendable {
    public var openCount: Int
    public var overdueCount: Int
    public var todayPoolCount: Int
    public var attentionCount: Int
    public var upcomingWeekCount: Int

    public init(
      openCount: Int,
      overdueCount: Int,
      todayPoolCount: Int,
      attentionCount: Int,
      upcomingWeekCount: Int
    ) {
      self.openCount = openCount
      self.overdueCount = overdueCount
      self.todayPoolCount = todayPoolCount
      self.attentionCount = attentionCount
      self.upcomingWeekCount = upcomingWeekCount
    }
  }

  public struct TopTask: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: String
    public var listID: String?
    public var priority: Int?
    public var dueDate: String?

    public init(
      id: String,
      title: String,
      status: String,
      listID: String?,
      priority: Int?,
      dueDate: String?
    ) {
      self.id = id
      self.title = title
      self.status = status
      self.listID = listID
      self.priority = priority
      self.dueDate = dueDate
    }
  }

  public var date: String
  public var stats: Stats
  public var topTasks: [TopTask]
  /// Whether today already has the assistant's briefing, the sign that the day
  /// was planned.
  public var hasBriefing: Bool

  public init(
    date: String,
    stats: Stats,
    topTasks: [TopTask],
    hasBriefing: Bool
  ) {
    self.date = date
    self.stats = stats
    self.topTasks = topTasks
    self.hasBriefing = hasBriefing
  }
}

/// Session-start context returned by `session.context`.
///
/// Lightweight envelope summarising the current moment, device identity, sync
/// backend, configured timezone, and working hours so an assistant client can
/// ground its first turn without separate calls. `date`, `weekday`, and
/// `localTime` all describe the same instant in `timezone`. It carries the
/// device/locale frame only; tasks, the day's schedule and briefing, calendar,
/// changelog, and memory are loaded with their own tools.
public struct SessionContextSnapshot: Equatable, Sendable {
  /// Today as `YYYY-MM-DD`.
  public var date: String
  /// Today's English weekday name, such as `Monday`.
  public var weekday: String
  /// The current wall-clock time as 24-hour `HH:MM`.
  public var localTime: String
  public var deviceID: String?
  public var syncBackend: String
  public var timezone: String
  public var workingHours: String?

  public init(
    date: String,
    weekday: String,
    localTime: String,
    deviceID: String?,
    syncBackend: String,
    timezone: String,
    workingHours: String?
  ) {
    self.date = date
    self.weekday = weekday
    self.localTime = localTime
    self.deviceID = deviceID
    self.syncBackend = syncBackend
    self.timezone = timezone
    self.workingHours = workingHours
  }
}
