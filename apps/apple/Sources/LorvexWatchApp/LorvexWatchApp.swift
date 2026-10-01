import Foundation
import LorvexCore
import LorvexWatch
import SwiftUI
import Synchronization

#if canImport(WatchConnectivity)
  import WatchConnectivity
#endif

/// watchOS app entry point.
///
/// Uses the workspace-fenced Watch replica in the shared App Group so the
/// companion can render the latest Today list published by the iPhone. It
/// reports a replica-unavailable state when the App Group container is
/// unavailable. Write actions (complete, start, pause, defer, cancel, capture,
/// habit check-off) are durably journaled and forwarded through
/// WatchConnectivity; the iPhone applies them and publishes a fresh replica.
@main
struct LorvexWatchApp: App {
  private let store: LorvexWatchStore
  #if canImport(WatchConnectivity)
    private let connectivityForwarder: WatchConnectivityMutationForwarder
  #endif

  init() {
    #if canImport(WatchConnectivity)
      // The forwarder owns the watch's WCSession delegate slot. It routes the
      // phone's latest application context into the replica receiver and uses
      // background user-info only for command acknowledgements. Accepted
      // replicas refresh both the App Group reader and complication timeline.
      let snapshotRefreshRelay = WatchSnapshotRefreshRelay()
      let replicaStore = LorvexWatchReplicaStore()
      let snapshotReceiver = LorvexWatchSnapshotReceiver(
        replicaStore: replicaStore,
        onSnapshotWritten: {
          snapshotRefreshRelay.refresh()
        })
      let concreteForwarder = WatchConnectivityMutationForwarder(
        snapshotReceiver: snapshotReceiver,
        replicaStore: replicaStore)
      let forwarder: any LorvexWatchMutationForwarding = concreteForwarder
    #else
      let forwarder: (any LorvexWatchMutationForwarding)? = nil
    #endif
    let builtStore: LorvexWatchStore
    #if DEBUG
      if LorvexWatchUIPreview.isRequested {
        // The headless capture tour's fixed sample day stands in for the App
        // Group replica; a sample that cannot be written is a build defect.
        guard let replicaURL = try? LorvexWatchUIPreview.writeReplica() else {
          fatalError("The watch UI preview replica could not be written.")
        }
        builtStore = LorvexWatchStoreFactory(
          snapshotURLProvider: { _ in replicaURL },
          mutationForwarder: LorvexWatchUIPreview.forwarder
        ).makeStore()
      } else {
        builtStore = LorvexWatchStoreFactory(mutationForwarder: forwarder).makeStore()
      }
    #else
      builtStore = LorvexWatchStoreFactory(mutationForwarder: forwarder).makeStore()
    #endif
    #if canImport(WatchConnectivity)
      snapshotRefreshRelay.setStore(builtStore)
      concreteForwarder.setDeliveryStatusHandler { [weak builtStore] status in
        Task { @MainActor in
          builtStore?.updateDeliveryStatus(status)
        }
      }
      connectivityForwarder = concreteForwarder
    #endif
    store = builtStore
  }

  var body: some Scene {
    WindowGroup {
      #if DEBUG
        LorvexWatchRootView(
          store: store, initialPage: LorvexWatchUIPreview.page,
          opensActions: LorvexWatchUIPreview.opensActions)
      #else
        LorvexWatchRootView(store: store)
      #endif
    }
    #if os(watchOS)
      .backgroundTask(.watchConnectivity) { _ in
        await connectivityForwarder.handleBackgroundWake()
      }
    #endif
  }
}

#if canImport(WatchConnectivity)
  private final class WatchSnapshotRefreshRelay: Sendable {
    private let refreshAction = Mutex<(@Sendable () -> Void)?>(nil)

    func setStore(_ store: LorvexWatchStore) {
      refreshAction.withLock { action in
        action = {
          Task { @MainActor in
            await store.refresh()
          }
        }
      }
    }

    func refresh() {
      let action = refreshAction.withLock { $0 }
      action?()
    }
  }
#endif
