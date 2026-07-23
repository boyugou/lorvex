import Foundation
import LorvexDomain

/// Exact Apple-native task history captured independently from the portable
/// ``ExportTask`` projection.
///
/// The snapshot owns the complete canonical task aggregate graph plus the two
/// pieces of sync state that carry user meaning across a restore: deletion
/// tombstones and opaque forward-compatible payload fields. It deliberately
/// excludes generated columns, outbox delivery state, CloudKit confirmations,
/// device identity, and sync cursors.
public struct NativeTaskGraphSnapshot: Codable, Sendable, Equatable {
  public static let currentSchemaVersion = "1"

  public var schemaVersion: String
  public var tasks: [NativeTaskSnapshot]
  public var recurrenceExceptions: [NativeTaskRecurrenceExceptionSnapshot]
  public var tagEdges: [NativeTaskTagEdgeSnapshot]
  public var dependencyEdges: [NativeTaskDependencyEdgeSnapshot]
  public var checklistItems: [NativeTaskChecklistItemSnapshot]
  public var reminders: [NativeTaskReminderSnapshot]
  public var tombstones: [NativeTaskTombstoneSnapshot]
  public var payloadShadows: [NativeTaskPayloadShadowSnapshot]

  public init(
    schemaVersion: String = currentSchemaVersion,
    tasks: [NativeTaskSnapshot],
    recurrenceExceptions: [NativeTaskRecurrenceExceptionSnapshot],
    tagEdges: [NativeTaskTagEdgeSnapshot],
    dependencyEdges: [NativeTaskDependencyEdgeSnapshot],
    checklistItems: [NativeTaskChecklistItemSnapshot],
    reminders: [NativeTaskReminderSnapshot],
    tombstones: [NativeTaskTombstoneSnapshot] = [],
    payloadShadows: [NativeTaskPayloadShadowSnapshot] = []
  ) {
    self.schemaVersion = schemaVersion
    self.tasks = tasks
    self.recurrenceExceptions = recurrenceExceptions
    self.tagEdges = tagEdges
    self.dependencyEdges = dependencyEdges
    self.checklistItems = checklistItems
    self.reminders = reminders
    self.tombstones = tombstones
    self.payloadShadows = payloadShadows
  }
}

/// A delete marker whose HLC remains authoritative after an exact restore.
/// CloudKit confirmation is intentionally omitted because it is evidence tied
/// to the exporting account/zone, not portable user state.
public struct NativeTaskTombstoneSnapshot: Codable, Sendable, Equatable {
  public var entityType: EntityKind
  public var entityID: String
  public var version: Hlc
  public var deletedAt: String

  public init(
    entityType: EntityKind, entityID: String, version: Hlc, deletedAt: String
  ) {
    self.entityType = entityType
    self.entityID = entityID
    self.version = version
    self.deletedAt = deletedAt
  }
}

/// Opaque unknown-field payload retained for a task-domain entity. The raw JSON
/// is preserved byte-for-byte; a newer app can later promote fields this build
/// does not understand without a backup/restore cycle erasing them.
public struct NativeTaskPayloadShadowSnapshot: Codable, Sendable, Equatable {
  public var entityType: EntityKind
  public var entityID: String
  public var baseVersion: Hlc
  public var payloadSchemaVersion: UInt32
  public var rawPayloadJSON: String
  public var sourceDeviceID: String
  public var updatedAt: String

  public init(
    entityType: EntityKind, entityID: String, baseVersion: Hlc,
    payloadSchemaVersion: UInt32, rawPayloadJSON: String,
    sourceDeviceID: String, updatedAt: String
  ) {
    self.entityType = entityType
    self.entityID = entityID
    self.baseVersion = baseVersion
    self.payloadSchemaVersion = payloadSchemaVersion
    self.rawPayloadJSON = rawPayloadJSON
    self.sourceDeviceID = sourceDeviceID
    self.updatedAt = updatedAt
  }
}

/// Closed task-domain sync inventory carried by the native graph. Keeping this
/// list beside the archive DTO prevents export, validation, freshness checks,
/// and restore routing from drifting apart.
enum NativeTaskGraphContract {
  static let syncedEntityKinds: [EntityKind] = [
    .task,
    .taskReminder,
    .taskChecklistItem,
    .taskTag,
    .taskDependency,
    .taskCalendarEventLink,
  ]

  static let syncedEntityKindSet = Set(syncedEntityKinds)
  static let syncedEntityTypes = syncedEntityKinds.map(\.asString)
}

/// Every canonical `tasks` column except the generated `priority_effective`.
/// HLC-bearing fields use the typed clock so malformed/non-canonical values fail
/// closed at the codec boundary instead of entering a restore plan as strings.
public struct NativeTaskSnapshot: Codable, Sendable, Equatable {
  public var id: String
  public var title: String
  public var body: String?
  public var rawInput: String?
  public var aiNotes: String?
  public var status: String
  public var listID: String
  public var priority: Int?
  public var dueDate: String?
  public var estimatedMinutes: Int?
  public var recurrence: String?
  public var spawnedFrom: String?
  public var spawnedFromVersion: Hlc?
  public var recurrenceGroupID: String?
  public var recurrenceInstanceKey: String?
  public var canonicalOccurrenceDate: String?
  public var contentVersion: Hlc
  public var scheduleVersion: Hlc
  public var lifecycleVersion: Hlc
  public var archiveVersion: Hlc
  public var recurrenceRolloverState: String
  public var recurrenceSuccessorID: String?
  public var version: Hlc
  public var createdAt: String
  public var updatedAt: String
  public var completedAt: String?
  public var lastDeferredAt: String?
  public var lastDeferReason: String?
  public var plannedDate: String?
  public var availableFrom: String?
  public var deferCount: Int
  public var archivedAt: String?

