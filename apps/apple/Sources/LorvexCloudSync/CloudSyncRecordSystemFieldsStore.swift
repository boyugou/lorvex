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

  /// Writes any change the store is still holding back (a store may coalesce
  /// its writes). Called at the end of an explicit sync pass, which is also the
  /// pass the iPhone runs as it leaves the foreground.
  func flush() async
}

extension CloudSyncRecordSystemFieldsStoring {
  public func flush() async {}

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
///
/// The file holds an entry for every record the zone has, and each write
/// rewrites it whole, so entries stored or removed within `coalescingDelay` of
/// each other reach the file in one write (``flush()`` writes at once). A
/// first sync of thousands of records then writes the file a few times rather
/// than once per batch. Changes lost to a crash inside that window cost one
/// `serverRecordChanged` per record, like any missing or stale entry. Forgetting
/// a whole account or zone is written at once, since a stale tag from another
/// zone costs an `unknownItem` round trip per record.
public actor FileCloudSyncRecordSystemFieldsStore: CloudSyncRecordSystemFieldsStoring {
  private let fileURL: URL
  private let coalescingDelay: Duration
  private var cache: [String: Data]?
  private var writeScheduled = false

  public init(directory: URL, coalescingDelay: Duration = .seconds(2)) {
    self.fileURL = directory.appendingPathComponent("record-system-fields.json")
    self.coalescingDelay = coalescingDelay
  }

  public func flush() async {
    guard writeScheduled else { return }
    writeNow()
  }

  /// Writes the cache after `coalescingDelay`, once for every change made in
  /// the meantime.
  private func scheduleWrite() {
    guard !writeScheduled else { return }
    writeScheduled = true
    let delay = coalescingDelay
    Task { [weak self] in
      try? await Task.sleep(for: delay)
      await self?.flush()
    }
  }

  private func writeNow() {
    writeScheduled = false
    persist(cache ?? [:])
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
    scheduleWrite()
  }

  public func remove(accountIdentifier: String, zoneName: String, recordName: String) async {
    var map = loaded()
    guard
      map.removeValue(
        forKey: key(
          accountIdentifier: accountIdentifier, zoneName: zoneName, recordName: recordName)) != nil
    else { return }
    cache = map
    scheduleWrite()
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
    scheduleWrite()
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
    scheduleWrite()
  }

  public func removeAll(accountIdentifier: String, zoneName: String) async {
    var map = loaded()
    let prefix = keyPrefix(accountIdentifier: accountIdentifier, zoneName: zoneName)
    let priorCount = map.count
    map = map.filter { !$0.key.hasPrefix(prefix) }
    guard map.count != priorCount else { return }
    cache = map
    writeNow()
  }

  public func removeAll() async {
    cache = [:]
    writeNow()
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
