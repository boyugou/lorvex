import Foundation

/// One-shot bridge that resolves its awaiter with whichever of a push's sync
/// work or its deadline finishes first (see
/// ``MobileStore/handleCloudKitPush(applicationIsActive:backgroundDeadline:)``).
///
/// Lock-guarded so the two racing tasks — the main-actor work and the
/// off-main deadline timer — can call ``finish(_:)`` from different executors
/// without a data race; only the first takes effect and resumes the awaiter
/// exactly once. A result delivered before the awaiter suspends is stashed and
/// returned immediately, so the race is correct regardless of task-scheduling
/// order.
final class CloudSyncLifecycleRace: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<MobileCloudSyncLifecycleResult, Never>?
  private var pending: MobileCloudSyncLifecycleResult?
  private var finished = false

  func value() async -> MobileCloudSyncLifecycleResult {
    await withCheckedContinuation { continuation in
      lock.lock()
      if let pending {
        lock.unlock()
        continuation.resume(returning: pending)
      } else {
        self.continuation = continuation
        lock.unlock()
      }
    }
  }

  func finish(_ result: MobileCloudSyncLifecycleResult) {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    let awaiting = continuation
    continuation = nil
    if awaiting == nil { pending = result }
    lock.unlock()
    awaiting?.resume(returning: result)
  }
}
