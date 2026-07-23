import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import OSLog

/// Final phone→watch transport for a workspace-fenced replica envelope.
public protocol WatchReplicaPublishing: Sendable {
  @MainActor
  func publish(replicaEnvelope: LorvexWatchReplicaEnvelope) async
}

enum WatchReplicaSnapshotProjectionError: Error, Equatable {
  case essentialFieldsExceedLimit
  case invalidSemanticField(String)
}

/// Converts the shared widget snapshot into the bounded subset the Watch app
/// actually reads. Source order is stable, so a constrained replica always
/// contains the same leading focus tasks and habits for the same source value.
struct WatchReplicaSnapshotProjector: Sendable {
  static let maximumFocusTasks = 6
  static let maximumVisibleHabits = 16
  static let maximumBriefingUTF8Bytes = 4 * 1024

  func encodedSnapshot(from source: WidgetSnapshot) throws -> Data {
    guard source.version == WidgetSnapshot.supportedVersion else {
      throw WatchReplicaSnapshotProjectionError.invalidSemanticField("version")
    }
    try Self.requireCanonicalTimestamp(source.generatedAt, field: "generated_at")
    if let timezone = source.timezone, TimeZone(identifier: timezone) == nil {
      throw WatchReplicaSnapshotProjectionError.invalidSemanticField("timezone")
    }
    if let logicalDay = source.logicalDay {
      try Self.requireCanonicalDate(logicalDay, field: "logical_day")
    }

    let focusTasks = try source.focusTasks.prefix(Self.maximumFocusTasks).map { task in
      try Self.requireCanonicalUUID(task.id, field: "focus_tasks.id")
      guard LorvexTask.Status(rawValue: task.status)?.isActionable == true else {
        throw WatchReplicaSnapshotProjectionError.invalidSemanticField("focus_tasks.status")
      }
      if let dueDate = task.dueDate {
        try Self.requireCanonicalDate(dueDate, field: "focus_tasks.due_date")
      }
      return WidgetSnapshot.FocusTask(
        id: task.id,
        title: Self.bounded(task.title, maximumUTF8Bytes: 1_024),
        status: task.status,
        dueDate: task.dueDate,
        priority: task.priority,
        // The Watch never consumes list identity. Omitting it avoids carrying a
        // second mutation-capable identifier through a contract that does not
        // need it, and is safer than truncating an opaque identity.
        listID: nil,
        estimatedMinutes: task.estimatedMinutes)
    }
    let habits = try source.habits.prefix(Self.maximumVisibleHabits).map { habit in
      try Self.requireCanonicalUUID(habit.id, field: "habits.id")
      return WidgetSnapshot.HabitSummary(
        id: habit.id,
        name: Self.bounded(habit.name, maximumUTF8Bytes: 1_024),
        // An icon is an SF Symbol identifier, not prose. Preserve a bounded
        // identifier exactly; drop an impossible oversized value instead of
        // truncating it into a different symbol name.
        icon: habit.icon.flatMap { $0.utf8.count <= 128 ? $0 : nil },
        completedToday: habit.completedToday,
        target: habit.target)
    }
    var habitCount = habits.count
    var briefing = source.briefing.map {
      Self.bounded($0, maximumUTF8Bytes: Self.maximumBriefingUTF8Bytes)
    }

    while true {
      let projected = WidgetSnapshot(
        version: source.version,
        generatedAt: source.generatedAt,
        storageGeneration: source.storageGeneration,
        focusFilterRevision: source.focusFilterRevision,
        workspaceInstanceID: source.workspaceInstanceID,
        localChangeSequence: source.localChangeSequence,
        timezone: source.timezone,
        logicalDay: source.logicalDay,
        stats: source.stats,
        briefing: briefing,
        focusTasks: Array(focusTasks),
        habits: Array(habits.prefix(habitCount)),
        todayTasks: [],
        lists: [],
        listStats: [])
      let data = try JSONEncoder().encode(projected)
      if data.count <= LorvexWatchReplicaEnvelope.maximumSnapshotBytes {
        return data
      }
      if habitCount > 0 {
        habitCount -= 1
      } else if briefing != nil {
        briefing = nil
      } else {
        throw WatchReplicaSnapshotProjectionError.essentialFieldsExceedLimit
      }
    }
  }

