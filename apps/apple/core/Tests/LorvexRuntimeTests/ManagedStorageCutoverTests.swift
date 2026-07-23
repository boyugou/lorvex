import Foundation
import GRDB
import LorvexStore
import XCTest

@testable import LorvexRuntime

/// The managed database's factory-reset cutover primitive
/// (`ManagedStorageGeneration.resetDatabase` / `withSharedCutoverLock`): under an
/// exclusive cross-process flock, bump the durable storage generation, then
/// delete the database and its sidecars — bump FIRST so any later failure leaves
/// the data intact and reconnectable. All paths are injected temp directories;
/// no real containers are touched.
final class ManagedStorageCutoverTests: XCTestCase {
  private var tempRoot: URL!

  override func setUpWithError() throws {
    tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("lorvex-storage-cutover-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempRoot {
      try? FileManager.default.removeItem(at: tempRoot)
    }
  }

  /// The managed database both the app and its helpers/extensions resolve.
  private var targetDbPath: String {
    tempRoot.appendingPathComponent("GroupContainer/Lorvex/db.sqlite").path
  }

  // MARK: - Fixtures

  @discardableResult
  private func makeDatabase(at path: String) throws -> LorvexStore {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    return try LorvexStore.open(at: url, schemaSQL: RuntimeTestSupport.loadSchemaSQL())
  }

  private func generation() -> Int? {
    ManagedStorageGeneration.read(forDatabase: targetDbPath)
  }

  private func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  // MARK: - The factory-reset cutover primitive

  func testResetBumpsGenerationAndDeletesDatabase() throws {
    try makeDatabase(at: targetDbPath)
    try ManagedInstallIdentity.write(forDatabase: targetDbPath, deviceId: "pre-reset-device")
    // Simulate live sidecars beside the database.
    FileManager.default.createFile(atPath: targetDbPath + "-wal", contents: Data("wal".utf8))
    FileManager.default.createFile(atPath: targetDbPath + "-shm", contents: Data("shm".utf8))

    // No marker exists yet (it is stamped lazily by the first reset), so the
    // generation advances from 0 to 1 and the database + sidecars are removed.
    let next = try ManagedStorageGeneration.resetDatabase(atPath: targetDbPath)

    XCTAssertEqual(next, 1)
    XCTAssertEqual(generation(), 1)
    XCTAssertFalse(exists(targetDbPath))
    XCTAssertFalse(exists(targetDbPath + "-wal"))
    XCTAssertFalse(exists(targetDbPath + "-shm"))
    XCTAssertFalse(exists(ManagedInstallIdentity.markerPath(forDatabase: targetDbPath)))
  }

  func testResetOnMissingDatabaseStillBumps() throws {
    // Nothing to erase is not a failure; the generation still advances so any
    // process that opened (and created) the file concurrently reconnects.
    let first = try ManagedStorageGeneration.resetDatabase(atPath: targetDbPath)
    XCTAssertEqual(first, 1)
    let second = try ManagedStorageGeneration.resetDatabase(atPath: targetDbPath)
    XCTAssertEqual(second, 2)
  }

  func testExclusiveReplacementAdvanceIsDurable() throws {
    try makeDatabase(at: targetDbPath)

    let result = try ManagedStorageGeneration.withExclusiveCutoverLock(
      forDatabase: targetDbPath
    ) { advanceGenerationForReplacement in
      XCTAssertNil(generation())
      let next = try advanceGenerationForReplacement()
      XCTAssertEqual(next, 1)
      XCTAssertEqual(generation(), 1)
      return "replaced"
    }

    XCTAssertEqual(result, "replaced")
    XCTAssertEqual(generation(), 1)
  }

  func testExclusiveHealthyRecheckDoesNotAdvanceGeneration() throws {
    try makeDatabase(at: targetDbPath)

    let result = try ManagedStorageGeneration.withExclusiveCutoverLock(
      forDatabase: targetDbPath
    ) { _ in
      "healthy"
    }

    XCTAssertEqual(result, "healthy")
    XCTAssertNil(generation())
  }

