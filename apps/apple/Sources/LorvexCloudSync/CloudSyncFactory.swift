import Foundation
import LorvexCore

/// Builds the CloudSync runtime (mode and controller) for the macOS and iOS
/// main apps. The host supplies its CloudKit container identifier and a
/// sync-state directory; everything else is wired identically on both.
public enum CloudSyncFactory {
  /// Resolves the effective `CloudSyncMode`. The env var `LORVEX_CLOUD_SYNC`
  /// overrides the persisted setting: "live" → `.live`, any other non-nil
  /// value → `.off`. Absent env var → `persistedMode`
  /// (default `.off`).
  public static func resolveMode(
    persistedMode: CloudSyncMode = .off,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> CloudSyncMode {
    switch environment["LORVEX_CLOUD_SYNC"] {
    case "live": return .live
    case .some: return .off
    case .none: return persistedMode
    }
  }

  /// The reconstructible-cache subdirectory of a sync-state directory.
  ///
  /// A sync-state directory holds two lifecycles with opposite backup needs. The
  /// reconstructible cached `CKRecord` system fields live HERE and are excluded
  /// from backup. The CONSENT /
  /// account-safety state (account fingerprint, pause reason incl. `userDeletedZone`)
  /// stays in the PARENT directory, backup-eligible, so the deletion/adopt gates
  /// survive a restore.
  public static func reconstructibleCacheDirectory(_ base: URL) -> URL {
    base.appendingPathComponent("Cache", isDirectory: true)
  }

  /// Create the sync-state directory split and apply the backup policy: the
  /// parent (consent/account state) is left backup-eligible, the reconstructible
  /// cache subdirectory is excluded from backup. Returns the cache subdirectory.
  /// Best-effort — a failed create/flag must not block coordinator construction;
  /// the cache stores reapply the exclusion on every write as the durable
  /// backstop.
  @discardableResult
  public static func prepareStateDirectories(base: URL) -> URL {
    let cache = reconstructibleCacheDirectory(base)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    CloudSyncBackupExclusion.exclude(cache)
    return cache
  }

  /// The CKSyncEngine-backed controller that owns this device's sync.
  ///
  /// Built regardless of the sync mode: "Delete iCloud Data" must work while
  /// sync is off, and the host starts or stops the controller as the mode
  /// changes. A store constructs exactly one controller per sync-state
  /// directory, because the file-backed pause, identity, and system-fields
  /// stores assume a single owner.
  ///
  /// The reconstructible CloudKit system-fields cache lives in the
  /// backup-excluded ``reconstructibleCacheDirectory(_:)``; the consent and
  /// account state (identity fingerprint, pause reason) stays in
  /// `stateDirectory`, backup-eligible.
  public static func makeController(
    store: any CloudSyncEngineStore,
    containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier,
    stateDirectory: URL
  ) -> CloudSyncController {
    let cacheDirectory = prepareStateDirectories(base: stateDirectory)
    return CloudSyncController(
      store: store,
      accountChecker: LiveCloudKitAccountStatusChecker(containerIdentifier: containerIdentifier),
      accountIdentifier: CloudKitUserRecordAccountIdentifier(containerIdentifier: containerIdentifier),
      accountIdentityStore: FileCloudSyncAccountIdentityStore(directory: stateDirectory),
      pauseStore: FileCloudSyncPauseStateStore(directory: stateDirectory),
      systemFieldsStore: FileCloudSyncRecordSystemFieldsStore(directory: cacheDirectory),
      makeEngine: LiveCloudSyncEngine.factory(containerIdentifier: containerIdentifier))
  }

  /// A stable, per-app sync-state directory under Application Support:
  /// `<AppSupport>/<appName>/CloudSyncState/<sanitized container>`.
  /// Falls back to the temporary directory when Application Support is
  /// unavailable.
  public static func stateDirectory(
    appName: String,
    containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier
  ) -> URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent(appName, isDirectory: true)
      .appendingPathComponent("CloudSyncState", isDirectory: true)
      .appendingPathComponent(
        sanitizedContainerPathComponent(containerIdentifier),
        isDirectory: true)
  }

  private static func sanitizedContainerPathComponent(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
    return raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
      .map(String.init)
      .joined()
  }
}
