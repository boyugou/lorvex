import Foundation

/// Why CloudSync is durably paused. While a reason is set the controller runs
/// no ordinary push, pull, or zone creation until the user resolves it.
public enum CloudSyncPauseReason: String, Codable, Sendable, Equatable, CaseIterable {
  /// The live iCloud account differs from the account bound to local data.
  case accountChanged
  /// The user deleted Lorvex's CloudKit namespace. Re-creation requires consent.
  case userDeletedZone
}

/// Durable consent/safety state. A present but unreadable reason always fails
/// closed, and every write is durable before returning.
public protocol CloudSyncPauseStateStoring: Sendable {
  func loadPauseReason() async throws -> CloudSyncPauseReason?
  func savePauseReason(_ reason: CloudSyncPauseReason) async throws
  func clearPauseReason() async throws
}

/// File-backed pause state in the backup-eligible CloudSync safety directory.
/// An unrecognized reason fails closed: treating an unknown consent gate as
/// absent would be unsafe.
public actor FileCloudSyncPauseStateStore: CloudSyncPauseStateStoring {
  private struct PersistedState: Codable {
    var reason: CloudSyncPauseReason?
  }

  private static let fileName = "sync-pause-reason.json"
  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

  public func loadPauseReason() async throws -> CloudSyncPauseReason? {
    guard let data = try CloudSyncDurableStateFile.readIfPresent(at: fileURL) else { return nil }
    do {
      return try JSONDecoder().decode(PersistedState.self, from: data).reason
    } catch {
      throw CloudSyncDurableStateError.unreadable("pause state is undecodable")
    }
  }

  public func savePauseReason(_ reason: CloudSyncPauseReason) async throws {
    try write(PersistedState(reason: reason))
  }

  public func clearPauseReason() async throws {
    guard try await loadPauseReason() != nil else { return }
    try write(PersistedState(reason: nil))
  }

  private func write(_ state: PersistedState) throws {
    try CloudSyncDurableStateFile.write(try JSONEncoder().encode(state), to: fileURL)
  }
}
