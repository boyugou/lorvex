import Foundation
import LorvexRuntime
import os

/// Reads and writes the active Focus-filter state beside the managed App-Group
/// database so the host app and App Intents extension see one atomic value.
///
/// Configuration and revision are one JSON payload, atomically replaced. Revision
/// minting and the replace run under the managed database's existing exclusive
/// cutover flock, serializing independent app/extension processes without a
/// second lock protocol. Reads need no lock: atomic rename exposes either the
/// complete old payload or the complete new payload.
public actor FocusFilterStore {
  private static let log = Logger(subsystem: "com.lorvex.apple", category: "focus-filter")
  private static let formatVersion = 1
  private static let maxStateBytes = 64 * 1024

  private let managedDatabasePath: String
  private let stateURL: URL
  /// Generation observed when this store instance was created. A system-intent
  /// request may be suspended behind a factory reset's cutover lock; retaining
  /// this token lets the eventual save reject that delayed pre-reset writer.
  private let openedStorageGeneration: Int
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  public init(managedDatabasePath: String) {
    self.managedDatabasePath = managedDatabasePath
    self.openedStorageGeneration =
      ManagedStorageGeneration.read(forDatabase: managedDatabasePath) ?? 0
    self.stateURL = URL(
      fileURLWithPath: managedDatabasePath + LorvexProductMetadata.focusFilterStateFileSuffix)
  }

  /// Reads the complete stored state. A missing file is the initial inactive
  /// revision; a present-but-invalid file fails closed because treating an
  /// unknown prior revision as zero could let an old projection win.
  public func loadState() throws -> FocusFilterState {
    let data: Data
    do {
      data = try Data(contentsOf: stateURL)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return .inactive(storageGeneration: currentStorageGeneration())
    } catch {
      Self.log.error(
        "Focus filter state at \(self.stateURL.path, privacy: .private) is unreadable: \(String(describing: error), privacy: .public)")
      throw FocusFilterStoreError.corruptState(stateURL.path)
    }
    do {
      guard data.count <= Self.maxStateBytes else {
        throw FocusFilterStoreError.corruptState(stateURL.path)
      }
      let persisted = try decoder.decode(PersistedState.self, from: data)
      let currentGeneration = currentStorageGeneration()
      guard persisted.version == Self.formatVersion, persisted.revision >= 0,
        persisted.storageGeneration == currentGeneration
      else {
        throw FocusFilterStoreError.corruptState(stateURL.path)
      }
      return FocusFilterState(
        configuration: persisted.configuration,
        revision: persisted.revision,
        storageGeneration: persisted.storageGeneration)
    } catch {
      Self.log.error(
        "Focus filter state at \(self.stateURL.path, privacy: .private) is unreadable: \(String(describing: error), privacy: .public)")
      if let error = error as? FocusFilterStoreError { throw error }
      throw FocusFilterStoreError.corruptState(stateURL.path)
    }
  }

  public func load() throws -> FocusFilterConfiguration {
    try loadState().configuration
  }

  /// Atomically persist `configuration` at the next monotonic revision.
  ///
  /// The exclusive managed-storage lock serializes the read-increment-write
  /// across processes. It does not advance the physical storage generation;
  /// Focus policy is a local sidecar update, not a database replacement.
  @discardableResult
  public func save(_ configuration: FocusFilterConfiguration) throws -> FocusFilterState {
    try ManagedStorageGeneration.withExclusiveCutoverLock(
      forDatabase: managedDatabasePath
    ) { _ in
      let currentGeneration = currentStorageGeneration()
      guard currentGeneration == openedStorageGeneration else {
        throw FocusFilterStoreError.supersededStorageGeneration
      }
      let current = try loadState()
      let (nextRevision, overflow) = current.revision.addingReportingOverflow(1)
      guard !overflow else { throw FocusFilterStoreError.revisionExhausted }
      let next = FocusFilterState(
        configuration: configuration,
        revision: nextRevision,
        storageGeneration: currentGeneration)
      let persisted = PersistedState(
        version: Self.formatVersion,
        revision: next.revision,
        storageGeneration: next.storageGeneration,
        configuration: next.configuration)
      let data = try encoder.encode(persisted)
      let directory = stateURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
      try data.write(to: stateURL, options: .atomic)
      return next
    }
  }

  /// Persists the inactive policy at a new revision. Removing the file would
  /// reset its ordering to zero and let an already-running stale publisher win.
  @discardableResult
  public func reset() throws -> FocusFilterState {
    try save(.inactive)
  }

  private func currentStorageGeneration() -> Int {
    ManagedStorageGeneration.read(forDatabase: managedDatabasePath) ?? 0
  }

  private struct PersistedState: Codable {
    let version: Int
    let revision: Int
    let storageGeneration: Int
    let configuration: FocusFilterConfiguration

    enum CodingKeys: String, CodingKey {
      case version
      case revision
      case storageGeneration = "storage_generation"
      case configuration
    }
  }
}

public enum FocusFilterStoreError: Error, Equatable, Sendable {
  case corruptState(String)
  case revisionExhausted
  case supersededStorageGeneration
}
