import Foundation

/// FIFO async mutex shared by every copy of one coordinator value.
///
/// CloudKit account notifications, user adoption/deletion actions, and normal
/// sync cycles all mutate the same cursor, account, snapshot, and zone
/// generation state. Point-in-time identity checks do not prevent a MainActor
/// observer from re-entering while a detached cycle is suspended. The hosts
/// therefore route each top-level operation through this gate; internal helper
/// calls use explicitly unlocked variants to avoid recursive acquisition.
public actor CloudSyncOperationGate {
  private var isHeld = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init() {}

  public func acquire() async {
    if !isHeld {
      isHeld = true
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  public func release() {
    guard !waiters.isEmpty else {
      isHeld = false
      return
    }
    let next = waiters.removeFirst()
    // Ownership transfers directly; `isHeld` deliberately stays true.
    next.resume()
  }
}

extension CloudSyncEngineCoordinator {
  func withSerializedOperation<T: Sendable>(
    _ operation: @Sendable () async throws -> T
  ) async throws -> T {
    await operationGate.acquire()
    if Task.isCancelled {
      await operationGate.release()
      throw CancellationError()
    }
    do {
      let result = try await operation()
      await operationGate.release()
      return result
    } catch {
      await operationGate.release()
      throw error
    }
  }

  /// Run a local storage cutover only after every in-flight CloudSync operation
  /// reaches a terminal boundary, while preventing a new cycle/account action
  /// from entering until the cutover finishes. Used by factory reset before it
  /// closes and replaces the database beneath the coordinator.
  public func withQuiescedCloudSync<T: Sendable>(
    _ operation: @Sendable () async throws -> T
  ) async throws -> T {
    try await withSerializedOperation(operation)
  }
}