  /// Watch mutations use these ids as database identities. They must survive
  /// byte-for-byte; accepting and shortening a malformed value could fabricate
  /// a different entity on the wrist.
  private static func requireCanonicalUUID(_ value: String, field: String) throws {
    guard LorvexWatchWire.isCanonicalUUID(value) else {
      throw WatchReplicaSnapshotProjectionError.invalidSemanticField(field)
    }
  }

  /// Semantic date fields are routing/freshness inputs, not display strings.
  /// Validate the exact canonical shape and preserve the original bytes.
  private static func requireCanonicalDate(_ value: String, field: String) throws {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: value),
      LorvexDateFormatters.ymdUTC.string(from: date) == value
    else {
      throw WatchReplicaSnapshotProjectionError.invalidSemanticField(field)
    }
  }

  /// The phone projector emits the second-precision UTC ISO-8601 shape. A
  /// merely parseable alternative is not the wire contract: preserve that
  /// canonical value exactly so freshness ordering has one representation.
  private static func requireCanonicalTimestamp(_ value: String, field: String) throws {
    guard let date = LorvexDateFormatters.iso8601.date(from: value),
      LorvexDateFormatters.iso8601.string(from: date) == value
    else {
      throw WatchReplicaSnapshotProjectionError.invalidSemanticField(field)
    }
  }

  /// Truncate on extended-grapheme boundaries and reserve the final three bytes
  /// for an ellipsis, so every bounded value remains valid Unicode.
  private static func bounded(_ value: String, maximumUTF8Bytes: Int) -> String {
    guard value.utf8.count > maximumUTF8Bytes else { return value }
    let suffix = "…"
    let contentBudget = max(0, maximumUTF8Bytes - suffix.utf8.count)
    var result = ""
    var byteCount = 0
    for character in value {
      let fragment = String(character)
      let fragmentBytes = fragment.utf8.count
      guard byteCount + fragmentBytes <= contentBudget else { break }
      result.append(character)
      byteCount += fragmentBytes
    }
    return result + suffix
  }
}

/// Projects the shared widget value into a bounded Watch replica and binds it
/// to the exact database instance that produced it before transport. The same
/// core instance backs the mobile store and resolves the workspace identity, so
/// a replica cannot pair one store's snapshot with another store's fence.
public struct WatchSnapshotReplicaMirror: Sendable {
  private static let log = Logger(
    subsystem: "com.lorvex.mobile", category: "watch-snapshot")

  private let commandService: any LorvexWatchCommandServicing
  private let publisher: any WatchReplicaPublishing

  public init(
    commandService: any LorvexWatchCommandServicing,
    publisher: any WatchReplicaPublishing
  ) {
    self.commandService = commandService
    self.publisher = publisher
  }

  @MainActor
  public func publish(snapshot: WidgetSnapshot) async {
    do {
      let snapshotData = try WatchReplicaSnapshotProjector().encodedSnapshot(from: snapshot)
      let workspaceInstanceID = try await commandService.currentWatchWorkspaceInstanceID()
      guard workspaceInstanceID == snapshot.workspaceInstanceID else {
        throw WatchReplicaSnapshotProjectionError.invalidSemanticField(
          "workspace_instance_id")
      }
      let envelope = try LorvexWatchReplicaEnvelope(
        workspaceInstanceID: workspaceInstanceID,
        snapshotData: snapshotData)
      await publisher.publish(replicaEnvelope: envelope)
    } catch {
      Self.log.error(
        "Watch replica envelope creation failed; replica not sent: \(String(describing: error), privacy: .public)"
      )
    }
  }
}

#if canImport(WatchConnectivity)
  import WidgetKit

  /// Triggers a WidgetKit timeline reload for the watch complication after a
  /// mutation-driven snapshot update.
  public protocol WatchComplicationReloading: Sendable {
    func reloadTimelines()
  }

  /// Reloads the watch complication timeline via `WidgetCenter`.
  public struct WidgetCenterComplicationReloader: WatchComplicationReloading {
    public init() {}

    public func reloadTimelines() {
      // WidgetCenter on visionOS is visionOS 26.0+; other platforms already
      // meet the deployment minimum.
      #if os(visionOS)
        if #available(visionOS 26.0, *) {
          WidgetCenter.shared.reloadTimelines(
            ofKind: LorvexProductMetadata.watchComplicationKind
          )
        }
      #else
        WidgetCenter.shared.reloadTimelines(
          ofKind: LorvexProductMetadata.watchComplicationKind
        )
      #endif
    }
  }
#endif
