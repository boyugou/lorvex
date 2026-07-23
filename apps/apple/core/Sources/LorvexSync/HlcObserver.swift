import Foundation
import LorvexDomain

/// Sync-module surface for the process-wide HLC observer.
///
/// The observer slot itself lives in `LorvexDomain.HlcObserver` because
/// lower-layer lifecycle ops in `LorvexStore` also mint merge HLCs and
/// `LorvexStore` cannot depend on `LorvexSync`. This namespace forwards to it
/// so sync apply call sites read against the sync module.
public enum SyncHlcObserver {
  public typealias LocalEventObserver = HlcObserver.LocalEventObserver
  public typealias SetObserverOutcome = HlcObserver.SetObserverOutcome

  /// Install the process-wide observer (last install wins).
  @discardableResult
  public static func setLocalEventObserver(
    _ observer: @escaping LocalEventObserver
  ) -> SetObserverOutcome {
    HlcObserver.setLocalEventObserver(observer)
  }

  /// Feed a locally-minted HLC back into the installed observer.
  public static func observeLocalEvent(_ hlc: Hlc) {
    HlcObserver.observeLocalEvent(hlc)
  }

  public static func withTransactionObserver<R>(
    _ observer: @escaping LocalEventObserver,
    _ body: () throws -> R
  ) rethrows -> R {
    try HlcObserver.withTransactionObserver(observer, body)
  }

  /// Run `body` with `observer` temporarily installed in the test slot.
  public static func withTemporaryObserver<R>(
    _ observer: @escaping LocalEventObserver,
    _ body: () throws -> R
  ) rethrows -> R {
    try HlcObserver.withTemporaryObserver(observer, body)
  }
}
