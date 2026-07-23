import Foundation
import LorvexDomain
import Synchronization

/// Constructs the live `LorvexCoreServicing` implementation.
///
/// The production backend is always `SwiftLorvexCoreService` (the GRDB-backed
/// pure-Swift core in `apps/apple/core/`), opening the single Lorvex-managed App
/// Group store. An unsandboxed dev/source build additionally honors a launch-time
/// `LORVEX_APPLE_DB_PATH` override; a sandboxed build ignores that override and
/// always resolves the managed store. Mock and in-memory services are test
/// fixtures only and are never selectable through the product runtime environment.
public enum LorvexCoreRuntimeFactory {
  public static let databasePathEnvironmentKey = "LORVEX_APPLE_DB_PATH"

  /// Test-only isolation hook for App Intent, widget, and notification perform
  /// paths that construct their own core service and have no dependency-injection
  /// seam. Bound to a temp database path so concurrent perform tests never race
  /// the process-global managed location. Product code never binds this value.
  @TaskLocal public static var databaseOverride: String?

  /// One cached service per surface. The system surfaces (`makeForAppIntent` /
  /// `makeForWidget` / `makeForNotification` / `makeForMobile`) are invoked
  /// repeatedly within one process — once per intent/notification/widget perform
  /// — and each fresh `SwiftLorvexCoreService` carries its own HLC clock. Reusing
  /// one service per surface keeps a single clock alive for the process and
  /// avoids re-opening the store + replaying the full-schema DDL on every
  /// invocation. `HlcObserver` is last-install-wins, so merge-minted HLCs advance
  /// whichever service's clock installed most recently; a short-lived extra
  /// service can no longer strand the observer on a discarded clock, but reuse
  /// still avoids the per-invocation store re-open.
  private static let serviceCache = Mutex<[HlcSurface: any LorvexCoreServicing]>([:])

  public static func make(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    surface: HlcSurface = .app
  ) -> any LorvexCoreServicing {
    // Every surface this factory serves — the app UI, App Intents / Shortcuts /
    // Siri, interactive widgets, notification actions, mobile, CarPlay, and the
    // phone-side watch-mutation apply — is a human surface, so each service
    // declares `.user` provenance for its `ai_changelog` writes. The MCP host
    // constructs its own `.mcp` service directly (fail-closed default) and binds
    // `.assistant` per tool call, so it never routes through here.
    let humanInitiator = SwiftLorvexCoreService.ChangelogInitiator.user
    // Test-only per-task override: never cached, so concurrent tests binding
    // different databases never collide on a shared instance.
    if let path = databaseOverride {
      return SwiftLorvexCoreService(
        databasePath: path, surface: surface, writeInitiatorDefault: humanInitiator)
    }
    // The dev `LORVEX_APPLE_DB_PATH` override is honored only on unsandboxed
    // builds; a sandboxed process ignores it and resolves the managed store.
    if !AppSandboxEnvironment.isSandboxed(environment: environment),
      let explicitPath = environment[databasePathEnvironmentKey]?.nilIfEmpty
    {
      return cachedService(surface: surface) {
        SwiftLorvexCoreService(
          databasePath: explicitPath, surface: surface, writeInitiatorDefault: humanInitiator)
      }
    }
    return cachedService(surface: surface) {
      SwiftLorvexCoreService(
        databasePath: nil, surface: surface, writeInitiatorDefault: humanInitiator)
    }
  }

  /// Returns the cached service for `surface`, building and storing one via
  /// `makeService` on first use. Thread-safe: the factory is reached from
  /// multiple executors (widget intents, notification actions, CarPlay).
  /// `makeService` only constructs the service — the store opens lazily on first
  /// use — so running it under the lock stays cheap.
  private static func cachedService(
    surface: HlcSurface,
    makeService: () -> any LorvexCoreServicing
  ) -> any LorvexCoreServicing {
    serviceCache.withLock { cache in
      if let cached = cache[surface] {
        return cached
      }
      let service = makeService()
      cache[surface] = service
      return service
    }
  }

  /// Storage-cutover invalidation: drops every cached per-surface service and
  /// closes each one's open store, so no cached connection — an intent, widget,
  /// or notification surface served earlier in this process — keeps writing to a
  /// database file that is about to be deleted (factory reset). The next `make`
  /// for any surface constructs a fresh service that opens the current store
  /// lazily. The factory reset invokes this so the stale store is released
  /// promptly rather than lingering until ARC deallocates it.
  public static func invalidateCachedServices() {
    let dropped = serviceCache.withLock { cache in
      let services = Array(cache.values)
      cache.removeAll()
      return services
    }
    // closeStoreForCutover blocks until each service's active operation leases
    // drain. Run it outside the cache lock so a lease body that reaches this
    // factory can never deadlock against the drain.
    for service in dropped {
      (service as? SwiftLorvexCoreService)?.closeStoreForCutover()
    }
  }

  /// Test-only: drops every cached per-surface service so one test's factory
  /// calls never hand a later test a service (and open store) another test
  /// cached. Unlike ``invalidateCachedServices()`` it does NOT close the
  /// dropped services' stores — a test may still hold and use one. Product
  /// code never calls this.
  public static func resetCachedServicesForTesting() {
    serviceCache.withLock { $0.removeAll() }
  }

  public static func makeForAppIntent(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any LorvexCoreServicing {
    make(environment: environment, surface: .appIntent)
  }

  public static func makeForWidget(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any LorvexCoreServicing {
    make(environment: environment, surface: .widget)
  }

  public static func makeForNotification(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any LorvexCoreServicing {
    make(environment: environment, surface: .notification)
  }

  public static func makeForMobile(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> any LorvexCoreServicing {
    make(environment: environment, surface: .mobile)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
