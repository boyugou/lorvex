import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import OSLog

#if canImport(WatchConnectivity)
  @preconcurrency import WatchConnectivity

  private final class WatchConnectivityCommandChannel: LorvexWatchCommandChannel,
    @unchecked Sendable
  {
    private let session: WCSession

    init(session: WCSession) {
      self.session = session
    }

    func deliveryState() async -> LorvexWatchDeliveryChannelState {
      guard WCSession.isSupported(), session.activationState == .activated else {
        return .inactive
      }
      return session.isReachable ? .reachable : .background
    }

    func sendDirect(_ commandData: Data) async throws -> Data {
      guard session.activationState == .activated, session.isReachable else {
        throw WatchForwardingError.unavailable
      }
      return try await withCheckedThrowingContinuation { continuation in
        session.sendMessageData(
          commandData,
          replyHandler: { continuation.resume(returning: $0) },
          errorHandler: { continuation.resume(throwing: $0) })
      }
    }

    func hasOutstandingBackgroundCommand(_ commandData: Data) async -> Bool {
      session.outstandingUserInfoTransfers.contains { transfer in
        guard
          let outstanding = transfer.userInfo[LorvexWatchConnectivityKey.commandEnvelopeV1]
            as? Data
        else { return false }
        return outstanding == commandData
      }
    }

    func enqueueBackground(_ commandData: Data) async throws {
      // `transferUserInfo` is not a pre-activation queue. Calling it while
      // inactive can throw an Objective-C exception on some OS releases, so the
      // activated state is a hard gate rather than a silent success path.
      guard WCSession.isSupported(), session.activationState == .activated else {
        throw WatchForwardingError.unavailable
      }
      session.transferUserInfo([
        LorvexWatchConnectivityKey.commandEnvelopeV1: commandData
      ])
    }
  }

  /// Tracks delegate-launched async work so SwiftUI's watch-connectivity
  /// background task can await actual content handling. It deliberately does not
  /// consult `WCSession.hasContentPending`, which describes inbound delivery and
  /// cannot prove the outgoing journal drained.
  private final class WatchConnectivityInboundWorkTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func begin() {
      lock.withLock { activeCount += 1 }
    }

    func end() {
      let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
        activeCount -= 1
        guard activeCount == 0 else { return [] }
        let current = waiters
        waiters = []
        return current
      }
      for continuation in continuations { continuation.resume() }
    }

    func waitUntilIdle() async {
      await withCheckedContinuation { continuation in
        let resumeImmediately = lock.withLock {
          if activeCount == 0 { return true }
          waiters.append(continuation)
          return false
        }
        if resumeImmediately { continuation.resume() }
      }
    }
  }

  /// Durable WatchConnectivity forwarder. `forward` means "persisted in the
  /// local command journal", never "already applied on the phone".
  public final class WatchConnectivityMutationForwarder: NSObject,
    LorvexWatchDeliveryManaging, WCSessionDelegate, @unchecked Sendable
  {
    private static let log = Logger(
      subsystem: "com.lorvex.watch", category: "connectivity")
    private static let journalFileName = "watch_commands_v1.json"

    private let session: WCSession
    private let snapshotReceiver: LorvexWatchSnapshotReceiver?
    private let delivery: LorvexWatchCommandDelivery?
    private let startupFailure: (any Error & Sendable)?
    private let inboundWork = WatchConnectivityInboundWorkTracker()
    private let replicaIngressLock = NSLock()
    private var nextReplicaIngressSequence: UInt64 = 1

    public init(
      session: WCSession = .default,
      snapshotReceiver: LorvexWatchSnapshotReceiver? = nil,
      replicaStore: LorvexWatchReplicaStore? = nil,
      appGroupID: String = LorvexProductMetadata.appGroupIdentifier,
      fileManager: FileManager = .default
    ) {
      self.session = session
      self.snapshotReceiver = snapshotReceiver

      let sharedReplicaStore =
        replicaStore
        ?? LorvexWatchReplicaStore(
          appGroupID: appGroupID,
          fileManagerBox: LorvexWatchFileManagerBox(fileManager))
      do {
        guard
          let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
          )
        else {
          throw LorvexWatchReplicaStoreError.appGroupUnavailable
        }
        let journalURL =
          containerURL
          .appendingPathComponent("Lorvex", isDirectory: true)
          .appendingPathComponent(Self.journalFileName, isDirectory: false)
        let journal = try LorvexWatchCommandJournal(fileURL: journalURL)
        let channel = WatchConnectivityCommandChannel(session: session)
        delivery = LorvexWatchCommandDelivery(
          journal: journal,
          replicaStore: sharedReplicaStore,
          channel: channel)
        startupFailure = nil
      } catch {
        delivery = nil
        startupFailure = error
      }

      super.init()
      guard WCSession.isSupported() else { return }
      session.delegate = self
      session.activate()
    }

    public func forward(_ mutation: LorvexWatchMutation) async throws {
      guard WCSession.isSupported() else { throw WatchForwardingError.unavailable }
      guard let delivery else {
        throw startupFailure ?? WatchForwardingError.unavailable
      }
      try await delivery.enqueue(mutation)
      Task {
        await Task.yield()
        await delivery.drain()
      }
    }

    public func setDeliveryStatusHandler(
      _ handler: @escaping @Sendable (LorvexWatchDeliveryStatus) -> Void
    ) {
      guard let delivery else {
        handler(
          LorvexWatchDeliveryStatus(
            journalUnavailable: startupFailure != nil || !WCSession.isSupported()))
        return
      }
      Task { await delivery.setStatusHandler(handler) }
    }

    public func dismissRejectedCommand(id: String) async {
      await delivery?.dismissRejectedCommand(id: id)
    }

    public func drain() async {
      await delivery?.drain()
    }

    public func handleBackgroundWake() async {
      // Give a just-delivered delegate callback one scheduling turn to register
      // its synchronous tracker token, then await both inbound processing and
      // the concrete journal drain.
      await Task.yield()
      await inboundWork.waitUntilIdle()
      await delivery?.drainAndWait()
    }

    // MARK: WCSessionDelegate

    public func session(
      _ session: WCSession,
      activationDidCompleteWith activationState: WCSessionActivationState,
      error: Error?
    ) {
      if let error {
        Self.log.error(
          "WCSession activation failed (state \(activationState.rawValue, privacy: .public)): \(error.localizedDescription, privacy: .public)"
        )
        return
      }
      Self.log.info(
        "WCSession activated (state \(activationState.rawValue, privacy: .public), reachable \(session.isReachable, privacy: .public))"
      )
      let replicaData =
        session.receivedApplicationContext[
          LorvexWatchConnectivityKey.replicaEnvelopeV1] as? Data
      if let replicaData {
        receiveReplicaData(replicaData)
      } else {
        Task { await delivery?.drain() }
      }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
      Task { await delivery?.drain() }
    }

    public func session(
      _ session: WCSession,
      didReceiveMessageData messageData: Data
    ) {
      inboundWork.begin()
      Task {
        await delivery?.receiveAcknowledgementData(messageData)
        inboundWork.end()
      }
    }

    public func session(
      _ session: WCSession,
      didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
      // Extract Sendable Data before crossing out of the nonisolated property-list
      // callback. Foreign dictionaries are ignored without touching the journal.
      let ackData = userInfo[LorvexWatchConnectivityKey.commandAckV1] as? Data
      guard let ackData else { return }

      inboundWork.begin()
      Task {
        await delivery?.receiveAcknowledgementData(ackData)
        inboundWork.end()
      }
    }

    /// Latest-state replica channel. `updateApplicationContext` coalesces stale
    /// values, preventing a delayed old-workspace snapshot from reverting the
    /// workspace fence after a reset.
    public func session(
      _ session: WCSession,
      didReceiveApplicationContext applicationContext: [String: Any]
    ) {
      guard
        let replicaData = applicationContext[
          LorvexWatchConnectivityKey.replicaEnvelopeV1] as? Data
      else { return }
      receiveReplicaData(replicaData)
    }

    public func session(
      _ session: WCSession,
      didFinish userInfoTransfer: WCSessionUserInfoTransfer,
      error: (any Error)?
    ) {
      guard
        let commandData = userInfoTransfer.userInfo[
          LorvexWatchConnectivityKey.commandEnvelopeV1] as? Data
      else { return }
      inboundWork.begin()
      Task {
        await delivery?.backgroundTransferFinished(commandData: commandData, error: error)
        inboundWork.end()
      }
    }

    #if os(iOS)
      public func sessionDidBecomeInactive(_ session: WCSession) {}

      public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
      }
    #endif

    private func receiveReplicaData(_ replicaData: Data) {
      // Reserve order synchronously in the delegate callback. The unstructured
      // Tasks below may begin in either order, so the replica-store actor uses
      // this token to reject a late task for an older application context.
      let ingressSequence = replicaIngressLock.withLock { () -> UInt64 in
        let reserved = nextReplicaIngressSequence
        if nextReplicaIngressSequence < UInt64.max {
          nextReplicaIngressSequence += 1
        }
        return reserved
      }
      inboundWork.begin()
      Task {
        _ = await snapshotReceiver?.handle(
          applicationContext: [
            LorvexWatchConnectivityKey.replicaEnvelopeV1: replicaData
          ], ingressSequence: ingressSequence)
        await delivery?.drain()
        inboundWork.end()
      }
    }
  }
#endif
