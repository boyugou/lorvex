import Foundation

/// Device-local cache of archived CKRecord system fields, keyed by account,
/// physical custom zone, and record name.
///
/// CloudKit fixes each record's change tag on the server, and a freshly built
/// `CKRecord` carries no tag. Under `.ifServerRecordUnchanged` (the LWW push
/// barrier) a tag-less record that already exists on the server always comes back
/// `serverRecordChanged`, so — absent this cache — every push after an entity's
/// first save would drop into per-record HLC conflict resolution, one serial
/// re-save per record (SY10: a 200-row chunk becomes up to 200 sequential round
/// trips, tripping `requestRateLimited`).
///
/// Persisting the system fields CloudKit returns on save lets the next push
/// re-hydrate the record with its current change tag, so an unchanged-on-server
/// re-push succeeds inside the batch with no per-record round trip. The cache is
/// best-effort and self-healing: a stale or missing entry costs exactly one
/// `serverRecordChanged`, which the HLC backstop still resolves correctly and
/// then re-caches. It holds no user content — system fields are recordID + change
/// tag + timestamps — so it is a device-local file, never a synced table.
public protocol CloudSyncRecordSystemFieldsStoring: Sendable {
  func systemFields(
    accountIdentifier: String, zoneName: String, recordName: String
  ) async -> Data?

  func store(
    _ systemFields: Data, accountIdentifier: String, zoneName: String, recordName: String
  ) async

  func remove(accountIdentifier: String, zoneName: String, recordName: String) async

  func removeAll(accountIdentifier: String, zoneName: String) async

  /// Forget every cached entry. Called when the zone identity changes out from
  /// under the cache — account adopt, `zoneNotFound` recreation, or a
  /// user-deleted-zone re-opt-in — so no stale change tag from the old zone
  /// survives to make a push satisfy `.ifServerRecordUnchanged` against a record
  /// that does not exist in the new zone (which returns `unknownItem` per record
  /// and, since that is not transient, moves the outbox toward retry wait).
  func removeAll() async

  /// Store many entries with one write. A first sync can cache thousands of
  /// records; writing them one by one would rewrite the backing file each time.
  func storeAll(_ entries: [String: Data], accountIdentifier: String, zoneName: String) async

  /// Forget the given record names with one write.
  func remove(recordNames: Set<String>, accountIdentifier: String, zoneName: String) async
}

extension CloudSyncRecordSystemFieldsStoring {
  public func storeAll(
    _ entries: [String: Data], accountIdentifier: String, zoneName: String
  ) async {
    for (recordName, data) in entries {
      await store(data, accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)
    }
  }

  public func remove(
    recordNames: Set<String>, accountIdentifier: String, zoneName: String
  ) async {
    for recordName in recordNames {
      await remove(accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)
    }
  }
}

/// File-backed ``CloudSyncRecordSystemFieldsStoring``: one JSON file mapping
/// record name → base64 system fields, mirrored in an in-memory dictionary so a
/// push batch does not re-read the file per record. Writes are atomic. It uses
/// the established device-local sync-state pattern so reconstructible transport
/// cache does not become durable user
/// schema and there is nothing to migrate.
public actor FileCloudSyncRecordSystemFieldsStore: CloudSyncRecordSystemFieldsStoring {
  private let fileURL: URL
  private var cache: [String: Data]?

  public init(directory: URL) {
    self.fileURL = directory.appendingPathComponent("record-system-fields.json")
  }

  public func systemFields(
    accountIdentifier: String, zoneName: String, recordName: String
  ) async -> Data? {
    loaded()[key(accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)]
  }

  public func store(
    _ systemFields: Data, accountIdentifier: String, zoneName: String, recordName: String
  ) async {
    var map = loaded()
    map[key(accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)] = systemFields
    cache = map
    persist(map)
  }

  public func remove(accountIdentifier: String, zoneName: String, recordName: String) async {
    var map = loaded()
    guard
      map.removeValue(
        forKey: key(
          accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)) != nil
    else { return }
    cache = map
    persist(map)
  }

  public func storeAll(
    _ entries: [String: Data], accountIdentifier: String, zoneName: String
  ) async {
    guard !entries.isEmpty else { return }
    var map = loaded()
    for (recordName, data) in entries {
      map[key(accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)] = data
    }
    cache = map
    persist(map)
  }

  public func remove(
    recordNames: Set<String>, accountIdentifier: String, zoneName: String
  ) async {
    guard !recordNames.isEmpty else { return }
    var map = loaded()
    let priorCount = map.count
    for recordName in recordNames {
      map.removeValue(
        forKey: key(accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName))
    }
    guard map.count != priorCount else { return }
    cache = map
    persist(map)
  }

  public func removeAll(accountIdentifier: String, zoneName: String) async {
    var map = loaded()
    let prefix = keyPrefix(accountIdentifier: accountIdentifier, zoneName: zoneName)
    let priorCount = map.count
    map = map.filter { !$0.key.hasPrefix(prefix) }
    guard map.count != priorCount else { return }
    cache = map
    persist(map)
  }

  public func removeAll() async {
    cache = [:]
    persist([:])
  }

  private func loaded() -> [String: Data] {
    if let cache { return cache }
    let map: [String: Data] =
      (try? Data(contentsOf: fileURL))
      .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }?
      .compactMapValues { Data(base64Encoded: $0) } ?? [:]
    cache = map
    return map
  }

  private func persist(_ map: [String: Data]) {
    guard let data = try? JSONEncoder().encode(map.mapValues { $0.base64EncodedString() }) else {
      return
    }
    let directory = fileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Cached CKRecord change tags are reconstructible: keep them excluded from
    // backup so a restore does not carry stale tags that would make a push
    // satisfy `.ifServerRecordUnchanged` against records the restored database
    // never held. Reapplied on each write (an atomic write can clear the flag).
    CloudSyncBackupExclusion.exclude(directory)
    try? data.write(to: fileURL, options: [.atomic])
  }

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
