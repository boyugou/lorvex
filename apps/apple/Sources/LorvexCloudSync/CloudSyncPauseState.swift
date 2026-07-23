import Foundation

/// Why CloudSync is durably paused. While a reason is set the coordinator runs
/// no ordinary push, pull, or zone creation until the user resolves it.
public enum CloudSyncPauseReason: String, Codable, Sendable, Equatable, CaseIterable {
  /// The live iCloud account differs from the account bound to local data.
  case accountChanged
  /// The user deleted Lorvex's CloudKit namespace. Re-creation requires consent.
  case userDeletedZone
  /// An explicitly authorized adoption started but has not proved completion.
  case adoptionInProgress
  /// An authorized rebuild failed and is waiting for an explicit retry.
  case backfillFailed
}

/// Exact durable pause event. The revision distinguishes two occurrences of
/// the same reason, so consent prepared for one account switch or cloud deletion
/// cannot clear a newer event through a same-value ABA transition.
public struct CloudSyncPauseSnapshot: Codable, Sendable, Equatable {
  public let reason: CloudSyncPauseReason
  public let revision: UInt64

  public init(reason: CloudSyncPauseReason, revision: UInt64) {
    self.reason = reason
    self.revision = revision
  }
}

public enum CloudSyncPauseTransition: Sendable, Equatable {
  case applied(CloudSyncPauseSnapshot?)
  case rejected
}

/// Durable consent/safety state. A present but unreadable snapshot always fails
/// closed; every write is durable before returning. Exact-snapshot CAS is the
/// only API allowed to consume a user authorization.
public protocol CloudSyncPauseStateStoring: Sendable {
  func loadPauseSnapshot() async throws -> CloudSyncPauseSnapshot?
  func savePauseReason(_ reason: CloudSyncPauseReason) async throws
  func clearPauseReason() async throws

  @discardableResult
  func compareAndSetPauseSnapshot(
    expected: CloudSyncPauseSnapshot?, replacement: CloudSyncPauseReason?
  ) async throws -> CloudSyncPauseTransition

  /// Atomically set `reason` unless a deleted-zone consent gate is standing.
  @discardableResult
  func setPauseReasonPreservingUserDeletedZone(
    _ reason: CloudSyncPauseReason?
  ) async throws -> CloudSyncPauseReason?
}

extension CloudSyncPauseStateStoring {
  public func loadPauseReason() async throws -> CloudSyncPauseReason? {
    try await loadPauseSnapshot()?.reason
  }

  /// Convenience for non-consent transitions. It still performs an exact
  /// snapshot CAS after resolving the expected reason.
  @discardableResult
  public func compareAndSetPauseReason(
    expected: CloudSyncPauseReason?, replacement: CloudSyncPauseReason?
  ) async throws -> Bool {
    let snapshot = try await loadPauseSnapshot()
    guard snapshot?.reason == expected else { return false }
    guard case .applied = try await compareAndSetPauseSnapshot(
      expected: snapshot, replacement: replacement)
    else { return false }
    return true
  }
}

