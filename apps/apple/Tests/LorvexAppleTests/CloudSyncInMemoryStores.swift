import Foundation

@testable import LorvexCloudSync

/// Pause state held in memory, for tests of the controller and the stores.
actor InMemoryCloudSyncPauseStateStore: CloudSyncPauseStateStoring {
  private var reason: CloudSyncPauseReason?

  init(reason: CloudSyncPauseReason? = nil) {
    self.reason = reason
  }

  func loadPauseReason() async -> CloudSyncPauseReason? { reason }
  func savePauseReason(_ reason: CloudSyncPauseReason) async { self.reason = reason }
  func clearPauseReason() async { reason = nil }
}

/// Account identity held in memory, for tests.
actor InMemoryCloudSyncAccountIdentityStore: CloudSyncAccountIdentityStoring {
  private var identifier: String?

  init(identifier: String? = nil) {
    self.identifier = identifier
  }

  func loadLastAccountIdentifier() async -> String? { identifier }

  func saveLastAccountIdentifier(_ identifier: String) async {
    self.identifier = identifier
  }
}

/// Record system fields held in memory, for tests.
actor InMemoryCloudSyncRecordSystemFieldsStore: CloudSyncRecordSystemFieldsStoring {
  private var map: [String: Data] = [:]

  init() {}

  func systemFields(
    accountIdentifier: String, zoneName: String, recordName: String
  ) async -> Data? {
    map[key(accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)]
  }

  func store(
    _ systemFields: Data, accountIdentifier: String, zoneName: String, recordName: String
  ) async {
    map[key(accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)] = systemFields
  }

  func remove(accountIdentifier: String, zoneName: String, recordName: String) async {
    map.removeValue(
      forKey: key(
        accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName))
  }

  func removeAll(accountIdentifier: String, zoneName: String) async {
    let prefix = keyPrefix(accountIdentifier: accountIdentifier, zoneName: zoneName)
    map = map.filter { !$0.key.hasPrefix(prefix) }
  }

  func removeAll() async {
    map.removeAll()
  }

  /// Test helper: number of cached records.
  func cachedRecordCount() -> Int { map.count }

  /// Test helper: forget every cached entry (simulate a lost / never-persisted
  /// cache to prove the conflict path returns without it).
  func clear() { map.removeAll() }

  private func key(accountIdentifier: String, zoneName: String, recordName: String) -> String {
    keyPrefix(accountIdentifier: accountIdentifier, zoneName: zoneName) + encoded(recordName) + "|"
  }

  private func keyPrefix(accountIdentifier: String, zoneName: String) -> String {
    encoded(accountIdentifier) + "|" + encoded(zoneName) + "|"
  }

  private func encoded(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
  }
}
