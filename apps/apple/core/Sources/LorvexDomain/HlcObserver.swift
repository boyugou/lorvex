import Foundation
import Synchronization

/// Process-wide hook for the sync apply pipeline (and lower-layer lifecycle
/// ops) to feed locally-minted HLCs back into the caller's `HlcState`.
///
/// Most HLCs that affect this device's clock are either generated locally
/// (`HlcState.generate`) or arrive on a peer envelope
/// (`HlcState.updateOnReceive`). A few merge / clear paths mint a brand-new
/// HLC directly (the merge version guaranteed greater than every participant)
/// without going through `generate()`. The caller's `HlcState` therefore has
/// no record of having emitted that HLC, and a later local edit can produce a
/// version that lex-orders BELOW the freshly-stamped child rows — peers then
/// reject the post-merge edit as LWW-stale. Each merge / clear site calls
/// ``observeLocalEvent(_:)`` after constructing the new HLC so the installed
/// observer can advance the caller's clock past it.
///
/// Lives in `LorvexDomain` (not `LorvexSync`) because lower-layer lifecycle
/// ops in `LorvexStore` also mint fresh HLCs and `LorvexStore` cannot depend
/// on `LorvexSync`. `LorvexSync.HlcObserver` re-exports this surface so sync
/// call sites read against the sync module.
///
/// Concurrency: the production observer is held behind a lock-guarded
/// singleton (last-install-wins, read synchronously inside the apply
/// transaction). The test observer is a `@TaskLocal` so a
/// ``withTemporaryObserver(_:_:)`` body installs its own observer with
/// panic-safe restore on scope exit, and concurrent tasks never see each
/// other's slot — the structured-concurrency analog of a thread-local
/// test slot. ``observeLocalEvent(_:)`` consults the task-local test slot
/// first, then the production singleton.
public enum HlcObserver {
  /// Closure shape every surface installs. Must be cheap and never throw —
  /// it runs inside the apply transaction.
  public typealias LocalEventObserver = @Sendable (Hlc) -> Void

  /// Outcome of installing the process-wide observer. Install is
  /// last-install-wins: a later install always replaces the current observer.
  /// ``installed`` reports the slot was empty; ``alreadyInstalled`` reports it
  /// replaced an existing observer (which still takes effect), so callers can
  /// still detect double-init without losing the advance.
  public enum SetObserverOutcome: Sendable, Equatable {
    case installed
    case alreadyInstalled
  }

  /// Lock-guarded last-install-wins production observer slot.
  private final class ProductionSlot: Sendable {
    private let observer = Mutex<LocalEventObserver?>(nil)

    func set(_ newObserver: @escaping LocalEventObserver) -> SetObserverOutcome {
      observer.withLock { current in
        let hadObserver = current != nil
        current = newObserver
        return hadObserver ? .alreadyInstalled : .installed
      }
    }

    func get() -> LocalEventObserver? {
      observer.withLock { $0 }
    }
  }

  private static let production = ProductionSlot()

  /// Per-task test observer slot. `@TaskLocal` so a ``withTemporaryObserver``
  /// body sees its own observer and the value is restored when the body
  /// returns, even if it throws.
  @TaskLocal private static var testObserver: LocalEventObserver?
  /// Transaction-scoped production sink. Unlike the process-global compatibility
  /// slot, this is bound to the exact database transaction whose high-water will
  /// commit, so two services/databases in one process can never steal events.
  @TaskLocal private static var transactionObserver: LocalEventObserver?

  /// Install the process-wide observer, replacing any prior one
  /// (last-install-wins): the most recently installed observer is the one
  /// ``observeLocalEvent(_:)`` routes to. Advancing a stale/dead clock is
  /// harmless; failing to advance the live one is the bug an in-process DB switch
  /// would otherwise cause (the new service's live clock never sees merge-minted
  /// HLCs), so the newest clock always wins. Returns
  /// ``SetObserverOutcome/installed`` on the first install and
  /// ``SetObserverOutcome/alreadyInstalled`` when it replaced an existing one, so
  /// double-init stays observable. The observer runs inside the apply
  /// transaction, so it must be cheap and never throw.
  @discardableResult
  public static func setLocalEventObserver(
    _ observer: @escaping LocalEventObserver
  ) -> SetObserverOutcome {
    production.set(observer)
  }

  /// Notify the registered observer that a *local* HLC was just minted outside
  /// the normal `HlcState.generate` path. Routes to the task-local test
  /// observer first when one is installed, otherwise to the production
  /// singleton. No-op when neither is registered.
  public static func observeLocalEvent(_ hlc: Hlc) {
    if let transaction = transactionObserver {
      transaction(hlc)
      // A test observer is instrumentation, not the production owner; let it
      // observe the same event without replacing the transaction reservation.
      testObserver?(hlc)
      return
    }
    if let test = testObserver {
      test(hlc)
      return
    }
    if let prod = production.get() {
      prod(hlc)
    }
  }

  /// Bind deterministic merge events to the exact active write transaction.
  /// Nested test instrumentation remains observable through `testObserver`.
  public static func withTransactionObserver<R>(
    _ observer: @escaping LocalEventObserver,
    _ body: () throws -> R
  ) rethrows -> R {
    try $transactionObserver.withValue(observer) { try body() }
  }

  /// Run `body` with `observer` temporarily installed in the task-local test
  /// slot, restoring the previous value on scope exit. ``observeLocalEvent(_:)``
  /// consults this slot before the production observer, so callers can override
  /// whatever production observer the binary installed.
  public static func withTemporaryObserver<R>(
    _ observer: @escaping LocalEventObserver,
    _ body: () throws -> R
  ) rethrows -> R {
    try $testObserver.withValue(observer) {
      try body()
    }
  }
}
