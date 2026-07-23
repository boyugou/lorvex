import Foundation
import LorvexDomain
import LorvexStore
import LorvexSync

/// Frozen semantic validator for native task-graph schema version 1. Public-v1
/// restore calls this validator even after the app's current graph advances;
/// later graph versions get new validators instead of changing this language.
enum NativeTaskGraphV1Validator {
  static let schemaVersion = "1"

  // These are part of the released graph-v1 language. Do not derive them from
  // current-app enums or budgets: those are intentionally free to evolve while
  // a public-v1 backup must continue to mean exactly what it meant at release.
  private static let taskStatuses: Set<String> = [
    "open", "in_progress", "completed", "cancelled", "someday",
  ]
  private static let deferReasons: Set<String> = [
    "not_today", "blocked", "low_energy", "needs_breakdown", "needs_info",
  ]
  private static let recurrenceKeys: Set<String> = [
    "FREQ", "INTERVAL", "BYDAY", "BYMONTH", "BYMONTHDAY",
    "BYSETPOS", "WKST", "UNTIL", "COUNT", "ANCHOR",
  ]
  private static let syncedEntityKinds: Set<EntityKind> = [
    .task, .taskReminder, .taskChecklistItem, .taskTag, .taskDependency,
    .taskCalendarEventLink,
  ]
  private static let maxRecurrenceExceptions = 400
  private static let maxPayloadSchemaVersion: UInt32 = 101
  private static let maxRawPayloadJSONBytes = 256 * 1024
  private static let maxSourceDeviceIDBytes = 128

  static func validate(
    _ snapshot: NativeTaskGraphSnapshot,
    knownListIDs: Set<String>? = nil,
    knownTagIDs: Set<String>? = nil
  ) throws -> NativeTaskGraphValidationSummary {
    guard snapshot.schemaVersion == schemaVersion else {
      throw NativeTaskGraphValidationError.incompatibleSchemaVersion(snapshot.schemaVersion)
    }

    let tasksByID = try uniqueTasks(snapshot.tasks)
    let taskIDs = Set(tasksByID.keys)
    let requiredListIDs = Set(snapshot.tasks.map(\.listID))
    let requiredTagIDs = Set(snapshot.tagEdges.map(\.tagID))
    var observedVersions: [Hlc] = []
    observedVersions.reserveCapacity(
      snapshot.tasks.count * 5 + snapshot.tagEdges.count + snapshot.dependencyEdges.count
        + snapshot.checklistItems.count + snapshot.reminders.count)

    for task in snapshot.tasks {
      if let knownListIDs, !knownListIDs.contains(task.listID) {
        throw NativeTaskGraphValidationError.missingEndpoint(
          relation: "task.listID", identity: task.listID)
      }
      try validatePrimitiveTask(task)
      for (name, register) in [
        ("contentVersion", task.contentVersion),
        ("scheduleVersion", task.scheduleVersion),
        ("lifecycleVersion", task.lifecycleVersion),
        ("archiveVersion", task.archiveVersion),
      ] where register > task.version {
        throw NativeTaskGraphValidationError.registerExceedsTaskVersion(
          taskID: task.id, register: name)
      }
      if let spawnedFromVersion = task.spawnedFromVersion,
        spawnedFromVersion > task.version
      {
        throw NativeTaskGraphValidationError.registerExceedsTaskVersion(
          taskID: task.id, register: "spawnedFromVersion")
      }
      observedVersions += [
        task.contentVersion, task.scheduleVersion, task.lifecycleVersion,
        task.archiveVersion, task.version,
      ]
      if let spawnedFromVersion = task.spawnedFromVersion {
        observedVersions.append(spawnedFromVersion)
      }
      try validateInstanceIdentity(task)
    }

    try validateLineage(tasksByID)
    try validateRollover(tasksByID)
    try validateRelations(
      snapshot, tasksByID: tasksByID, taskIDs: taskIDs, knownTagIDs: knownTagIDs,
      observedVersions: &observedVersions)
    try validateSyncArtifacts(snapshot, observedVersions: &observedVersions)

    let maximumHLC = observedVersions.max()
    if let maximumHLC,
      !BackupV1NativeTaskGraphSemantics.hasOperationalSuccessor(after: maximumHLC)
    {
      throw NativeTaskGraphValidationError.terminalHlc(maximumHLC.description)
    }
    return NativeTaskGraphValidationSummary(
      taskIDs: taskIDs,
      requiredListIDs: requiredListIDs,
      requiredTagIDs: requiredTagIDs,
      maximumHLC: maximumHLC)
  }

