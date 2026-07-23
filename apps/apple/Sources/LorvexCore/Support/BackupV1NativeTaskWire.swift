import Foundation
import LorvexDomain

struct BackupV1NativeTaskTombstone: Codable, Sendable, Equatable {
  var entityType: String
  var entityID: String
  var version: String
  var deletedAt: String

  init(current: NativeTaskTombstoneSnapshot) {
    entityType = current.entityType.rawValue
    entityID = current.entityID
    version = current.version.description
    deletedAt = current.deletedAt
  }

  func current() throws -> NativeTaskTombstoneSnapshot {
    guard let kind = BackupV1NativeTaskGraphSemantics.entityKind(entityType) else {
      throw BackupV1WireError.invalidEntityKind(entityType)
    }
    return NativeTaskTombstoneSnapshot(
      entityType: kind, entityID: entityID,
      version: try BackupV1WireValidation.hlc(version, field: "nativeTaskGraph.tombstones.version"),
      deletedAt: deletedAt)
  }
}

struct BackupV1NativeTaskPayloadShadow: Codable, Sendable, Equatable {
  var entityType: String
  var entityID: String
  var baseVersion: String
  var payloadSchemaVersion: UInt32
  var rawPayloadJSON: String
  var sourceDeviceID: String
  var updatedAt: String

  init(current: NativeTaskPayloadShadowSnapshot) {
    entityType = current.entityType.rawValue
    entityID = current.entityID
    baseVersion = current.baseVersion.description
    payloadSchemaVersion = current.payloadSchemaVersion
    rawPayloadJSON = current.rawPayloadJSON
    sourceDeviceID = current.sourceDeviceID
    updatedAt = current.updatedAt
  }

  func current() throws -> NativeTaskPayloadShadowSnapshot {
    guard let kind = BackupV1NativeTaskGraphSemantics.entityKind(entityType) else {
      throw BackupV1WireError.invalidEntityKind(entityType)
    }
    return NativeTaskPayloadShadowSnapshot(
      entityType: kind, entityID: entityID,
      baseVersion: try BackupV1WireValidation.hlc(
        baseVersion, field: "nativeTaskGraph.payloadShadows.baseVersion"),
      payloadSchemaVersion: payloadSchemaVersion, rawPayloadJSON: rawPayloadJSON,
      sourceDeviceID: sourceDeviceID, updatedAt: updatedAt)
  }
}

struct BackupV1NativeTask: Codable, Sendable, Equatable {
  var id: String
  var title: String
  var body: String?
  var rawInput: String?
  var aiNotes: String?
  var status: String
  var listID: String
  var priority: Int?
  var dueDate: String?
  var estimatedMinutes: Int?
  var recurrence: String?
  var spawnedFrom: String?
  var spawnedFromVersion: String?
  var recurrenceGroupID: String?
  var recurrenceInstanceKey: String?
  var canonicalOccurrenceDate: String?
  var contentVersion: String
  var scheduleVersion: String
  var lifecycleVersion: String
  var archiveVersion: String
  var recurrenceRolloverState: String
  var recurrenceSuccessorID: String?
  var version: String
  var createdAt: String
  var updatedAt: String
  var completedAt: String?
  var lastDeferredAt: String?
  var lastDeferReason: String?
  var plannedDate: String?
  var availableFrom: String?
  var deferCount: Int
  var archivedAt: String?

  init(current: NativeTaskSnapshot) {
    id = current.id
    title = current.title
    body = current.body
    rawInput = current.rawInput
    aiNotes = current.aiNotes
    status = current.status
    listID = current.listID
    priority = current.priority
    dueDate = current.dueDate
    estimatedMinutes = current.estimatedMinutes
    recurrence = current.recurrence
    spawnedFrom = current.spawnedFrom
    spawnedFromVersion = current.spawnedFromVersion?.description
    recurrenceGroupID = current.recurrenceGroupID
    recurrenceInstanceKey = current.recurrenceInstanceKey
    canonicalOccurrenceDate = current.canonicalOccurrenceDate
    contentVersion = current.contentVersion.description
    scheduleVersion = current.scheduleVersion.description
    lifecycleVersion = current.lifecycleVersion.description
    archiveVersion = current.archiveVersion.description
    recurrenceRolloverState = current.recurrenceRolloverState
    recurrenceSuccessorID = current.recurrenceSuccessorID
    version = current.version.description
    createdAt = current.createdAt
    updatedAt = current.updatedAt
    completedAt = current.completedAt
    lastDeferredAt = current.lastDeferredAt
    lastDeferReason = current.lastDeferReason
    plannedDate = current.plannedDate
    availableFrom = current.availableFrom
    deferCount = current.deferCount
    archivedAt = current.archivedAt
  }

