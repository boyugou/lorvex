import Foundation
import LorvexCore
import LorvexWidgetKitSupport

extension LorvexWatchStore {
  /// Today's list at `nowMinutes` with its lead first when one leads
  /// (``TodayLead``: a running saved time, else a started task, else the next
  /// saved time). The rest keep Today's order.
  public func orderedTasks(at nowMinutes: Int) -> [LorvexTask] {
    TodayLead.ordered(
      tasks, nowMinutes: nowMinutes, time: { savedTimes[$0.id] },
      isStarted: { $0.status == .inProgress })
  }

  /// The task Today leads with at `date`, or nil when no task leads.
  public func lead(at date: Date) -> LorvexTask? {
    TodayLead.lead(
      in: tasks, nowMinutes: productMinutes(at: date), time: { savedTimes[$0.id] },
      isStarted: { $0.status == .inProgress }
    ).map { tasks[$0.index] }
  }

  /// The task's saved time when it contains `nowMinutes`, else nil.
  public func runningTime(of task: LorvexTask, at nowMinutes: Int) -> Range<Int>? {
    guard let time = savedTimes[task.id], time.contains(nowMinutes) else { return nil }
    return time
  }

  /// Minutes since midnight of the product day at `date`, in the day's
  /// timezone (the watch's own zone when the day names none).
  public func productMinutes(at date: Date) -> Int {
    WidgetTodayGlance.minutes(at: date, timezoneName: timezone)
  }

  func refreshFromSnapshot(url: URL) throws {
    let reader = LorvexWatchSnapshotReader(url: url)
    let refreshDate = now()
    let (result, tasks) = reader.read(at: refreshDate)
    switch result {
    case .snapshot(let snapshot):
      guard let snapshotDay = Self.logicalDay(for: snapshot, at: refreshDate) else {
        throw LorvexCoreError.validation(
          field: "logical_day", message: "The watch snapshot has no valid logical day.")
      }
      logicalDay = snapshotDay
      timezone = snapshot.timezone
      self.tasks = tasks
      moreCount = max(0, snapshot.stats.todayCount - tasks.count)
      savedTimes = snapshot.actionableTasks.reduce(into: [:]) { times, task in
        if times[task.id] == nil, let time = WidgetTodayGlance.time(of: task) {
          times[task.id] = time
        }
      }
      blockedTaskIDs = Set(snapshot.actionableTasks.filter(\.isBlocked).map(\.id))
      habits = snapshot.habits
      completedTodayCount = snapshot.stats.completedTodayCount
      snapshotStatusText = Self.snapshotStatusLabel(snapshot, now: refreshDate)
      staleAgeLabel = WidgetSnapshotFreshnessPolicy().classify(snapshot: snapshot, now: refreshDate)
        .staleAgeLabel()
    case .fallback(let fallback):
      self.tasks = []
      moreCount = 0
      habits = []
      savedTimes = [:]
      blockedTaskIDs = []
      throw LorvexWatchSnapshotError.unavailable(fallback)
    }
  }

  /// Producers materialize `logicalDay`; when a payload omits it, the day is
  /// derived in the payload's declared product timezone, never in the watch
  /// process's timezone.
  nonisolated static func logicalDay(for snapshot: WidgetSnapshot, at date: Date) -> String? {
    if let logicalDay = snapshot.logicalDay { return logicalDay }
    guard let timezoneID = snapshot.timezone, let timezone = TimeZone(identifier: timezoneID)
    else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
      return nil
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  public static func snapshotStatusLabel(_ snapshot: WidgetSnapshot, now: Date = Date()) -> String {
    let freshnessPolicy = WidgetSnapshotFreshnessPolicy()
    guard let ageSeconds = freshnessPolicy.classify(snapshot: snapshot, now: now).ageSeconds else {
      return String(
        localized: "watch.status.synced", defaultValue: "Synced snapshot",
        table: "Localizable", bundle: WatchL10n.bundle)
    }
    return String(
      format: String(
        localized: "watch.status.synced_at", defaultValue: "Synced %@",
        table: "Localizable", bundle: WatchL10n.bundle),
      freshnessPolicy.compactAgeLabel(ageSeconds: ageSeconds))
  }

  nonisolated static func snapshotUnavailableStatusText(_ fallback: WidgetSnapshotFallback) -> String {
    switch fallback.reason {
    case .missingFile, .expiredDay:
      return String(
        localized: "watch.status.open_to_sync", defaultValue: "Open Lorvex to sync",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .unreadableFile:
      return String(
        localized: "watch.status.unreadable", defaultValue: "Snapshot unreadable",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .invalidJSON:
      return String(
        localized: "watch.status.damaged", defaultValue: "Snapshot data damaged",
        table: "Localizable", bundle: WatchL10n.bundle)
    case .unsupportedVersion:
      return String(
        localized: "watch.status.update", defaultValue: "Update Lorvex to sync",
        table: "Localizable", bundle: WatchL10n.bundle)
    }
  }
}
