import Foundation
import LorvexCore

/// The WatchConnectivity property-list payload ceiling.
///
/// WatchConnectivity rejects a dictionary that grows past ~65 KB. The publisher
/// checks an encoded replica against this ceiling before updating application
/// context. Platform-neutral (not gated on `os(iOS)`) so the threshold logic is
/// unit-testable on the host.
enum WatchSnapshotTransferLimit {
  /// Approximate WatchConnectivity dictionary cap in bytes (~65 KB).
  static let maxApplicationContextPayloadBytes = 65_536

  /// Whether `byteCount` fits within the transfer ceiling.
  static func isWithinLimit(_ byteCount: Int) -> Bool {
    byteCount <= maxApplicationContextPayloadBytes
  }

  /// Measures the property-list dictionary actually handed to
  /// `updateApplicationContext`, including its key and container overhead.
  static func serializedByteCount(of applicationContext: [String: Data]) throws -> Int {
    try PropertyListSerialization.data(
      fromPropertyList: applicationContext, format: .binary, options: 0
    ).count
  }
}

/// Pure transfer gate shared by the iOS publisher and host-side tests. A
/// background transfer is legal only for an activated session with an installed
/// companion, and an over-cap replica must be dropped rather than knowingly
/// handed to WatchConnectivity.
enum WatchSnapshotTransferGate {
  static func shouldTransfer(
    byteCount: Int,
    sessionIsActivated: Bool,
    isPaired: Bool,
    isWatchAppInstalled: Bool
  ) -> Bool {
    sessionIsActivated && isPaired && isWatchAppInstalled
      && WatchSnapshotTransferLimit.isWithinLimit(byteCount)
  }
}

// Gated on `os(iOS)` (not `canImport(WatchConnectivity)`) because
// visionOS imports WatchConnectivity too, yet has no paired watch — the
// publisher only makes sense on the iPhone.
#if os(iOS)
  import LorvexWidgetKitSupport
  import OSLog
  import WatchConnectivity

  /// Phone-side `WatchReplicaPublishing` that pushes a workspace-fenced replica
  /// envelope to the paired watch as `WCSession`'s latest application context.
  ///
  /// The watch reads its own App Group container (it cannot reach the phone's),
  /// so any UI/data change the phone makes after applying a watch-originated
  /// mutation has to cross the WC boundary to reach the watch complication
  /// and watch app. The receiver on the watch side decodes and writes to the
  /// watch's App Group file (`watch_replica_v1.json`), then reloads its
  /// complication timeline.
  ///
  /// A replica is state, not an event: `updateApplicationContext` replaces the
  /// previous pending dictionary, so a delayed old-workspace replica cannot
  /// arrive after and overwrite a newer workspace fence. Per-update size limit
  /// is ~65 KB; the upstream Watch projection enforces a smaller raw-data bound
  /// before envelope base64 expansion and dictionary overhead.
  /// Note: this publisher does not own the `WCSession` delegate. Activation +
  /// delegate registration are the job of `PhoneWatchConnectivityReceiver`
  /// (which handles inbound watch→phone mutations); the publisher only sends.
  public final class WCSessionWatchSnapshotPublisher: WatchReplicaPublishing,
    @unchecked Sendable
  {
    /// Reserved key carrying the strict replica-envelope wire data.
    /// Aliases the shared constant so the receiver and the publisher can't
    /// drift apart.
    public static let userInfoKey = LorvexWatchConnectivityKey.replicaEnvelopeV1

    private static let log = Logger(
      subsystem: "com.lorvex.mobile",
      category: "watch-snapshot")

    private let session: WCSession

    public init(session: WCSession = .default) {
      self.session = session
    }

    @MainActor
    public func publish(replicaEnvelope: LorvexWatchReplicaEnvelope) async {
      guard WCSession.isSupported() else { return }
      let data: Data
      do {
        data = try replicaEnvelope.wireData()
      } catch {
        Self.log.error(
          "Watch replica encode failed; complication left stale: \(String(describing: error), privacy: .public)"
        )
        return
      }
      let applicationContext = [Self.userInfoKey: data]
      let payloadByteCount: Int
      do {
        payloadByteCount = try WatchSnapshotTransferLimit.serializedByteCount(
          of: applicationContext)
      } catch {
        Self.log.error(
          "Watch replica application-context sizing failed; complication left stale: \(String(describing: error), privacy: .public)"
        )
        return
      }
      let activationState = session.activationState
      let isPaired = session.isPaired
      let isWatchAppInstalled = session.isWatchAppInstalled
      guard WatchSnapshotTransferGate.shouldTransfer(
        byteCount: payloadByteCount,
        sessionIsActivated: activationState == .activated,
        isPaired: isPaired,
        isWatchAppInstalled: isWatchAppInstalled
      ) else {
        Self.log.warning(
          "Watch replica not transferred (context bytes \(payloadByteCount, privacy: .public), activation \(activationState.rawValue, privacy: .public), paired \(isPaired, privacy: .public), installed \(isWatchAppInstalled, privacy: .public))."
        )
        return
      }
      do {
        try session.updateApplicationContext(applicationContext)
      } catch {
        Self.log.error(
          "Watch replica application-context update failed; complication left stale: \(String(describing: error), privacy: .public)"
        )
      }
    }
  }
#endif