  public init(
    id: String,
    title: String,
    body: String?,
    rawInput: String?,
    aiNotes: String?,
    status: String,
    listID: String,
    priority: Int?,
    dueDate: String?,
    estimatedMinutes: Int?,
    recurrence: String?,
    spawnedFrom: String?,
    spawnedFromVersion: Hlc?,
    recurrenceGroupID: String?,
    recurrenceInstanceKey: String?,
    canonicalOccurrenceDate: String?,
    contentVersion: Hlc,
    scheduleVersion: Hlc,
    lifecycleVersion: Hlc,
    archiveVersion: Hlc,
    recurrenceRolloverState: String,
    recurrenceSuccessorID: String?,
    version: Hlc,
    createdAt: String,
    updatedAt: String,
    completedAt: String?,
    lastDeferredAt: String?,
    lastDeferReason: String?,
    plannedDate: String?,
    availableFrom: String?,
    deferCount: Int,
    archivedAt: String?
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.rawInput = rawInput
    self.aiNotes = aiNotes
    self.status = status
    self.listID = listID
    self.priority = priority
    self.dueDate = dueDate
    self.estimatedMinutes = estimatedMinutes
    self.recurrence = recurrence
    self.spawnedFrom = spawnedFrom
    self.spawnedFromVersion = spawnedFromVersion
    self.recurrenceGroupID = recurrenceGroupID
    self.recurrenceInstanceKey = recurrenceInstanceKey
    self.canonicalOccurrenceDate = canonicalOccurrenceDate
    self.contentVersion = contentVersion
    self.scheduleVersion = scheduleVersion
    self.lifecycleVersion = lifecycleVersion
    self.archiveVersion = archiveVersion
    self.recurrenceRolloverState = recurrenceRolloverState
    self.recurrenceSuccessorID = recurrenceSuccessorID
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.completedAt = completedAt
    self.lastDeferredAt = lastDeferredAt
    self.lastDeferReason = lastDeferReason
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
    self.deferCount = deferCount
    self.archivedAt = archivedAt
  }
}

public struct NativeTaskRecurrenceExceptionSnapshot: Codable, Sendable, Equatable {
  public var taskID: String
  public var exceptionDate: String

  public init(taskID: String, exceptionDate: String) {
    self.taskID = taskID
    self.exceptionDate = exceptionDate
  }
}

public struct NativeTaskTagEdgeSnapshot: Codable, Sendable, Equatable {
  public var taskID: String
  public var tagID: String
  public var version: Hlc
  public var createdAt: String

  public init(taskID: String, tagID: String, version: Hlc, createdAt: String) {
    self.taskID = taskID
    self.tagID = tagID
    self.version = version
    self.createdAt = createdAt
  }
}

public struct NativeTaskDependencyEdgeSnapshot: Codable, Sendable, Equatable {
  public var taskID: String
  public var dependsOnTaskID: String
  public var version: Hlc
  public var createdAt: String

  public init(taskID: String, dependsOnTaskID: String, version: Hlc, createdAt: String) {
    self.taskID = taskID
    self.dependsOnTaskID = dependsOnTaskID
    self.version = version
    self.createdAt = createdAt
  }
}

public struct NativeTaskChecklistItemSnapshot: Codable, Sendable, Equatable {
  public var id: String
  public var taskID: String
  public var position: Int
  public var text: String
  public var completedAt: String?
  public var version: Hlc
  public var createdAt: String
  public var updatedAt: String

  public init(
    id: String,
    taskID: String,
    position: Int,
    text: String,
    completedAt: String?,
    version: Hlc,
    createdAt: String,
    updatedAt: String
  ) {
    self.id = id
    self.taskID = taskID
    self.position = position
    self.text = text
    self.completedAt = completedAt
    self.version = version
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct NativeTaskReminderSnapshot: Codable, Sendable, Equatable {
  public var id: String
  public var taskID: String
  public var reminderAt: String
  public var dismissedAt: String?
  public var cancelledAt: String?
  public var version: Hlc
  public var createdAt: String
  public var originalLocalTime: String?
  public var originalTimeZone: String?

  public init(
    id: String,
    taskID: String,
    reminderAt: String,
    dismissedAt: String?,
    cancelledAt: String?,
    version: Hlc,
    createdAt: String,
    originalLocalTime: String?,
    originalTimeZone: String?
  ) {
    self.id = id
    self.taskID = taskID
    self.reminderAt = reminderAt
    self.dismissedAt = dismissedAt
    self.cancelledAt = cancelledAt
    self.version = version
    self.createdAt = createdAt
    self.originalLocalTime = originalLocalTime
    self.originalTimeZone = originalTimeZone
  }
}

/// The portable task projection and exact Apple-native graph observed under one
/// SQLite read transaction.
public struct TaskDataExportBundle: Sendable {
  public var tasks: [ExportTask]
  public var nativeGraph: NativeTaskGraphSnapshot

  public init(tasks: [ExportTask], nativeGraph: NativeTaskGraphSnapshot) {
    self.tasks = tasks
    self.nativeGraph = nativeGraph
  }
}