  func current() throws -> NativeTaskSnapshot {
    let parsedSpawnedVersion: Hlc?
    if let spawnedFromVersion {
      parsedSpawnedVersion = try BackupV1WireValidation.hlc(
        spawnedFromVersion, field: "nativeTaskGraph.tasks.spawnedFromVersion")
    } else {
      parsedSpawnedVersion = nil
    }
    return NativeTaskSnapshot(
      id: id, title: title, body: body, rawInput: rawInput, aiNotes: aiNotes,
      status: status, listID: listID, priority: priority, dueDate: dueDate,
      estimatedMinutes: estimatedMinutes, recurrence: recurrence,
      spawnedFrom: spawnedFrom, spawnedFromVersion: parsedSpawnedVersion,
      recurrenceGroupID: recurrenceGroupID,
      recurrenceInstanceKey: recurrenceInstanceKey,
      canonicalOccurrenceDate: canonicalOccurrenceDate,
      contentVersion: try BackupV1WireValidation.hlc(
        contentVersion, field: "nativeTaskGraph.tasks.contentVersion"),
      scheduleVersion: try BackupV1WireValidation.hlc(
        scheduleVersion, field: "nativeTaskGraph.tasks.scheduleVersion"),
      lifecycleVersion: try BackupV1WireValidation.hlc(
        lifecycleVersion, field: "nativeTaskGraph.tasks.lifecycleVersion"),
      archiveVersion: try BackupV1WireValidation.hlc(
        archiveVersion, field: "nativeTaskGraph.tasks.archiveVersion"),
      recurrenceRolloverState: recurrenceRolloverState,
      recurrenceSuccessorID: recurrenceSuccessorID,
      version: try BackupV1WireValidation.hlc(version, field: "nativeTaskGraph.tasks.version"),
      createdAt: createdAt, updatedAt: updatedAt, completedAt: completedAt,
      lastDeferredAt: lastDeferredAt, lastDeferReason: lastDeferReason,
      plannedDate: plannedDate, availableFrom: availableFrom,
      deferCount: deferCount, archivedAt: archivedAt)
  }
}

struct BackupV1NativeTaskRecurrenceException: Codable, Sendable, Equatable {
  var taskID: String
  var exceptionDate: String

  init(current: NativeTaskRecurrenceExceptionSnapshot) {
    taskID = current.taskID
    exceptionDate = current.exceptionDate
  }

  var current: NativeTaskRecurrenceExceptionSnapshot {
    NativeTaskRecurrenceExceptionSnapshot(taskID: taskID, exceptionDate: exceptionDate)
  }
}

struct BackupV1NativeTaskTagEdge: Codable, Sendable, Equatable {
  var taskID: String
  var tagID: String
  var version: String
  var createdAt: String

  init(current: NativeTaskTagEdgeSnapshot) {
    taskID = current.taskID
    tagID = current.tagID
    version = current.version.description
    createdAt = current.createdAt
  }

  func current() throws -> NativeTaskTagEdgeSnapshot {
    NativeTaskTagEdgeSnapshot(
      taskID: taskID, tagID: tagID,
      version: try BackupV1WireValidation.hlc(
        version, field: "nativeTaskGraph.tagEdges.version"),
      createdAt: createdAt)
  }
}

struct BackupV1NativeTaskDependencyEdge: Codable, Sendable, Equatable {
  var taskID: String
  var dependsOnTaskID: String
  var version: String
  var createdAt: String

  init(current: NativeTaskDependencyEdgeSnapshot) {
    taskID = current.taskID
    dependsOnTaskID = current.dependsOnTaskID
    version = current.version.description
    createdAt = current.createdAt
  }

  func current() throws -> NativeTaskDependencyEdgeSnapshot {
    NativeTaskDependencyEdgeSnapshot(
      taskID: taskID, dependsOnTaskID: dependsOnTaskID,
      version: try BackupV1WireValidation.hlc(
        version, field: "nativeTaskGraph.dependencyEdges.version"),
      createdAt: createdAt)
  }
}

