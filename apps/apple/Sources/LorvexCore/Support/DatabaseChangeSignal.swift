import Foundation
import Synchronization

final class InProcessDatabaseChangeCoalescer: Sendable {
  private let postPending = Mutex(false)

  func enqueue(
    schedule: (@escaping @Sendable () -> Void) -> Void,
    deliver: @escaping @Sendable () -> Void
  ) {
    let shouldSchedule = postPending.withLock { pending in
      guard !pending else { return false }
      pending = true
      return true
    }
    guard shouldSchedule else { return }

    schedule { [self] in
      // Clear before delivery so a write racing the callback schedules a
      // trailing invalidation rather than being hidden by this burst.
      postPending.withLock { $0 = false }
      deliver()
    }
  }
}

/// Process-wide "the local database changed" invalidation signal.
///
/// Every ordinary local mutation through the Swift core's write funnel ends in
/// ``broadcastIfEnabled()`` after its transaction commits. A process opts into
/// the delivery it needs at startup: the app posts a coalesced in-process
/// invalidation so its independent window stores converge, while the MCP host
/// posts a Darwin notification so the running app sees helper-process writes.
/// Dedicated inbound-sync transactions publish explicitly from their completed
/// report. Darwin notifications cross the app sandbox (unlike
/// `DistributedNotificationCenter`). Both routes end at
/// ``didChangeNotification``, giving stores one observation path.
public enum DatabaseChangeSignal {
  /// The Darwin notification name posted across processes.
  public static let darwinName = "com.lorvex.localDatabaseChanged"

  /// An in-process `Notification` re-posted whenever a Darwin change signal
  /// arrives, so app code observes it with the ordinary `NotificationCenter` API
  /// rather than a C callback.
  public static let didChangeNotification = Notification.Name(
    "com.lorvex.localDatabaseChanged.inProcess")

  /// Set `true` only in a writing process that must notify *other processes*
  /// (the MCP host). The app leaves this false: its own window stores share a
  /// process and use ``postsInProcessOnWrite`` instead.
  ///
  /// `nonisolated(unsafe)`: set once at process startup before any write.
  public nonisolated(unsafe) static var broadcastsOnWrite = false

  /// Set `true` in an app process so every committed core write invalidates all
  /// independent stores in that process. This covers macOS windows plus
  /// in-process App Intents, notification actions, and CarPlay/mobile writers.
  /// Successful CloudKit apply reports use the explicit origin-tagged method
  /// below, without starting another sync stack per window.
  ///
  /// Delivery is throttled: a write-heavy action can commit several core
  /// transactions, but observers receive one notification per short burst rather
  /// than one full reload per transaction.
  ///
  /// `nonisolated(unsafe)`: set once at process startup before any write.
  public nonisolated(unsafe) static var postsInProcessOnWrite = false

  /// Configure the process that owns the app UI to receive both its own core
  /// writes and Darwin notifications from sibling processes. Call exactly once
  /// from each app entry point before the first product mutation.
  public static func configureApplicationProcess() {
    postsInProcessOnWrite = true
    startObserving()
  }

  /// Serializes the one-time observer registration. Multiple in-process entry
  /// points call ``startObserving()`` (app bootstrap, the CarPlay scene, the
  /// mobile CloudSync path), possibly from different executors.
  private static let isObserving = Mutex(false)

  /// Guards the short in-process invalidation throttle. A main-queue post keeps
  /// UI observers on their natural executor; the coalescer makes calls from
  /// core writer queues race-free.
  private static let inProcessPostCoalescer = InProcessDatabaseChangeCoalescer()

  /// Deliver the configured change signal(s) after a committed write.
  public static func broadcastIfEnabled() {
    if postsInProcessOnWrite {
      enqueueInProcessPost()
    }
    if broadcastsOnWrite {
      broadcastCommittedChange()
    }
  }

  /// Post one unconditional cross-process invalidation for a committed write.
  ///
  /// Use this at an extension boundary that owns one complete operation (for
  /// example, an interactive widget intent) instead of enabling per-core-write
  /// broadcasting for the whole process. The Darwin center coalesces duplicate
  /// posts and the receiving app relays them through ``didChangeNotification``.
  public static func broadcastCommittedChange() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(darwinName as CFString), nil, nil, true)
  }

  /// Post one committed-change invalidation inside the current process.
  ///
  /// `origin` lets a store that already reconciled the commit ignore its own
  /// notification while independent stores still reload. CloudKit's macOS
  /// coordinator uses this after its domain-selective reload: detached windows
  /// converge, but the originating main store does not start a redundant full
  /// refresh/sync cycle. Ordinary core-write and Darwin-relay notifications have
  /// no origin and therefore invalidate every observing store.
  public static func broadcastCommittedChangeInProcess(origin: AnyObject? = nil) {
    NotificationCenter.default.post(
      name: didChangeNotification, object: origin)
  }

  /// Coalesce a burst of committed writes into one in-process invalidation.
  /// Fifty milliseconds is long enough to absorb the multiple transactions a
  /// single UI action can perform while remaining imperceptible to an open peer
  /// window. A sustained writer is therefore bounded to at most 20 invalidations
  /// per second, and each store's reload single-flight coalesces further.
  static func enqueueInProcessPost() {
    inProcessPostCoalescer.enqueue(
      schedule: { callback in
        DispatchQueue.main.asyncAfter(
          deadline: .now() + .milliseconds(50), execute: callback)
      },
      deliver: {
        broadcastCommittedChangeInProcess()
      })
  }

  /// Relay Darwin change signals to ``didChangeNotification`` on the default
  /// `NotificationCenter`. Idempotent: the underlying `CFNotificationCenter`
  /// observer is registered exactly once per process, so repeated calls from
  /// independent in-process entry points (app bootstrap, the CarPlay scene, the
  /// mobile CloudSync path) never stack observers — a stacked observer would
  /// re-post ``didChangeNotification`` once per registration and multiply the
  /// refresh work every signal triggers.
  public static func startObserving() {
    registerObserverIfNeeded {
      CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        nil,
        { _, _, _, _, _ in
          NotificationCenter.default.post(
            name: DatabaseChangeSignal.didChangeNotification, object: nil)
        },
        darwinName as CFString,
        nil,
        .deliverImmediately)
    }
  }

  /// Runs `register` only on the first call per process; later calls are no-ops.
  /// The seam is `internal` (not the `CFNotificationCenter` closure directly) so
  /// a test can assert the register-once contract without installing a real
  /// process-wide Darwin observer.
  static func registerObserverIfNeeded(_ register: () -> Void) {
    isObserving.withLock { observing in
      guard !observing else { return }
      observing = true
      register()
    }
  }

  /// Test-only: clears the register-once guard so a subsequent
  /// ``registerObserverIfNeeded(_:)`` runs its body again. Does not remove any
  /// already-installed `CFNotificationCenter` observer. Product code never calls
  /// this.
  static func resetObservingForTesting() {
    isObserving.withLock { $0 = false }
  }
}
