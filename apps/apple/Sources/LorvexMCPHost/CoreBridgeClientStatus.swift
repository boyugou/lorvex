import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadSyncStatus() async throws -> Value {
    let sync = try await service.loadRuntimeDiagnostics().sync
    // Hoist the optional-to-Value conversions into locals: a single large
    // dictionary literal with many inline `map ?? .null` ternaries trips the
    // Swift type-checker's expression-time heuristic.
    let oldestPendingAt: Value = sync.oldestPendingAt.map(Value.string) ?? .null
    let newestPendingAt: Value = sync.newestPendingAt.map(Value.string) ?? .null
    let lastSyncedAt: Value = sync.lastSyncedAt.map(Value.string) ?? .null
    let lastError: Value = sync.lastError.map(Value.string) ?? .null
    let deviceID: Value = sync.deviceID.map(Value.string) ?? .null
    return .object([
      "sync_backend_kind_raw": .null,
      "sync_backend_kind": .string(sync.backend),
      "sync_backend_kind_effective": .string(sync.backend),
      "sync_backend_kind_malformed": .bool(false),
      "sync_backend_kind_malformed_reason": .null,
      "pending_count": .int(sync.pendingCount),
      "retrying_count": .int(sync.retryingCount),
      "failed_count": .int(sync.failedCount),
      "oldest_pending_at": oldestPendingAt,
      "newest_pending_at": newestPendingAt,
      "last_synced_at": lastSyncedAt,
      "last_error": lastError,
      "device_id": deviceID,
      "reseed_required": .bool(sync.reseedRequired),
    ])
  }

  func loadSetupStatus() async throws -> Value {
    let setup = try await service.loadRuntimeDiagnostics().setup
    let defaultListReady = setup.defaultListID != nil
    return .object([
      "setup_completed": .bool(setup.setupCompleted),
      "setup_state": .object([
        "list_count": .int(setup.listCount),
        "default_list_id": setup.defaultListID.map(Value.string) ?? .null,
        "lists_ready": .bool(setup.listCount > 0),
        "default_list_ready": .bool(defaultListReady),
        "working_hours_ready": .bool(setup.workingHours != nil),
        "normal_task_creation_ready": .bool(setup.listCount > 0),
        "prerequisites_ready": .bool(setup.listCount > 0),
        "explicit_setup_completed": .bool(setup.setupCompleted),
        "setup_completed": .bool(setup.setupCompleted),
      ]),
      "existing_preferences": .object([
        "working_hours": setup.workingHours.map(Value.string) ?? .null,
        "default_list_id": setup.defaultListID.map(Value.string) ?? .null,
      ]),
      "list_count": .int(setup.listCount),
      "task_count": .int(setup.taskCount),
    ])
  }
}