struct BackupV1NativeTaskChecklistItem: Codable, Sendable, Equatable {
  var id: String
  var taskID: String
  var position: Int
  var text: String
  var completedAt: String?
  var version: String
  var createdAt: String
  var updatedAt: String

  init(current: NativeTaskChecklistItemSnapshot) {
    id = current.id
    taskID = current.taskID
    position = current.position
    text = current.text
    completedAt = current.completedAt
    version = current.version.description
    createdAt = current.createdAt
    updatedAt = current.updatedAt
  }

  func current() throws -> NativeTaskChecklistItemSnapshot {
    NativeTaskChecklistItemSnapshot(
      id: id, taskID: taskID, position: position, text: text,
      completedAt: completedAt,
      version: try BackupV1WireValidation.hlc(
        version, field: "nativeTaskGraph.checklistItems.version"),
      createdAt: createdAt, updatedAt: updatedAt)
  }
}

struct BackupV1NativeTaskReminder: Codable, Sendable, Equatable {
  var id: String
  var taskID: String
  var reminderAt: String
  var dismissedAt: String?
  var cancelledAt: String?
  var version: String
  var createdAt: String
  var originalLocalTime: String?
  var originalTimeZone: String?

  init(current: NativeTaskReminderSnapshot) {
    id = current.id
    taskID = current.taskID
    reminderAt = current.reminderAt
    dismissedAt = current.dismissedAt
    cancelledAt = current.cancelledAt
    version = current.version.description
    createdAt = current.createdAt
    originalLocalTime = current.originalLocalTime
    originalTimeZone = current.originalTimeZone
  }

  func current() throws -> NativeTaskReminderSnapshot {
    NativeTaskReminderSnapshot(
      id: id, taskID: taskID, reminderAt: reminderAt,
      dismissedAt: dismissedAt, cancelledAt: cancelledAt,
      version: try BackupV1WireValidation.hlc(
        version, field: "nativeTaskGraph.reminders.version"),
      createdAt: createdAt, originalLocalTime: originalLocalTime,
      originalTimeZone: originalTimeZone)
  }
}

/// Immutable v1 native-task graph. The wire-facing clocks and entity kinds are
/// strings, so later changes to `Hlc`, `EntityKind`, or their Codable
/// conformances cannot silently redefine the public-v1 document.
struct BackupV1NativeTaskGraph: Codable, Sendable, Equatable {
  var schemaVersion: String
  var tasks: [BackupV1NativeTask]
  var recurrenceExceptions: [BackupV1NativeTaskRecurrenceException]
  var tagEdges: [BackupV1NativeTaskTagEdge]
  var dependencyEdges: [BackupV1NativeTaskDependencyEdge]
  var checklistItems: [BackupV1NativeTaskChecklistItem]
  var reminders: [BackupV1NativeTaskReminder]
  var tombstones: [BackupV1NativeTaskTombstone]
  var payloadShadows: [BackupV1NativeTaskPayloadShadow]

  init(current: NativeTaskGraphSnapshot) {
    schemaVersion = current.schemaVersion
    tasks = current.tasks.map(BackupV1NativeTask.init(current:))
    recurrenceExceptions = current.recurrenceExceptions.map(
      BackupV1NativeTaskRecurrenceException.init(current:))
    tagEdges = current.tagEdges.map(BackupV1NativeTaskTagEdge.init(current:))
    dependencyEdges = current.dependencyEdges.map(
      BackupV1NativeTaskDependencyEdge.init(current:))
    checklistItems = current.checklistItems.map(
      BackupV1NativeTaskChecklistItem.init(current:))
    reminders = current.reminders.map(BackupV1NativeTaskReminder.init(current:))
    tombstones = current.tombstones.map(BackupV1NativeTaskTombstone.init(current:))
    payloadShadows = current.payloadShadows.map(
      BackupV1NativeTaskPayloadShadow.init(current:))
  }

  func current() throws -> NativeTaskGraphSnapshot {
    NativeTaskGraphSnapshot(
      schemaVersion: schemaVersion,
      tasks: try tasks.map { try $0.current() },
      recurrenceExceptions: recurrenceExceptions.map(\.current),
      tagEdges: try tagEdges.map { try $0.current() },
      dependencyEdges: try dependencyEdges.map { try $0.current() },
      checklistItems: try checklistItems.map { try $0.current() },
      reminders: try reminders.map { try $0.current() },
      tombstones: try tombstones.map { try $0.current() },
      payloadShadows: try payloadShadows.map { try $0.current() })
  }
}
