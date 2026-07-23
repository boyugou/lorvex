import Foundation
import LorvexCore
import LorvexWidgetKitSupport

extension LorvexWatchStore {
  func resolvedFocusTasks(
    focus: CurrentFocusPlan?,
    logicalDay: String,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTask] {
    guard let focus, !focus.taskIDs.isEmpty else { return [] }
    // An actionable task deferred to a future day (planned_date > today) drops
    // out of today's watch focus, even though it stays actionable. A started
    // (in_progress) task is actionable and stays eligible. Tasks with no planned
    // date, or one on/before today, remain in focus.
    var focusEligible: [LorvexTask] = []
    for id in focus.taskIDs {
      let task: LorvexTask
      do {
        task = try await core.loadTask(id: id)
      } catch LorvexCoreError.taskNotFound {
        continue
      }
      guard task.status.isActionable else { continue }
      guard let planned = task.plannedDate else {
        focusEligible.append(task)
        continue
      }
      if LorvexDateFormatters.ymdUTC.string(from: planned) <= logicalDay {
        focusEligible.append(task)
      }
    }
    return focus.taskIDs.compactMap { id in focusEligible.first { $0.id == id } }
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
      let taskIDs = tasks.map(\.id)
      logicalDay = snapshotDay
      currentFocus = CurrentFocusPlan(
        date: snapshotDay,
        taskIDs: taskIDs,
        briefing: snapshot.briefing,
        timezone: snapshot.timezone,
        localChangeSequence: 0
      )
      focusTasks = tasks
      primaryTask = tasks.first
      habits = snapshot.habits
      snapshotStatusText = Self.snapshotStatusLabel(snapshot, now: refreshDate)
    case .fallback(let fallback):
      currentFocus = nil
      primaryTask = nil
      focusTasks = []
      habits = []
      throw LorvexWatchSnapshotError.unavailable(fallback)
    }
  }

  /// v3 producers materialize `logicalDay`. The fallback only exists to read a
  /// legacy v3 payload that omitted it; derive in the payload's declared
  /// product timezone, never in the watch process's timezone.
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
