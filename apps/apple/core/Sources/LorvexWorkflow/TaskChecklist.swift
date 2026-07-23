import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-item checklist mutations: add, update text, toggle completion,
/// remove, reorder. Each op stamps a fresh `version` + `updated_at`
/// on every touched child row so peers' LWW reconciliation accepts the change.
public enum TaskChecklist {
  /// Sync-fanout operation applied to a single checklist item.
  public enum ChecklistSyncOperation: Sendable, Equatable {
    case upsert
    case delete

    public var asString: String {
      switch self {
      case .upsert: return SyncNaming.opUpsert
      case .delete: return SyncNaming.opDelete
      }
    }
  }

  /// One sync-fanout change record produced by a checklist mutation.
  /// `snapshot` is populated only for delete operations, carrying the
  /// pre-delete payload the sync layer enqueues as a tombstone body.
  public struct ChecklistItemSyncChange: Sendable, Equatable {
    public let itemId: String
    public let operation: ChecklistSyncOperation
    public let snapshot: JSONValue?
    public let version: String
  }

  /// Rich return shape from every checklist mutation: pre/post task
  /// JSON, a human-readable summary, and the per-item sync changes.
  public struct MutationResult: Sendable {
    public let taskId: String
    public let beforeTask: JSONValue
    public let afterTask: JSONValue
    public let summary: String
    public let itemSyncChanges: [ChecklistItemSyncChange]
  }

  // MARK: - Inputs

  public struct AddInput: Sendable {
    public let taskId: TaskId
    public let text: String
    public let position: UInt32?
    public init(taskId: TaskId, text: String, position: UInt32? = nil) {
      self.taskId = taskId
      self.text = text
      self.position = position
    }
  }

  public struct UpdateInput: Sendable {
    public let itemId: ChecklistItemId
    public let text: String
    public init(itemId: ChecklistItemId, text: String) {
      self.itemId = itemId
      self.text = text
    }
  }

  public struct ToggleInput: Sendable {
    public let itemId: ChecklistItemId
    public let completed: Bool
    public init(itemId: ChecklistItemId, completed: Bool) {
      self.itemId = itemId
      self.completed = completed
    }
  }

  public struct RemoveInput: Sendable {
    public let itemId: ChecklistItemId
    public init(itemId: ChecklistItemId) { self.itemId = itemId }
  }

  public struct ReorderInput: Sendable {
    public let taskId: TaskId
    public let itemIds: [ChecklistItemId]
    public init(taskId: TaskId, itemIds: [ChecklistItemId]) {
      self.taskId = taskId
      self.itemIds = itemIds
    }
  }

  // MARK: - Operations

  /// Insert a checklist item at `input.position` (or the end when
  /// omitted), re-stamping every sibling row's `position`.
  public static func addTaskChecklistItem(
    _ db: Database, hlc: HlcSession, input: AddInput
  ) throws -> MutationResult {
    let text = UnicodeHygiene.sanitizeUserText(input.text)
    do { try validateTaskChecklistItemText(text) } catch let e as ValidationError {
      throw StoreError.validation(e.description)
    }

    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: input.taskId)
    let title = TaskResponse.taskTitle(before)
    let existingItems = try fetchChecklistItemsForTask(db, taskId: input.taskId)
    do { try validateTaskChecklistItemCount(existingItems.count + 1) }
    catch let e as ValidationError {
      throw StoreError.validation(e.description)
    }

    let insertIndex: Int
    if let p = input.position {
      insertIndex = Int(p)
    } else {
      insertIndex = existingItems.count
    }
    if insertIndex > existingItems.count {
      throw StoreError.validation(
        "checklist insert position \(insertIndex) is out of range for task '\(input.taskId.asString)' with \(existingItems.count) items"
      )
    }

    let now = SyncTimestampFormat.syncTimestampNow()
    let newItemId = ChecklistItemId.new()
    var ordered = existingItems.map(\.itemId)
    ordered.insert(newItemId, at: insertIndex)
    let versionsById = Dictionary(
      uniqueKeysWithValues: existingItems.map { ($0.itemId.rawValue, $0.version) })