  private static func validatePrimitiveTask(_ task: NativeTaskSnapshot) throws {
    try requireCanonicalUuid(task.id, field: "task.id")
    try requireCanonicalListID(task.listID, field: "task.listID")
    guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw invalidValue("task.title", "task \(task.id) has an empty title")
    }
    guard taskStatuses.contains(task.status) else {
      throw invalidValue("task.status", "task \(task.id) uses \(task.status)")
    }
    guard task.priority.map({ (1...3).contains($0) }) ?? true else {
      throw invalidValue("task.priority", "task \(task.id) must use 1...3 or null")
    }
    guard task.estimatedMinutes.map({ (1...1440).contains($0) }) ?? true else {
      throw invalidValue(
        "task.estimatedMinutes", "task \(task.id) must use 1...1440 or null")
    }
    guard task.deferCount >= 0 else {
      throw invalidValue("task.deferCount", "task \(task.id) is negative")
    }
    if let reason = task.lastDeferReason, !deferReasons.contains(reason) {
      throw invalidValue("task.lastDeferReason", "task \(task.id) uses \(reason)")
    }
    try requireTimestamp(task.createdAt, field: "task.createdAt")
    try requireTimestamp(task.updatedAt, field: "task.updatedAt")
    try requireOptionalTimestamp(task.completedAt, field: "task.completedAt")
    try requireOptionalTimestamp(task.lastDeferredAt, field: "task.lastDeferredAt")
    try requireOptionalTimestamp(task.archivedAt, field: "task.archivedAt")
    try requireOptionalDate(task.dueDate, field: "task.dueDate")
    try requireOptionalDate(task.plannedDate, field: "task.plannedDate")
    try requireOptionalDate(task.availableFrom, field: "task.availableFrom")
    try requireOptionalDate(
      task.canonicalOccurrenceDate, field: "task.canonicalOccurrenceDate")

