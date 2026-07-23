import Foundation
import LorvexCore
import LorvexCloudSync

enum AppCoreFactory {
    /// Builds the app's main-surface core service.
    ///
    /// Storage is fixed: the pure-Swift GRDB core always opens the single Lorvex-
    /// managed App Group database (cross-device sync is CloudKit-only). Passing
    /// `databasePath: nil` defers to the core's `DbLocator`, which resolves the
    /// managed location — and, on unsandboxed dev/source builds, a launch-time
    /// `LORVEX_APPLE_DB_PATH` override. That override is resolved directly by the
    /// core, immutable for the process lifetime; production sandboxed builds never
    /// carry it, so they always open the managed store. There is no runtime
    /// database selection, security-scoped bookmark, or per-surface divergence.
    ///
    /// `writeInitiatorDefault: .user` declares the macOS app a human surface, so
    /// every AppStore write states `user` provenance intentionally rather than
    /// relying on a default; a forgotten binding on a non-human path stays
    /// fail-closed (see `SwiftLorvexCoreService.writeInitiatorDefault`).
    @MainActor
    static func make() -> any LorvexCoreServicing {
        SwiftLorvexCoreService(
            databasePath: nil,
            writeInitiatorDefault: SwiftLorvexCoreService.ChangelogInitiator.user)
    }

    // MARK: - Cloud Sync factory methods

    /// Resolves the effective `CloudSyncMode` for the current process.
    ///
    /// The env var `LORVEX_CLOUDKIT_EXPORT` overrides the persisted setting:
    /// "record-plan" → `.recordPlan`, "live" → `.live`, any other non-nil value → `.off`.
    /// When the env var is absent, `persistedMode` is used; it defaults to `.off`.
    static func resolveCloudSyncMode(
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

    @MainActor
    static func makeCloudSyncSubscriber(settings: AppSettingsStore) -> any CloudSyncSubscribing {
        makeCloudSyncSubscriber(
            persistedMode: settings.cloudSyncMode,
            environment: settings.environment
        )
    }

    static func makeCloudSyncSubscriber(
        persistedMode: CloudSyncMode = .off,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any CloudSyncSubscribing {
        switch resolveCloudSyncMode(persistedMode: persistedMode, environment: environment) {
        case .recordPlan, .live:
            return CloudKitCloudSyncSubscriber(
                containerIdentifier: AppMetadata.cloudKitContainerIdentifier
            )
        case .off:
            return NoOpCloudSyncSubscriber()
        }
    }

    @MainActor
    static func makeCloudSyncCoordinator(
        settings: AppSettingsStore
    ) -> CloudSyncEngineCoordinator? {
        makeCloudSyncCoordinator(
            persistedMode: settings.cloudSyncMode,
            environment: settings.environment
        )
    }

    /// Builds the engine sync coordinator (outbound outbox→CK + inbound
    /// CK→applyEnvelope) for `.live` mode. `.recordPlan` and `.off` produce no
    /// coordinator — the cycle silently no-ops.
    ///
    /// `stateDirectoryOverride` redirects all on-disk sync safety/cache state
    /// (system-fields cache and account identity/pause) to a caller-supplied
    /// directory; production leaves it `nil` and the
    /// per-container Application Support directory is used.
    static func makeCloudSyncCoordinator(
        persistedMode: CloudSyncMode = .off,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stateDirectoryOverride: URL? = nil
    ) -> CloudSyncEngineCoordinator? {
        guard resolveCloudSyncMode(persistedMode: persistedMode, environment: environment) == .live
        else {
            return nil
        }
        return makeCloudDataMaintenanceCoordinator(
            stateDirectoryOverride: stateDirectoryOverride)
    }

    /// Coordinator for the Settings iCloud-data maintenance actions — "Delete
    /// iCloud Data" and the explicit sync re-enable that follows it. Built
    /// UNCONDITIONALLY, unlike ``makeCloudSyncCoordinator``: deleting the cloud
    /// copy must work while sync is off (the common case — the user turned sync
    /// off and now wants the iCloud data gone too), when the mode-gated factory
    /// deliberately returns nil.
    ///
    /// Wired over the same sync-state directory as ordinary live sync. A store
    /// must construct this value once, retain it for off-mode maintenance, and
    /// reuse the same value as its live coordinator; only one operation gate and
    /// file-backed actor set may own a sync-state directory.
    static func makeCloudDataMaintenanceCoordinator(
        stateDirectoryOverride: URL? = nil
    ) -> CloudSyncEngineCoordinator {
        let stateDirectory = stateDirectoryOverride ?? CloudSyncFactory.stateDirectory(
            appName: "LorvexApple",
            containerIdentifier: AppMetadata.cloudKitContainerIdentifier)
        // Split the sync-state directory by lifecycle (mirroring
        // `CloudSyncFactory.makeCoordinator`): the reconstructible CloudKit cache
        // (record system fields) lives in the
        // backup-EXCLUDED cache subdirectory so a restore cannot resurrect a stale
        // record-version cache, while the consent / account-safety state
        // (identity fingerprint, pause reason incl.
        // `userDeletedZone`) stays in the backup-eligible parent so the
        // deletion/adopt gates survive a restore.
        let cacheDirectory = CloudSyncFactory.prepareStateDirectories(
            base: stateDirectory)
        return CloudSyncEngineCoordinator(
            accountChecker: LiveCloudKitAccountStatusChecker(
                containerIdentifier: AppMetadata.cloudKitContainerIdentifier
            ),
            // The default-zone generation singleton is the durable cross-launch
            // authority. Ordinary sync never recreates a zone by name.
            pusher: CloudKitRecordPusher(
                containerIdentifier: AppMetadata.cloudKitContainerIdentifier,
                systemFieldsStore: FileCloudSyncRecordSystemFieldsStore(
                    directory: cacheDirectory)),
            fetcher: CloudKitRemoteChangeFetcher(
                containerIdentifier: AppMetadata.cloudKitContainerIdentifier
            ),
            accountIdentifier: CloudKitUserRecordAccountIdentifier(
                containerIdentifier: AppMetadata.cloudKitContainerIdentifier
            ),
            accountIdentityStore: FileCloudSyncAccountIdentityStore(directory: stateDirectory),
            accountPauseStore: FileCloudSyncPauseStateStore(directory: stateDirectory)
        )
    }

}
