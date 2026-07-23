import Foundation
import LorvexCore

/// Builds the CloudSync runtime (mode, push subscriber, engine coordinator) for
/// a surface that owns only a core + App-Group config, with no macOS
/// `AppSettingsStore`.
///
/// This is the shared, platform-neutral construction path. The host supplies its
/// CloudKit container identifier and a sync-state directory; everything else
/// (generation controller, account checker, pusher, and fetcher) is wired
/// identically to the macOS lifecycle. The macOS app keeps its own
/// `AppSettingsStore`-driven construction in `AppCoreFactory`; both realize the
/// same wiring, so a later convergence can point macOS at this factory.
public enum CloudSyncFactory {
  /// Resolves the effective `CloudSyncMode`. The env var `LORVEX_CLOUDKIT_EXPORT`
  /// overrides the persisted setting: "record-plan" → `.recordPlan`, "live" →
  /// `.live`, any other non-nil value → `.off`. Absent env var → `persistedMode`
  /// (default `.off`).
  public static func resolveMode(
    persistedMode: CloudSyncMode = .off,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> CloudSyncMode {
    switch environment["LORVEX_CLOUDKIT_EXPORT"] {
    case "record-plan": return .recordPlan
    case "live": return .live
    case .some: return .off
    case .none: return persistedMode
    }
  }

  /// The push subscriber for `mode`: a real `CKDatabaseSubscription` installer
  /// for `.recordPlan`/`.live`, a no-op for `.off`.
  public static func makeSubscriber(
    mode: CloudSyncMode,
    containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier
  ) -> any CloudSyncSubscribing {
    switch mode {
    case .recordPlan, .live:
      return CloudKitCloudSyncSubscriber(containerIdentifier: containerIdentifier)
    case .off:
      return NoOpCloudSyncSubscriber()
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

  /// The engine coordinator (outbound outbox→CK + inbound CK→applyEnvelope) for
  /// `.live` mode. `.recordPlan` and `.off` produce no coordinator — the cycle
  /// silently no-ops.
  ///
  /// The reconstructible CloudKit system-fields cache is
  /// routed to the backup-excluded ``reconstructibleCacheDirectory(_:)``
  /// subdirectory; the consent/account state (identity fingerprint, pause reason)
  /// stays in `stateDirectory`, backup-eligible.
  public static func makeCoordinator(
    mode: CloudSyncMode,
    containerIdentifier: String = LorvexProductMetadata.cloudKitContainerIdentifier,
    stateDirectory: URL
  ) -> CloudSyncEngineCoordinator? {
    guard mode == .live else { return nil }
    let cacheDirectory = prepareStateDirectories(base: stateDirectory)
    return CloudSyncEngineCoordinator(
      accountChecker: LiveCloudKitAccountStatusChecker(containerIdentifier: containerIdentifier),
      pusher: CloudKitRecordPusher(
        containerIdentifier: containerIdentifier,
        systemFieldsStore: FileCloudSyncRecordSystemFieldsStore(directory: cacheDirectory)),
      fetcher: CloudKitRemoteChangeFetcher(containerIdentifier: containerIdentifier),
      accountIdentifier: CloudKitUserRecordAccountIdentifier(containerIdentifier: containerIdentifier),
      accountIdentityStore: FileCloudSyncAccountIdentityStore(directory: stateDirectory),
      accountPauseStore: FileCloudSyncPauseStateStore(directory: stateDirectory)
    )
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
