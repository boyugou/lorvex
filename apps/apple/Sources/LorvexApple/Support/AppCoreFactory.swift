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

    /// Builds this Mac's one `CloudSyncController`, over the per-container
    /// sync-state directory. Built in every mode, so "Delete iCloud Data"
    /// works with sync off. `stateDirectoryOverride` redirects the on-disk
    /// sync state for tests; production passes nil.
    static func makeCloudSyncController(
        core: any LorvexCoreServicing,
        stateDirectoryOverride: URL? = nil
    ) -> CloudSyncController? {
        guard let store = core as? any CloudSyncEngineStore else { return nil }
        return CloudSyncFactory.makeController(
            store: store,
            containerIdentifier: AppMetadata.cloudKitContainerIdentifier,
            stateDirectory: stateDirectoryOverride ?? CloudSyncFactory.stateDirectory(
                appName: "LorvexApple",
                containerIdentifier: AppMetadata.cloudKitContainerIdentifier))
    }
}
