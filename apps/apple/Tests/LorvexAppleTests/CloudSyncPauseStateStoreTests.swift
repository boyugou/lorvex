import Foundation
import LorvexCloudSync
import Testing

/// The durable pause file: current reasons round-trip, and any reason this
/// build does not know is an unreadable consent gate that fails closed.
@Suite("Cloud sync pause state store")
struct CloudSyncPauseStateStoreTests {
  private func makeDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-pause-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func writePauseFile(in dir: URL, json: String) throws {
    try Data(json.utf8).write(to: dir.appendingPathComponent("sync-pause-reason.json"))
  }

  @Test
  func anAbsentFileMeansNoPause() async throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FileCloudSyncPauseStateStore(directory: dir)

    #expect(try await store.loadPauseReason() == nil)
  }

  @Test(arguments: CloudSyncPauseReason.allCases)
  func currentReasonsRoundTripThroughTheFile(_ reason: CloudSyncPauseReason) async throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FileCloudSyncPauseStateStore(directory: dir)

    try await store.savePauseReason(reason)
    #expect(try await FileCloudSyncPauseStateStore(directory: dir).loadPauseReason() == reason)

    try await store.clearPauseReason()
    #expect(try await FileCloudSyncPauseStateStore(directory: dir).loadPauseReason() == nil)
  }

  @Test
  func extraFieldsInTheFileAreIgnored() async throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    try writePauseFile(in: dir, json: #"{"revision":3,"reason":"userDeletedZone"}"#)
    let store = FileCloudSyncPauseStateStore(directory: dir)

    #expect(try await store.loadPauseReason() == .userDeletedZone)
  }

  @Test(arguments: ["somethingElse", "backfillFailed", "adoptionInProgress"])
  func anUnknownReasonFailsClosed(_ unknown: String) async throws {
    let dir = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    try writePauseFile(in: dir, json: #"{"reason":"\#(unknown)"}"#)
    let store = FileCloudSyncPauseStateStore(directory: dir)

    await #expect(throws: CloudSyncDurableStateError.self) {
      _ = try await store.loadPauseReason()
    }
    await #expect(throws: CloudSyncDurableStateError.self) {
      try await store.clearPauseReason()
    }
  }
}
