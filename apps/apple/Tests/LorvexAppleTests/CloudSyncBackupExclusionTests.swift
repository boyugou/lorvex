import Foundation
import Testing

@testable import LorvexCloudSync

// CloudSync state has two backup lifecycles. Reconstructible CKRecord system
// fields are excluded; consent/account state remains backup-eligible. Change
// cursors are part of the managed SQLite database and need no sidecar policy.

private func isExcludedFromBackup(_ url: URL) -> Bool? {
  (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup
}

private func makeTempDirectoryURL(_ label: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-f4-\(label)-\(UUID().uuidString)", isDirectory: true)
}

@Test
func factorySplitsCacheFromConsentAndExcludesOnlyTheCache() throws {
  let base = makeTempDirectoryURL("factory")
  defer { try? FileManager.default.removeItem(at: base) }

  let cache = CloudSyncFactory.prepareStateDirectories(base: base)
  #expect(cache == CloudSyncFactory.reconstructibleCacheDirectory(base))
  #expect(FileManager.default.fileExists(atPath: cache.path))
  #expect(
    isExcludedFromBackup(cache) == true,
    "the reconstructible CloudKit cache subdirectory must be excluded from backup")
  #expect(
    isExcludedFromBackup(base) != true,
    "the consent / account-state parent directory must stay backup-eligible")
}

@Test
func recordSystemFieldsStoreExcludesItsDirectoryFromBackupOnWrite() async throws {
  let dir = makeTempDirectoryURL("sysfields")
  defer { try? FileManager.default.removeItem(at: dir) }
  let store = FileCloudSyncRecordSystemFieldsStore(directory: dir)

  await store.store(Data([0xAB]), accountIdentifier: "account-A", zoneName: "Lorvex", recordName: "task|abc")
  await store.flush()

  #expect(isExcludedFromBackup(dir) == true)
}

/// The system-fields file holds an entry for every record and is rewritten whole, so changes
/// close together reach it in one write; flush writes at once, and a new store reads them back.
@Test
func recordSystemFieldsStoreCoalescesWritesUntilFlushed() async throws {
  let dir = makeTempDirectoryURL("sysfields-coalesce")
  defer { try? FileManager.default.removeItem(at: dir) }
  let file = dir.appendingPathComponent("record-system-fields.json")
  let store = FileCloudSyncRecordSystemFieldsStore(directory: dir, coalescingDelay: .seconds(60))

  await store.storeAll(
    ["task|a": Data([1]), "task|b": Data([2])], accountIdentifier: "account-A", zoneName: "Lorvex")
  await store.remove(recordNames: ["task|b"], accountIdentifier: "account-A", zoneName: "Lorvex")
  #expect(!FileManager.default.fileExists(atPath: file.path), "nothing written before the flush")
  #expect(
    await store.systemFields(accountIdentifier: "account-A", zoneName: "Lorvex", recordName: "task|a")
      == Data([1]))

  await store.flush()
  let reopened = FileCloudSyncRecordSystemFieldsStore(directory: dir)
  #expect(
    await reopened.systemFields(accountIdentifier: "account-A", zoneName: "Lorvex", recordName: "task|a")
      == Data([1]))
  #expect(
    await reopened.systemFields(accountIdentifier: "account-A", zoneName: "Lorvex", recordName: "task|b")
      == nil)
}

@Test
func recordSystemFieldsStoreWritesOnItsOwnAfterTheDelay() async throws {
  let dir = makeTempDirectoryURL("sysfields-delay")
  defer { try? FileManager.default.removeItem(at: dir) }
  let file = dir.appendingPathComponent("record-system-fields.json")
  let store = FileCloudSyncRecordSystemFieldsStore(directory: dir, coalescingDelay: .milliseconds(50))

  await store.store(Data([7]), accountIdentifier: "account-A", zoneName: "Lorvex", recordName: "task|c")
  var waited = 0
  while !FileManager.default.fileExists(atPath: file.path), waited < 200 {
    try await Task.sleep(for: .milliseconds(25))
    waited += 1
  }
  #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test
func accountIdentityStoreDoesNotExcludeItsDirectoryFromBackup() async throws {
  let dir = makeTempDirectoryURL("identity")
  defer { try? FileManager.default.removeItem(at: dir) }
  let store = FileCloudSyncAccountIdentityStore(directory: dir)

  try await store.saveLastAccountIdentifier("account-A")

  #expect(
    isExcludedFromBackup(dir) != true,
    "the account-identity consent state must remain backup-eligible")
}

@Test
func pauseStateStoreDoesNotExcludeItsDirectoryFromBackup() async throws {
  let dir = makeTempDirectoryURL("pause")
  defer { try? FileManager.default.removeItem(at: dir) }
  let store = FileCloudSyncPauseStateStore(directory: dir)

  try await store.savePauseReason(.userDeletedZone)

  #expect(
    isExcludedFromBackup(dir) != true,
    "the userDeletedZone consent gate must remain backup-eligible")
}
