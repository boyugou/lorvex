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

/// Compact today-style overview returned by `overview.compact`.
///
/// A bounded subset of `loadToday` intended for session-start context: top
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
  public var currentFocusTaskCount: Int

  public init(
    date: String,
    stats: Stats,
    topTasks: [TopTask],
    currentFocusTaskCount: Int
  ) {
    self.date = date
    self.stats = stats
    self.topTasks = topTasks
    self.currentFocusTaskCount = currentFocusTaskCount
  }
}

/// Session-start context returned by `session.context`.
///
/// Lightweight envelope summarising device identity, sync backend, configured
/// timezone, and working hours so an assistant client can ground its first turn
/// without separate calls. It carries the device/locale frame only; tasks,
/// focus, calendar, changelog, and memory are loaded with their own tools.
public struct SessionContextSnapshot: Equatable, Sendable {
  public var date: String
  public var deviceID: String?
  public var syncBackend: String
  public var timezone: String
  public var workingHours: String?

  public init(
    date: String,
    deviceID: String?,
    syncBackend: String,
    timezone: String,
    workingHours: String?
  ) {
    self.date = date
    self.deviceID = deviceID
    self.syncBackend = syncBackend
    self.timezone = timezone
    self.workingHours = workingHours
  }
}