/// File-backed pause state in the backup-eligible CloudSync safety directory.
/// No legacy decoder is intentional: the app has no released installations,
/// and silently treating an unknown consent format as active would be unsafe.
public actor FileCloudSyncPauseStateStore: CloudSyncPauseStateStoring {
  private struct PersistedState: Codable {
    var revision: UInt64
    var reason: CloudSyncPauseReason?
  }

  private static let fileName = "sync-pause-reason.json"
  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

  public func loadPauseSnapshot() async throws -> CloudSyncPauseSnapshot? {
    snapshot(from: try loadState())
  }

  public func savePauseReason(_ reason: CloudSyncPauseReason) async throws {
    let current = try loadState()
    try writeState(
      PersistedState(revision: nextRevision(after: current.revision), reason: reason))
  }

  public func clearPauseReason() async throws {
    let current = try loadState()
    guard current.reason != nil else { return }
    try writeState(
      PersistedState(revision: nextRevision(after: current.revision), reason: nil))
  }

  @discardableResult
  public func compareAndSetPauseSnapshot(
    expected: CloudSyncPauseSnapshot?, replacement: CloudSyncPauseReason?
  ) async throws -> CloudSyncPauseTransition {
    let current = try loadState()
    guard snapshot(from: current) == expected else { return .rejected }
    let next = PersistedState(
      revision: nextRevision(after: current.revision), reason: replacement)
    try writeState(next)
    return .applied(snapshot(from: next))
  }

  @discardableResult
  public func setPauseReasonPreservingUserDeletedZone(
    _ reason: CloudSyncPauseReason?
  ) async throws -> CloudSyncPauseReason? {
    let current = try loadState()
    if current.reason == .userDeletedZone { return .userDeletedZone }
    guard current.reason != reason else { return reason }
    try writeState(
      PersistedState(revision: nextRevision(after: current.revision), reason: reason))
    return reason
  }

  private func loadState() throws -> PersistedState {
    guard let data = try CloudSyncDurableStateFile.readIfPresent(at: fileURL) else {
      return PersistedState(revision: 0, reason: nil)
    }
    do {
      let state = try JSONDecoder().decode(PersistedState.self, from: data)
      guard state.revision > 0 else {
        throw CloudSyncDurableStateError.unreadable("pause revision is invalid")
      }
      return state
    } catch let error as CloudSyncDurableStateError {
      throw error
    } catch {
      throw CloudSyncDurableStateError.unreadable("pause state is undecodable")
    }
  }

  private func snapshot(from state: PersistedState) -> CloudSyncPauseSnapshot? {
    state.reason.map { CloudSyncPauseSnapshot(reason: $0, revision: state.revision) }
  }

  private func nextRevision(after current: UInt64) -> UInt64 {
    let next = current &+ 1
    return next == 0 ? 1 : next
  }

  private func writeState(_ state: PersistedState) throws {
    try CloudSyncDurableStateFile.write(try JSONEncoder().encode(state), to: fileURL)
  }
}

public actor InMemoryCloudSyncPauseStateStore: CloudSyncPauseStateStoring {
  private var snapshot: CloudSyncPauseSnapshot?
  private var revision: UInt64

  public init(reason: CloudSyncPauseReason? = nil) {
    let initialRevision: UInt64 = reason == nil ? 0 : 1
    revision = initialRevision
    snapshot = reason.map { CloudSyncPauseSnapshot(reason: $0, revision: initialRevision) }
  }

  public func loadPauseSnapshot() async -> CloudSyncPauseSnapshot? { snapshot }

  public func savePauseReason(_ reason: CloudSyncPauseReason) async {
    snapshot = nextSnapshot(reason)
  }

  public func clearPauseReason() async {
    guard snapshot != nil else { return }
    advanceRevision()
    snapshot = nil
  }

  @discardableResult
  public func compareAndSetPauseSnapshot(
    expected: CloudSyncPauseSnapshot?, replacement: CloudSyncPauseReason?
  ) async -> CloudSyncPauseTransition {
    guard snapshot == expected else { return .rejected }
    if let replacement {
      let next = nextSnapshot(replacement)
      snapshot = next
      return .applied(next)
    }
    advanceRevision()
    snapshot = nil
    return .applied(nil)
  }

  @discardableResult
  public func setPauseReasonPreservingUserDeletedZone(
    _ reason: CloudSyncPauseReason?
  ) async -> CloudSyncPauseReason? {
    if snapshot?.reason == .userDeletedZone { return .userDeletedZone }
    guard snapshot?.reason != reason else { return reason }
    snapshot = reason.map(nextSnapshot)
    if reason == nil { advanceRevision() }
    return reason
  }

  private func nextSnapshot(_ reason: CloudSyncPauseReason) -> CloudSyncPauseSnapshot {
    advanceRevision()
    return CloudSyncPauseSnapshot(reason: reason, revision: revision)
  }

  private func advanceRevision() {
    revision &+= 1
    if revision == 0 { revision = 1 }
  }
}