  func testResetThrowsWhenDatabaseCannotBeDeleted() throws {
    try makeDatabase(at: targetDbPath)
    let dir = (targetDbPath as NSString).deletingLastPathComponent
    let fm = FileManager.default
    // Removing a file needs write permission on its parent directory.
    try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir)
    defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir) }

    XCTAssertThrowsError(try ManagedStorageGeneration.resetDatabase(atPath: targetDbPath))
    // A failed erase must leave the database intact, never a false success.
    XCTAssertTrue(exists(targetDbPath))
  }

  /// The shared cutover lock an opener holds across its open + generation
  /// capture blocks a concurrent factory reset from bumping-then-deleting, so
  /// the opener can never observe the reset's half-done ABA window.
  func testSharedCutoverLockExcludesConcurrentReset() throws {
    try makeDatabase(at: targetDbPath)
    let shortLock = ManagedStorageLock.LockConfiguration(
      acquireTimeout: 0.2, retryInterval: 0.05)

    try ManagedStorageGeneration.withSharedCutoverLock(forDatabase: targetDbPath) {
      // A reset needs the exclusive lock; it must fail while the shared lock is
      // held rather than mutate storage under the open. The reset's throw is
      // consumed here so the closure itself stays non-throwing.
      var resetThrew = false
      do {
        _ = try ManagedStorageGeneration.resetDatabase(
          atPath: targetDbPath, lockConfiguration: shortLock)
      } catch {
        resetThrew = true
      }
      XCTAssertTrue(resetThrew, "the reset acquired the exclusive lock under a live shared lock")
      XCTAssertTrue(exists(targetDbPath))
      XCTAssertNil(generation())
    }
    // Once released, the reset proceeds.
    XCTAssertEqual(try ManagedStorageGeneration.resetDatabase(atPath: targetDbPath), 1)
    XCTAssertFalse(exists(targetDbPath))
  }

  /// Symmetric with the reset side: an opener that cannot take the shared lock
  /// because a factory reset holds it exclusively must fail closed — throw
  /// `lockUnavailable` and NEVER run its open/capture body — rather than proceed
  /// unguarded into the reset's ABA window and commit a write to the doomed inode.
  func testSharedCutoverLockFailsClosedWhileExclusiveHeld() throws {
    try makeDatabase(at: targetDbPath)
    let shortLock = ManagedStorageLock.LockConfiguration(
      acquireTimeout: 0.2, retryInterval: 0.05)

    // Stand in for a reset in progress: hold the cutover lock EXCLUSIVELY.
    let reset = try XCTUnwrap(
      ManagedStorageLock.FileLock(
        path: ManagedStorageLock.lockFilePath(forDatabase: targetDbPath)))
    defer { reset.release() }
    XCTAssertTrue(ManagedStorageLock.acquire(reset, mode: .exclusive, configuration: shortLock))

    var bodyRan = false
    XCTAssertThrowsError(
      try ManagedStorageGeneration.withSharedCutoverLock(
        forDatabase: targetDbPath, lockConfiguration: shortLock) { bodyRan = true }
    ) { error in
      guard case ManagedStorageGeneration.ResetError.lockUnavailable = error else {
        return XCTFail("expected lockUnavailable, got \(error)")
      }
    }
    XCTAssertFalse(bodyRan, "the opener ran its body unguarded while a reset held the exclusive lock")
  }

  /// A torn (present-but-unparseable) marker must fail the reset closed rather
  /// than regress the monotonic generation to 1 — regressing would let an open
  /// that recorded the higher generation keep serving a deleted inode.
  func testResetFailsClosedOnCorruptMarker() throws {
    try makeDatabase(at: targetDbPath)
    XCTAssertEqual(try ManagedStorageGeneration.resetDatabase(atPath: targetDbPath), 1)

    let markerPath = ManagedStorageGeneration.markerPath(forDatabase: targetDbPath)
    try Data("{ truncated".utf8).write(to: URL(fileURLWithPath: markerPath))
    XCTAssertNil(ManagedStorageGeneration.read(forDatabase: targetDbPath))

    XCTAssertThrowsError(try ManagedStorageGeneration.resetDatabase(atPath: targetDbPath)) { error in
      guard case ManagedStorageGeneration.ResetError.markerCorrupt = error else {
        return XCTFail("expected markerCorrupt, got \(error)")
      }
    }
    // The corrupt marker is left untouched (not silently reset to 1).
    XCTAssertNil(ManagedStorageGeneration.read(forDatabase: targetDbPath))
  }
}
