import Foundation
import LorvexCore
import LorvexWidgetKitSupport

/// Reads the atomic App Group replica envelope and maps its embedded widget
/// snapshot to watch-ready types.
///
/// Returns a fallback and no tasks when the snapshot is missing, corrupt, or of
/// another version. Call sites surface the unavailable snapshot state rather
/// than opening a local writable database on the watch.
public struct LorvexWatchSnapshotReader {
  private let url: URL
  private let calendar: Calendar

  /// Initialises a reader targeting `url` in the App Group container.
  ///
  public init(
    url: URL,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.url = url
    self.calendar = calendar
  }

  /// Attempts to resolve the App Group container and construct a reader.
  ///
  /// Returns `nil` when `FileManager` cannot resolve the container for
  /// `appGroupID` — typically in simulators or test environments without a
  /// provisioned entitlement.
  public static func appGroupReader(
    appGroupID: String,
    fileManager: FileManager = .default,
    calendar: Calendar = .autoupdatingCurrent
  ) -> LorvexWatchSnapshotReader? {
    guard let containerURL = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupID
    ) else {
      return nil
    }
    let snapshotURL = containerURL
      .appendingPathComponent("Lorvex", isDirectory: true)
      .appendingPathComponent(LorvexWatchReplicaStore.defaultReplicaFileName)
    return LorvexWatchSnapshotReader(url: snapshotURL, calendar: calendar)
  }

  /// Loads the snapshot and maps Today's actionable tasks to watch tasks, in
  /// Today's order as the phone sent them. The lead depends on the clock, so
  /// the store resolves it when a view draws (``LorvexWatchStore/orderedTasks(at:)``).
  ///
  /// - Returns: A tuple of the load result and the mapped actionable tasks.
  public func read(at date: Date = Date()) -> (result: WidgetSnapshotLoadResult, tasks: [LorvexTask]) {
    let result = WidgetSnapshotFreshnessPolicy().validatingCurrentDay(
      LorvexWatchReplicaFile.load(at: url),
      now: date,
      calendar: calendar
    )
    switch result {
    case .snapshot(let snapshot):
      return (result, snapshot.actionableTasks.map(Self.task(from:)))
    case .fallback:
      return (result, [])
    }
  }

  // MARK: - Mapping helpers

  static func task(from task: WidgetSnapshot.TodayTask) -> LorvexTask {
    LorvexTask(
      id: task.id,
      title: task.title,
      notes: "",
      aiNotes: nil,
      priority: priority(from: task.priority),
      status: status(from: task.status),
      dueDate: task.dueDate.flatMap(date(from:)),
      estimatedMinutes: task.estimatedMinutes,
      tags: [],
      dependsOn: [],
      checklistItems: [],
      reminders: [],
      latenessState: nil
    )
  }

  private static func priority(from value: Int?) -> LorvexTask.Priority {
    value.flatMap(LorvexTask.Priority.init(tier:)) ?? .p2
  }

  private static func status(from value: String) -> LorvexTask.Status {
    LorvexTask.Status(rawValue: value) ?? .open
  }

  private static func date(from value: String) -> Date? {
    LorvexDateFormatters.ymdUTC.date(from: value)
  }
}