    if let recurrence = task.recurrence {
      guard let parsed = JSONValue.parse(recurrence), case .object(let object) = parsed else {
        throw invalidValue(
          "task.recurrence", "task \(task.id) is not a JSON object")
      }
      if let unknownKey = object.keys.sorted().first(where: { !recurrenceKeys.contains($0) }) {
        throw invalidValue(
          "task.recurrence",
          "task \(task.id) uses graph-v1-unknown key \(unknownKey)")
      }
      let normalized: String
      do {
        normalized = try BackupV1RecurrenceSemantics.canonicalize(recurrence)
      } catch {
        throw invalidValue(
          "task.recurrence", "task \(task.id) is not valid: \(error)")
      }
      guard normalized == recurrence else {
        throw invalidValue("task.recurrence", "task \(task.id) is not canonical")
      }
    }
    if let spawnedFrom = task.spawnedFrom {
      try requireCanonicalUuid(spawnedFrom, field: "task.spawnedFrom")
    }
    if let groupID = task.recurrenceGroupID {
      try requireCanonicalUuid(groupID, field: "task.recurrenceGroupID")
    }
    if let key = task.recurrenceInstanceKey {
      try requireNonemptyTrimmed(key, field: "task.recurrenceInstanceKey")
    }
    if let successorID = task.recurrenceSuccessorID {
      try requireCanonicalUuid(successorID, field: "task.recurrenceSuccessorID")
    }
  }

  private static func uniqueTasks(
    _ tasks: [NativeTaskSnapshot]
  ) throws -> [String: NativeTaskSnapshot] {
    var result: [String: NativeTaskSnapshot] = [:]
    result.reserveCapacity(tasks.count)
    var instanceKeys = Set<String>()
    for task in tasks {
      guard result.updateValue(task, forKey: task.id) == nil else {
        throw NativeTaskGraphValidationError.duplicateIdentity(kind: "task", identity: task.id)
      }
      if let key = task.recurrenceInstanceKey, !instanceKeys.insert(key).inserted {
        throw NativeTaskGraphValidationError.duplicateIdentity(
          kind: "recurrence instance", identity: key)
      }
    }
    return result
  }

  private static func validateInstanceIdentity(_ task: NativeTaskSnapshot) throws {
    let isGenerated = task.spawnedFrom != nil
    guard isGenerated || task.recurrenceInstanceKey != nil else { return }
    guard let groupID = task.recurrenceGroupID, !groupID.isEmpty,
      let date = task.canonicalOccurrenceDate,
      let expected = BackupV1NativeTaskGraphSemantics.recurrenceInstanceKey(
        groupID: groupID, date: date),
      task.recurrenceInstanceKey == expected
    else {
      throw NativeTaskGraphValidationError.invalidLineage(
        taskID: task.id,
        reason: "generated occurrence identity does not match its group and canonical date")
    }
  }

  private static func validateLineage(
    _ tasksByID: [String: NativeTaskSnapshot]
  ) throws {
    for task in tasksByID.values {
      guard let parentID = task.spawnedFrom else {
        guard task.spawnedFromVersion == nil else {
          throw NativeTaskGraphValidationError.invalidLineage(
            taskID: task.id, reason: "spawnedFromVersion is present without a parent")
        }
        continue
      }
      guard task.spawnedFromVersion != nil else {
        throw NativeTaskGraphValidationError.invalidLineage(
          taskID: task.id, reason: "spawnedFrom is present without an authorization version")
      }
      guard parentID != task.id, let parent = tasksByID[parentID] else {
        throw NativeTaskGraphValidationError.missingEndpoint(
          relation: "task.spawnedFrom", identity: parentID)
      }
      guard let groupID = task.recurrenceGroupID, groupID == parent.recurrenceGroupID,
        BackupV1NativeTaskGraphSemantics.recurrenceSuccessorID(
          parentTaskID: parentID, groupID: groupID) == task.id
      else {
        throw NativeTaskGraphValidationError.invalidLineage(
          taskID: task.id,
          reason: "successor identity or recurrence group does not match its parent")
      }
      guard parent.recurrenceSuccessorID == task.id,
        parent.recurrenceRolloverState == "authorized"
          || parent.recurrenceRolloverState == "revoked"
      else {
        throw NativeTaskGraphValidationError.invalidLineage(
          taskID: task.id, reason: "parent does not retain this direct-successor decision")
      }
      if parent.recurrenceRolloverState == "revoked" {
        guard task.status == "cancelled",
          let generation = task.spawnedFromVersion,
          generation < parent.lifecycleVersion
        else {
          throw NativeTaskGraphValidationError.invalidLineage(
            taskID: task.id,
            reason: "a revoked successor must be the cancelled prior generation")
        }
      }
    }

    var settled = Set<String>()
    for start in tasksByID.keys.sorted() where !settled.contains(start) {
      var path: [String] = []
      var pathIndex: [String: Int] = [:]
      var cursor: String? = start
      while let current = cursor, !settled.contains(current) {
        if let cycleStart = pathIndex[current] {
          throw NativeTaskGraphValidationError.lineageCycle(
            taskIDs: Array(path[cycleStart...]) + [current])
        }
        pathIndex[current] = path.count
        path.append(current)
        cursor = tasksByID[current]?.spawnedFrom
      }
      settled.formUnion(path)
    }
  }

  private static func validateRollover(
    _ tasksByID: [String: NativeTaskSnapshot]
  ) throws {
    for parent in tasksByID.values {
      guard ["open", "in_progress", "completed", "cancelled", "someday"].contains(parent.status)
      else {
        throw NativeTaskGraphValidationError.invalidRollover(
          taskID: parent.id, reason: "unknown task status \(parent.status)")
      }
      let terminal = parent.status == "completed" || parent.status == "cancelled"
      let active =
        parent.status == "open" || parent.status == "in_progress"
        || parent.status == "someday"
      guard (parent.status == "completed") == (parent.completedAt != nil) else {
        throw NativeTaskGraphValidationError.invalidRollover(
          taskID: parent.id, reason: "completion status and completedAt disagree")
      }
      if parent.recurrence != nil,
        parent.dueDate == nil || parent.recurrenceGroupID == nil
          || parent.canonicalOccurrenceDate == nil
      {
        throw NativeTaskGraphValidationError.invalidRollover(
          taskID: parent.id,
          reason: "recurrence requires due date, group, and canonical occurrence date")
      }
      switch parent.recurrenceRolloverState {
      case "none", "ended":
        guard parent.recurrenceSuccessorID == nil else {
          throw NativeTaskGraphValidationError.invalidRollover(
            taskID: parent.id, reason: "state must not carry a successor")
        }
        if parent.recurrenceRolloverState == "none",
          !(parent.recurrence == nil || active)
        {
          throw NativeTaskGraphValidationError.invalidRollover(
            taskID: parent.id, reason: "none is not valid for this lifecycle product")
        }
        if parent.recurrenceRolloverState == "ended", !terminal {
          throw NativeTaskGraphValidationError.invalidRollover(
            taskID: parent.id, reason: "ended requires a terminal task")
        }
      case "authorized", "revoked":
        guard let groupID = parent.recurrenceGroupID, !groupID.isEmpty,
          let successorID = parent.recurrenceSuccessorID,
          BackupV1NativeTaskGraphSemantics.recurrenceSuccessorID(
            parentTaskID: parent.id, groupID: groupID) == successorID
        else {
          throw NativeTaskGraphValidationError.invalidRollover(
            taskID: parent.id, reason: "recorded successor is not deterministic for its group")
        }
        if parent.recurrenceRolloverState == "authorized",
          !(terminal && parent.recurrence != nil)
        {
          throw NativeTaskGraphValidationError.invalidRollover(
            taskID: parent.id,
            reason: "authorized requires a terminal recurring task")
        }
        if parent.recurrenceRolloverState == "revoked",
          !(active && parent.recurrence != nil)
        {
          throw NativeTaskGraphValidationError.invalidRollover(
            taskID: parent.id,
            reason: "revoked requires an active recurring task")
        }
        guard parent.recurrenceRolloverState == "authorized" else { continue }
        guard let child = tasksByID[successorID] else {
          throw NativeTaskGraphValidationError.missingEndpoint(
            relation: "authorized recurrence successor", identity: successorID)
        }
        guard child.spawnedFrom == parent.id,
          child.recurrenceGroupID == groupID,
          child.spawnedFromVersion == parent.lifecycleVersion
        else {
          throw NativeTaskGraphValidationError.invalidRollover(
            taskID: parent.id,
            reason: "authorized successor does not carry the exact parent lifecycle generation")
        }
      default:
        throw NativeTaskGraphValidationError.invalidRollover(
          taskID: parent.id, reason: "unknown rollover state \(parent.recurrenceRolloverState)")
      }
    }
  }

  private static func validateRelations(
    _ snapshot: NativeTaskGraphSnapshot,
    tasksByID: [String: NativeTaskSnapshot],
    taskIDs: Set<String>,
    knownTagIDs: Set<String>?,
    observedVersions: inout [Hlc]
  ) throws {
    var recurrenceExceptionIDs = Set<String>()
    var exceptionCountByTask: [String: Int] = [:]
    for row in snapshot.recurrenceExceptions {
      try requireEndpoint(row.taskID, relation: "recurrence exception owner", in: taskIDs)
      guard tasksByID[row.taskID]?.recurrence != nil else {
        throw NativeTaskGraphValidationError.invalidRelation(
          relation: "recurrence exception", reason: "the owner is not recurring")
      }
      try requireDate(row.exceptionDate, field: "recurrenceException.exceptionDate")
      try insertUnique(
        "\(row.taskID)\u{0}\(row.exceptionDate)", kind: "recurrence exception",
        into: &recurrenceExceptionIDs)
      // A legitimately exported graph-v1 archive was capped when authored, so
      // an over-count here is a hostile or corrupt archive.
      let count = (exceptionCountByTask[row.taskID] ?? 0) + 1
      exceptionCountByTask[row.taskID] = count
      if count > maxRecurrenceExceptions {
        throw NativeTaskGraphValidationError.invalidRelation(
          relation: "recurrence exception",
          reason: "a task holds at most \(maxRecurrenceExceptions) recurrence exceptions")
      }
    }

    var tagEdgeIDs = Set<String>()
    for edge in snapshot.tagEdges {
      try requireEndpoint(edge.taskID, relation: "task-tag task", in: taskIDs)
      try requireCanonicalUuid(edge.tagID, field: "taskTag.tagID")
      if let knownTagIDs {
        try requireEndpoint(edge.tagID, relation: "task-tag tag", in: knownTagIDs)
      }
      try requireTimestamp(edge.createdAt, field: "taskTag.createdAt")
      try insertUnique(
        "\(edge.taskID)\u{0}\(edge.tagID)", kind: "task-tag edge", into: &tagEdgeIDs)
      observedVersions.append(edge.version)
    }

    var dependencyEdgeIDs = Set<String>()
    for edge in snapshot.dependencyEdges {
      try requireEndpoint(edge.taskID, relation: "dependency task", in: taskIDs)
      try requireEndpoint(
        edge.dependsOnTaskID, relation: "dependency target", in: taskIDs)
      guard edge.taskID != edge.dependsOnTaskID else {
        throw NativeTaskGraphValidationError.invalidRelation(
          relation: "task dependency", reason: "a task cannot depend on itself")
      }
      guard tasksByID[edge.taskID]?.status != "cancelled",
        tasksByID[edge.dependsOnTaskID]?.status != "cancelled"
      else {
        throw NativeTaskGraphValidationError.invalidRelation(
          relation: "task dependency", reason: "a cancelled task remains an endpoint")
      }
      try requireTimestamp(edge.createdAt, field: "taskDependency.createdAt")
      try insertUnique(
        "\(edge.taskID)\u{0}\(edge.dependsOnTaskID)", kind: "task dependency edge",
        into: &dependencyEdgeIDs)
      observedVersions.append(edge.version)
    }
    try validateDependencyAcyclic(
      snapshot.dependencyEdges, taskIDs: taskIDs)

    var checklistIDs = Set<String>()
    for item in snapshot.checklistItems {
      try requireEndpoint(item.taskID, relation: "checklist owner", in: taskIDs)
      try requireCanonicalUuid(item.id, field: "checklist.id")
      guard item.position >= 0 else {
        throw invalidValue("checklist.position", "item \(item.id) is negative")
      }
      guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw invalidValue("checklist.text", "item \(item.id) is empty")
      }
      try requireOptionalTimestamp(item.completedAt, field: "checklist.completedAt")
      try requireTimestamp(item.createdAt, field: "checklist.createdAt")
      try requireTimestamp(item.updatedAt, field: "checklist.updatedAt")
      try insertUnique(item.id, kind: "checklist item", into: &checklistIDs)
      observedVersions.append(item.version)
    }

    var reminderIDs = Set<String>()
    for reminder in snapshot.reminders {
      try requireEndpoint(reminder.taskID, relation: "reminder owner", in: taskIDs)
      try requireCanonicalUuid(reminder.id, field: "reminder.id")
      try requireTimestamp(reminder.reminderAt, field: "reminder.reminderAt")
      try requireOptionalTimestamp(reminder.dismissedAt, field: "reminder.dismissedAt")
      try requireOptionalTimestamp(reminder.cancelledAt, field: "reminder.cancelledAt")
      try requireTimestamp(reminder.createdAt, field: "reminder.createdAt")
      try validateReminderAnchor(reminder)
      try insertUnique(reminder.id, kind: "task reminder", into: &reminderIDs)
      if let owner = tasksByID[reminder.taskID],
        owner.status == "completed" || owner.status == "cancelled"
      {
        guard reminder.dismissedAt != nil || reminder.cancelledAt != nil else {
          throw NativeTaskGraphValidationError.invalidRelation(
            relation: "task reminder", reason: "a terminal task retains an active reminder")
        }
      }
      observedVersions.append(reminder.version)
    }
  }

  private static func validateDependencyAcyclic(
    _ edges: [NativeTaskDependencyEdgeSnapshot], taskIDs: Set<String>
  ) throws {
    var outgoing: [String: [String]] = [:]
    var incomingCount = Dictionary(uniqueKeysWithValues: taskIDs.map { ($0, 0) })
    for edge in edges {
      outgoing[edge.taskID, default: []].append(edge.dependsOnTaskID)
      incomingCount[edge.dependsOnTaskID, default: 0] += 1
    }
    var queue = incomingCount.keys.filter { incomingCount[$0] == 0 }.sorted()
    var cursor = 0
    var visited = 0
    while cursor < queue.count {
      let taskID = queue[cursor]
      cursor += 1
      visited += 1
      for target in (outgoing[taskID] ?? []).sorted() {
        let next = (incomingCount[target] ?? 0) - 1
        incomingCount[target] = next
        if next == 0 { queue.append(target) }
      }
    }
    guard visited == taskIDs.count else {
      throw NativeTaskGraphValidationError.dependencyCycle(
        taskIDs: incomingCount.filter { $0.value > 0 }.map(\.key).sorted())
    }
  }

  private static func validateSyncArtifacts(
    _ snapshot: NativeTaskGraphSnapshot,
    observedVersions: inout [Hlc]
  ) throws {
    let liveVersions = liveSyncVersions(snapshot)
    var tombstoneIdentities = Set<String>()
    for tombstone in snapshot.tombstones {
      try validateTaskSyncIdentity(
        entityType: tombstone.entityType, entityID: tombstone.entityID,
        field: "tombstone")
      let identity = syncIdentity(tombstone.entityType, tombstone.entityID)
      try insertUnique(
        identity, kind: "task-domain tombstone", into: &tombstoneIdentities)
      guard liveVersions[identity] == nil else {
        throw NativeTaskGraphValidationError.invalidRelation(
          relation: "task-domain tombstone",
          reason:
            "\(tombstone.entityType.asString):\(tombstone.entityID) is also present as a live row"
        )
      }
      guard BackupV1NativeTaskGraphSemantics.isOperationallyAcceptable(tombstone.version) else {
        throw invalidValue(
          "tombstone.version",
          "\(tombstone.entityType.asString):\(tombstone.entityID) exceeds the operational HLC ceiling"
        )
      }
      try requireTimestamp(tombstone.deletedAt, field: "tombstone.deletedAt")
      observedVersions.append(tombstone.version)
    }

    var shadowIdentities = Set<String>()
    for shadow in snapshot.payloadShadows {
      try validateTaskSyncIdentity(
        entityType: shadow.entityType, entityID: shadow.entityID,
        field: "payloadShadow")
      let identity = syncIdentity(shadow.entityType, shadow.entityID)
      try insertUnique(
        identity, kind: "task-domain payload shadow", into: &shadowIdentities)
      guard !tombstoneIdentities.contains(identity) else {
        throw NativeTaskGraphValidationError.invalidRelation(
          relation: "task-domain payload shadow",
          reason:
            "\(shadow.entityType.asString):\(shadow.entityID) is also tombstoned")
      }
      if shadow.entityType != .taskCalendarEventLink,
        liveVersions[identity] == nil
      {
        throw NativeTaskGraphValidationError.missingEndpoint(
          relation: "payload shadow live entity",
          identity: "\(shadow.entityType.asString):\(shadow.entityID)")
      }
      if let liveVersion = liveVersions[identity], shadow.baseVersion > liveVersion {
        throw NativeTaskGraphValidationError.invalidRelation(
          relation: "task-domain payload shadow",
          reason:
            "\(shadow.entityType.asString):\(shadow.entityID) is newer than its live row")
      }
      guard BackupV1NativeTaskGraphSemantics.isOperationallyAcceptable(shadow.baseVersion) else {
        throw invalidValue(
          "payloadShadow.baseVersion",
          "\(shadow.entityType.asString):\(shadow.entityID) exceeds the operational HLC ceiling"
        )
      }
      guard shadow.payloadSchemaVersion >= 1,
        shadow.payloadSchemaVersion <= maxPayloadSchemaVersion
      else {
        throw invalidValue(
          "payloadShadow.payloadSchemaVersion",
          "\(shadow.entityType.asString):\(shadow.entityID) is outside the accepted sync range"
        )
      }
      guard
        shadow.rawPayloadJSON.utf8.count <= maxRawPayloadJSONBytes,
        let parsed = JSONValue.parse(shadow.rawPayloadJSON),
        case .object = parsed,
        let canonical = try? canonicalizeJSON(parsed),
        canonical == shadow.rawPayloadJSON
      else {
        throw invalidValue(
          "payloadShadow.rawPayloadJSON",
          "\(shadow.entityType.asString):\(shadow.entityID) must be a bounded canonical JSON object"
        )
      }
      guard shadow.sourceDeviceID.utf8.count <= maxSourceDeviceIDBytes else {
        throw invalidValue(
          "payloadShadow.sourceDeviceID",
          "\(shadow.entityType.asString):\(shadow.entityID) exceeds the device-id byte cap"
        )
      }
      try requireTimestamp(shadow.updatedAt, field: "payloadShadow.updatedAt")
      observedVersions.append(shadow.baseVersion)
    }
  }

  private static func liveSyncVersions(
    _ snapshot: NativeTaskGraphSnapshot
  ) -> [String: Hlc] {
    var result: [String: Hlc] = [:]
    for task in snapshot.tasks {
      result[syncIdentity(.task, task.id)] = task.version
    }
    for edge in snapshot.tagEdges {
      result[syncIdentity(.taskTag, "\(edge.taskID):\(edge.tagID)")] = edge.version
    }
    for edge in snapshot.dependencyEdges {
      result[
        syncIdentity(
          .taskDependency,
          BackupV1NativeTaskGraphSemantics.dependencyEntityID(
            taskID: edge.taskID, dependsOnTaskID: edge.dependsOnTaskID))
      ] = edge.version
    }
    for item in snapshot.checklistItems {
      result[syncIdentity(.taskChecklistItem, item.id)] = item.version
    }
    for reminder in snapshot.reminders {
      result[syncIdentity(.taskReminder, reminder.id)] = reminder.version
    }
    return result
  }

  private static func validateTaskSyncIdentity(
    entityType: EntityKind, entityID: String, field: String
  ) throws {
    guard syncedEntityKinds.contains(entityType) else {
      throw invalidValue(
        "\(field).entityType", "\(entityType.asString) is outside the task domain")
    }
    guard BackupV1NativeTaskGraphSemantics.isCanonicalTaskSyncIdentity(
      kind: entityType, entityID: entityID)
    else {
      throw invalidValue(
        "\(field).entityID",
        "\(entityType.asString):\(entityID) is not a canonical sync identity")
    }
  }

  private static func syncIdentity(_ entityType: EntityKind, _ entityID: String) -> String {
    "\(entityType.asString)\u{0}\(entityID)"
  }

  private static func requireEndpoint(
    _ identity: String, relation: String, in identities: Set<String>
  ) throws {
    guard identities.contains(identity) else {
      throw NativeTaskGraphValidationError.missingEndpoint(
        relation: relation, identity: identity)
    }
  }

  private static func insertUnique(
    _ identity: String, kind: String, into identities: inout Set<String>
  ) throws {
    guard identities.insert(identity).inserted else {
      throw NativeTaskGraphValidationError.duplicateIdentity(kind: kind, identity: identity)
    }
  }

  private static func requireCanonicalUuid(_ value: String, field: String) throws {
    guard BackupV1NativeTaskGraphSemantics.isCanonicalUUID(value) else {
      throw invalidValue(field, "must be a canonical hyphenated lowercase UUID")
    }
  }

  private static func requireCanonicalListID(_ value: String, field: String) throws {
    guard BackupV1NativeTaskGraphSemantics.isCanonicalListID(value) else {
      throw invalidValue(field, "must be the inbox sentinel or a canonical lowercase UUID")
    }
  }

  private static func requireNonemptyTrimmed(_ value: String, field: String) throws {
    guard !value.isEmpty,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    else {
      throw invalidValue(field, "must be nonempty and whitespace-trimmed")
    }
  }

  private static func requireOptionalDate(_ value: String?, field: String) throws {
    guard let value else { return }
    try requireDate(value, field: field)
  }

  private static func requireDate(_ value: String, field: String) throws {
    guard BackupV1NativeTaskGraphSemantics.isCanonicalDate(value) else {
      throw invalidValue(field, "must be a real YYYY-MM-DD date")
    }
  }

  private static func requireOptionalTimestamp(_ value: String?, field: String) throws {
    guard let value else { return }
    try requireTimestamp(value, field: field)
  }

  private static func requireTimestamp(_ value: String, field: String) throws {
    guard BackupV1NativeTaskGraphSemantics.isCanonicalTimestamp(value) else {
      throw invalidValue(field, "must be a canonical UTC sync timestamp")
    }
  }

  private static func validateReminderAnchor(
    _ reminder: NativeTaskReminderSnapshot
  ) throws {
    guard (reminder.originalLocalTime == nil) == (reminder.originalTimeZone == nil) else {
      throw invalidValue("reminder.localTimeAnchor", "reminder \(reminder.id) has a partial pair")
    }
    guard let local = reminder.originalLocalTime,
      let zone = reminder.originalTimeZone
    else { return }
    let bytes = Array(local.utf8)
    guard bytes.count == 5, bytes[2] == 58,
      let hour = Int(local.prefix(2)), let minute = Int(local.suffix(2)),
      (0...23).contains(hour), (0...59).contains(minute),
      BackupV1NativeTaskGraphSemantics.isStableTimezoneIdentifier(zone)
    else {
      throw invalidValue(
        "reminder.localTimeAnchor", "reminder \(reminder.id) has an invalid local time or zone")
    }
  }

  private static func invalidValue(
    _ field: String, _ reason: String
  ) -> NativeTaskGraphValidationError {
    .invalidValue(field: field, reason: reason)
  }
}