    var changes: [ChecklistItemSyncChange] = []
    changes.reserveCapacity(ordered.count)
    for (index, itemId) in ordered.enumerated() {
      let version = try VersionFloor.mint(
        hlc: hlc,
        existingVersion: versionsById[itemId.rawValue],
        entityType: EntityName.taskChecklistItem,
        entityId: itemId.rawValue)
      if itemId.rawValue == newItemId.rawValue {
        try db.execute(
          sql:
            "INSERT INTO task_checklist_items "
            + "(id, task_id, position, text, completed_at, version, created_at, updated_at) "
            + "VALUES (?, ?, ?, ?, NULL, ?, ?, ?)",
          arguments: [
            newItemId.rawValue, input.taskId.rawValue, Int64(index), text,
            version, now, now,
          ])
      } else {
        let existingVersion = versionsById[itemId.rawValue]
        try db.execute(
          sql:
            "UPDATE task_checklist_items "
            + "SET position = ?, version = ?, updated_at = ? "
            + "WHERE id = ? AND version = ?",
          arguments: [Int64(index), version, now, itemId.rawValue, existingVersion])
        try requireChecklistItemUpdate(
          db,
          itemId: itemId,
          attemptedVersion: version)
      }
      changes.append(itemUpsertChange(itemId, version: version))
    }

    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: input.taskId)
    return MutationResult(
      taskId: input.taskId.asString,
      beforeTask: before,
      afterTask: after,
      summary: "Added checklist item '\(text)' for '\(title)'",
      itemSyncChanges: changes)
  }

  /// Rewrite an item's text. Sanitized + validated.
  public static func updateTaskChecklistItem(
    _ db: Database, hlc: HlcSession, input: UpdateInput
  ) throws -> MutationResult {
    let text = UnicodeHygiene.sanitizeUserText(input.text)
    do { try validateTaskChecklistItemText(text) } catch let e as ValidationError {
      throw StoreError.validation(e.description)
    }

    let identity = try fetchChecklistItemIdentity(db, itemId: input.itemId)
    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: identity.taskId)
    let title = TaskResponse.taskTitle(before)
    let now = SyncTimestampFormat.syncTimestampNow()
    let version = try VersionFloor.mint(
      hlc: hlc,
      existingVersion: identity.version,
      entityType: EntityName.taskChecklistItem,
      entityId: input.itemId.rawValue)
    try db.execute(
      sql:
        "UPDATE task_checklist_items "
        + "SET text = ?, version = ?, updated_at = ? "
        + "WHERE id = ? AND version = ?",
      arguments: [text, version, now, input.itemId.rawValue, identity.version])
    try requireChecklistItemUpdate(db, itemId: input.itemId, attemptedVersion: version)

    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: identity.taskId)
    return MutationResult(
      taskId: identity.taskId.asString,
      beforeTask: before,
      afterTask: after,
      summary:
        "Updated checklist item '\(identity.text)' for '\(title)'",
      itemSyncChanges: [itemUpsertChange(input.itemId, version: version)])
  }

  /// Toggle `completed_at` (sets it to `now` when completing, NULL when
  /// reopening).
  public static func toggleTaskChecklistItem(
    _ db: Database, hlc: HlcSession, input: ToggleInput
  ) throws -> MutationResult {
    let identity = try fetchChecklistItemIdentity(db, itemId: input.itemId)
    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: identity.taskId)
    let title = TaskResponse.taskTitle(before)
    let now = SyncTimestampFormat.syncTimestampNow()
    let version = try VersionFloor.mint(
      hlc: hlc,
      existingVersion: identity.version,
      entityType: EntityName.taskChecklistItem,
      entityId: input.itemId.rawValue)
    let completedAt: String? = input.completed ? now : nil
    try db.execute(
      sql:
        "UPDATE task_checklist_items "
        + "SET completed_at = ?, version = ?, updated_at = ? "
        + "WHERE id = ? AND version = ?",
      arguments: [completedAt, version, now, input.itemId.rawValue, identity.version])
    try requireChecklistItemUpdate(db, itemId: input.itemId, attemptedVersion: version)

    let action = input.completed ? "Completed" : "Reopened"
    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: identity.taskId)
    return MutationResult(
      taskId: identity.taskId.asString,
      beforeTask: before,
      afterTask: after,
      summary: "\(action) checklist item '\(identity.text)' for '\(title)'",
      itemSyncChanges: [itemUpsertChange(input.itemId, version: version)])
  }

  /// Remove an item; restamps every remaining sibling's `position`.
  public static func removeTaskChecklistItem(
    _ db: Database, hlc: HlcSession, input: RemoveInput
  ) throws -> MutationResult {
    let identity = try fetchChecklistItemIdentity(db, itemId: input.itemId)
    let preDeleteSnapshot = try PayloadLoaders.loadTaskChecklistItemSyncPayload(
      db, itemId: input.itemId.rawValue)
    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: identity.taskId)
    let title = TaskResponse.taskTitle(before)
    let now = SyncTimestampFormat.syncTimestampNow()
    let deleteVersion = try VersionFloor.mint(
      hlc: hlc,
      existingVersion: identity.version,
      entityType: EntityName.taskChecklistItem,
      entityId: input.itemId.rawValue)
    let deletedSnapshot = preDeleteSnapshot.map {
      payload($0, replacingVersionWith: deleteVersion)
    }

    try db.execute(
      sql: "DELETE FROM task_checklist_items WHERE id = ? AND version = ?",
      arguments: [input.itemId.rawValue, identity.version])
    try requireChecklistItemDelete(
      db,
      itemId: input.itemId,
      attemptedVersion: deleteVersion)

    let remaining = try fetchChecklistItemsForTask(db, taskId: identity.taskId)
    var siblingChanges: [ChecklistItemSyncChange] = []
    siblingChanges.reserveCapacity(remaining.count)
    for (index, item) in remaining.enumerated() {
      let version = try VersionFloor.mint(
        hlc: hlc,
        existingVersion: item.version,
        entityType: EntityName.taskChecklistItem,
        entityId: item.itemId.rawValue)
      try db.execute(
        sql:
          "UPDATE task_checklist_items "
          + "SET position = ?, version = ?, updated_at = ? "
          + "WHERE id = ? AND version = ?",
        arguments: [Int64(index), version, now, item.itemId.rawValue, item.version])
      try requireChecklistItemUpdate(
        db,
        itemId: item.itemId,
        attemptedVersion: version)
      siblingChanges.append(itemUpsertChange(item.itemId, version: version))
    }

    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: identity.taskId)
    var changes: [ChecklistItemSyncChange] = []
    changes.reserveCapacity(remaining.count + 1)
    changes.append(
      ChecklistItemSyncChange(
        itemId: input.itemId.rawValue,
        operation: .delete,
        snapshot: deletedSnapshot,
        version: deleteVersion))
    changes.append(contentsOf: siblingChanges)

    return MutationResult(
      taskId: identity.taskId.asString,
      beforeTask: before,
      afterTask: after,
      summary: "Removed checklist item '\(identity.text)' for '\(title)'",
      itemSyncChanges: changes)
  }

  /// Reorder every item in one call. `itemIds` must contain every
  /// existing checklist item for `input.taskId` exactly once.
  public static func reorderTaskChecklistItems(
    _ db: Database, hlc: HlcSession, input: ReorderInput
  ) throws -> MutationResult {
    let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: input.taskId)
    let title = TaskResponse.taskTitle(before)
    let existing = try fetchChecklistItemsForTask(db, taskId: input.taskId)

    if input.itemIds.count != existing.count {
      throw StoreError.validation(
        "reorder_task_checklist_items requires exactly \(existing.count) ids for task '\(input.taskId.asString)', got \(input.itemIds.count)"
      )
    }
    let existingSet = Set(existing.map(\.itemId.rawValue))
    let requestedSet = Set(input.itemIds.map(\.rawValue))
    if existingSet != requestedSet || requestedSet.count != input.itemIds.count {
      throw StoreError.validation(
        "reorder_task_checklist_items must contain every checklist item for task '\(input.taskId.asString)' exactly once"
      )
    }

    let now = SyncTimestampFormat.syncTimestampNow()
    let versionsById = Dictionary(
      uniqueKeysWithValues: existing.map { ($0.itemId.rawValue, $0.version) })
    var changes: [ChecklistItemSyncChange] = []
    changes.reserveCapacity(input.itemIds.count)
    for (index, itemId) in input.itemIds.enumerated() {
      let existingVersion = versionsById[itemId.rawValue]
      let version = try VersionFloor.mint(
        hlc: hlc,
        existingVersion: existingVersion,
        entityType: EntityName.taskChecklistItem,
        entityId: itemId.rawValue)
      try db.execute(
        sql:
          "UPDATE task_checklist_items "
          + "SET position = ?, version = ?, updated_at = ? "
          + "WHERE id = ? AND task_id = ? AND version = ?",
        arguments: [
          Int64(index), version, now, itemId.rawValue, input.taskId.rawValue,
          existingVersion,
        ])
      try requireChecklistItemUpdate(db, itemId: itemId, attemptedVersion: version)
      changes.append(itemUpsertChange(itemId, version: version))
    }

    let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: input.taskId)
    return MutationResult(
      taskId: input.taskId.asString,
      beforeTask: before,
      afterTask: after,
      summary: "Reordered checklist items for '\(title)'",
      itemSyncChanges: changes)
  }

  // MARK: - Helpers

  /// Lightweight identity row read from a single SELECT, used by every
  /// per-item op to look up the owning task + display text for the
  /// summary string.
  struct ItemIdentity {
    let taskId: TaskId
    let text: String
    let position: Int64
    let completed: Bool
    let version: String
  }

  static func fetchChecklistItemIdentity(
    _ db: Database, itemId: ChecklistItemId
  ) throws -> ItemIdentity {
    guard
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT task_id, text, position, completed_at IS NOT NULL, version "
          + "FROM task_checklist_items WHERE id = ?",
        arguments: [itemId.rawValue])
    else {
      throw StoreError.notFound(
        entity: "checklist item", id: itemId.rawValue)
    }
    return ItemIdentity(
      taskId: TaskId(trusted: row[0]),
      text: row[1],
      position: row[2],
      completed: (row[3] as Int64) != 0,
      version: row[4])
  }

  struct VersionedItem {
    let itemId: ChecklistItemId
    let version: String
  }

  static func fetchChecklistItemsForTask(
    _ db: Database, taskId: TaskId
  ) throws -> [VersionedItem] {
    let rows = try Row.fetchAll(
      db,
      sql:
        "SELECT id, version FROM task_checklist_items "
        + "WHERE task_id = ? "
        + "ORDER BY position ASC, created_at ASC, id ASC",
      arguments: [taskId.rawValue])
    return rows.map {
      VersionedItem(itemId: ChecklistItemId(trusted: $0[0]), version: $0[1])
    }
  }

  static func requireChecklistItemUpdate(
    _ db: Database, itemId: ChecklistItemId, attemptedVersion: String
  ) throws {
    guard db.changesCount == 0 else { return }
    guard
      let winner = try String.fetchOne(
        db, sql: "SELECT version FROM task_checklist_items WHERE id = ?",
        arguments: [itemId.rawValue])
    else {
      throw StoreError.notFound(entity: EntityName.taskChecklistItem, id: itemId.rawValue)
    }
    throw StoreError.versionSuperseded(
      entityType: EntityName.taskChecklistItem,
      entityId: itemId.rawValue,
      attemptedVersion: attemptedVersion,
      existingVersion: winner)
  }

  static func requireChecklistItemDelete(
    _ db: Database, itemId: ChecklistItemId, attemptedVersion: String
  ) throws {
    guard db.changesCount == 0 else { return }
    guard
      let winner = try String.fetchOne(
        db, sql: "SELECT version FROM task_checklist_items WHERE id = ?",
        arguments: [itemId.rawValue])
    else {
      throw StoreError.notFound(entity: EntityName.taskChecklistItem, id: itemId.rawValue)
    }
    throw StoreError.versionSuperseded(
      entityType: EntityName.taskChecklistItem,
      entityId: itemId.rawValue,
      attemptedVersion: attemptedVersion,
      existingVersion: winner)
  }

  static func payload(_ payload: JSONValue, replacingVersionWith version: String) -> JSONValue {
    guard case .object(var object) = payload else { return payload }
    object["version"] = .string(version)
    return .object(object)
  }

  static func itemUpsertChange(
    _ itemId: ChecklistItemId, version: String
  ) -> ChecklistItemSyncChange {
    ChecklistItemSyncChange(
      itemId: itemId.rawValue, operation: .upsert, snapshot: nil, version: version)
  }
}
