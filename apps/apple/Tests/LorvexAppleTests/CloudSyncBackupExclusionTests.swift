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

  let coordinator = CloudSyncFactory.makeCoordinator(mode: .live, stateDirectory: base)
  #expect(coordinator != nil)

  let cache = CloudSyncFactory.reconstructibleCacheDirectory(base)
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

  await store.store(Data([0xAB]), forRecordName: "task|abc")

  #expect(isExcludedFromBackup(dir) == true)
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
