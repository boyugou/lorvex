import Foundation
import LorvexCore
import OSLog

/// A terminal Watch outcome must reconcile optimistic Watch UI against the
/// phone's authoritative replica. A retryable outcome deliberately keeps the
/// optimistic state and durable command pending until a later delivery.
enum PhoneWatchReplicaRefreshPolicy {
  static func shouldRefresh(after outcome: LorvexWatchCommandAck.Outcome) -> Bool {
    outcome != .retryable
  }
}

#if canImport(WatchConnectivity)
  @preconcurrency import WatchConnectivity

  /// Launch-lifetime iPhone endpoint for the strict Watch command protocol.
  ///
  /// The database transaction owned by `LorvexWatchCommandServicing` is the only
  /// application-ACK boundary. UI reload, replica publication, reminder work,
  /// and complication reload all start after the ACK has been returned or queued
  /// and can never rewrite an applied outcome into an error.
  @MainActor
  public final class PhoneWatchConnectivityReceiver: NSObject {
    private nonisolated let commandService: any LorvexWatchCommandServicing
    private let store: MobileStore
    private let complicationReloader: any WatchComplicationReloading
    private let session: WCSession

    nonisolated private static let log = Logger(
      subsystem: "com.lorvex.mobile", category: "watch-connectivity")

    public convenience init?(
      store: MobileStore,
      complicationReloader: any WatchComplicationReloading = WidgetCenterComplicationReloader(),
      session: WCSession = .default
    ) {
      guard let commandService = store.core as? any LorvexWatchCommandServicing else {
        Self.log.fault(
          "Phone Watch receiver not created because the mobile core lacks LorvexWatchCommandServicing"
        )
        return nil
      }
      self.init(
        store: store,
        commandService: commandService,
        complicationReloader: complicationReloader,
        session: session)
    }

    /// Explicit narrow-contract initializer used by tests and alternate hosts.
    /// The public app initializer above fails closed when its umbrella core does
    /// not also provide this capability.
    init(
      store: MobileStore,
      commandService: any LorvexWatchCommandServicing,
      complicationReloader: any WatchComplicationReloading,
      session: WCSession = .default
    ) {
      self.commandService = commandService
      self.store = store
      self.complicationReloader = complicationReloader
      self.session = session
      super.init()
    }

    /// Register the delegate and activate as early as the app lifetime permits.
    /// `LorvexMobileApp` calls this from its initializer rather than a view task,
    /// so a cold WatchConnectivity wake does not depend on SwiftUI rendering.
    public func activate() {
      guard WCSession.isSupported() else { return }
      session.delegate = self
      session.activate()
    }

    /// Strictly decode and apply one trusted command. A malformed, unsupported,
    /// or checksum-invalid payload yields no ACK: without a fully validated
    /// identity the phone must not fabricate a rejection that could cause the
    /// Watch to delete its durable journal entry.
    nonisolated func applyCommandData(_ data: Data) async -> LorvexWatchCommandAck? {
      let command: LorvexWatchCommand
      do {
        command = try LorvexWatchCommand.decodeWireData(data)
      } catch {
        Self.log.error(
          "Rejected untrusted Watch command data before apply: \(String(describing: error), privacy: .public)"
        )
        return nil
      }
      return await commandService.applyWatchCommand(command)
    }

    /// Encode a validated Core ACK. Failure is observable and leaves the Watch
    /// command pending; an empty or partial ACK is never sent.
    nonisolated private static func wireData(
      for ack: LorvexWatchCommandAck
    ) -> Data? {
      do {
        return try ack.wireData()
      } catch {
        log.error(
          "Watch command ACK encoding failed; Watch will retain command: \(String(describing: error), privacy: .public)"
        )
        return nil
      }
    }

    /// Queue an application ACK for a background command. Session activation is
    /// a hard precondition for every transfer API; if it changed during apply, the
    /// Watch retains and redelivers the command, and the SQLite receipt replays
    /// the same ACK on that retry.
    nonisolated private static func queueBackgroundAck(
      _ ackData: Data,
      on session: WCSession
    ) {
      guard session.activationState == .activated else {
        log.notice("Watch ACK not queued because WCSession is not activated")
        return
      }
      let isAlreadyOutstanding = session.outstandingUserInfoTransfers.contains { transfer in
        transfer.userInfo[LorvexWatchConnectivityKey.commandAckV1] as? Data == ackData
      }
      guard !isAlreadyOutstanding else {
        log.debug("Identical Watch ACK is already queued")
        return
      }
      session.transferUserInfo([
        LorvexWatchConnectivityKey.commandAckV1: ackData
      ])
    }

    /// Start best-effort derived-surface work after the application ACK boundary.
    /// `MobileStore.refresh()` coalesces concurrent triggers and republishes the
    /// workspace-fenced replica through its ordinary widget snapshot publisher.
    private func scheduleReplicaBaselineRefresh() {
      let store = store
      let complicationReloader = complicationReloader
      Task { @MainActor in
        _ = await store.refresh()
        complicationReloader.reloadTimelines()
      }
    }

    private func schedulePostCommitFanOut(for ack: LorvexWatchCommandAck) {
      guard PhoneWatchReplicaRefreshPolicy.shouldRefresh(after: ack.outcome) else { return }
      scheduleReplicaBaselineRefresh()
    }
  }

  // MARK: - WCSessionDelegate

  extension PhoneWatchConnectivityReceiver: WCSessionDelegate {
    nonisolated public func session(
      _ session: WCSession,
      activationDidCompleteWith activationState: WCSessionActivationState,
      error: Error?
    ) {
      if let error {
        Self.log.error(
          "WCSession activation failed (state \(activationState.rawValue, privacy: .public)): \(error.localizedDescription, privacy: .public)"
        )
      } else {
        Self.log.info(
          "WCSession activated (state \(activationState.rawValue, privacy: .public), reachable \(session.isReachable, privacy: .public))"
        )
      }
      guard activationState == .activated else { return }
      // A regular startup refresh may race ahead of session activation, where
      // the transfer publisher correctly drops it. Every successful activation
      // (including watch-switch reactivation) therefore creates a fresh
      // authoritative replica baseline.
      Task { @MainActor [weak self] in
        self?.scheduleReplicaBaselineRefresh()
      }
    }

    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
      Self.log.info("WCSession deactivated; reactivating for the current watch")
      session.activate()
    }

    /// Foreground request/reply path. The reply is the strict Core ACK, not a
    /// transport acknowledgement and not mutable `MobileStore.errorMessage`.
    nonisolated public func session(
      _ session: WCSession,
      didReceiveMessageData messageData: Data,
      replyHandler: @escaping (Data) -> Void
    ) {
      nonisolated(unsafe) let reply = replyHandler
      Task {
        guard let ack = await self.applyCommandData(messageData),
          let ackData = Self.wireData(for: ack)
        else {
          // Complete the system reply promptly, but deliberately send no valid
          // application ACK. The Watch's strict decoder retains the command.
          reply(Data())
          return
        }
        reply(ackData)
        await self.schedulePostCommitFanOut(for: ack)
      }
    }

    /// No-reply message path. Apply durably, then route the same ACK through the
    /// background channel so every accepted command has one protocol outcome.
    nonisolated public func session(
      _ session: WCSession,
      didReceiveMessageData messageData: Data
    ) {
      Task {
        guard let ack = await self.applyCommandData(messageData),
          let ackData = Self.wireData(for: ack)
        else { return }
        Self.queueBackgroundAck(ackData, on: session)
        await self.schedulePostCommitFanOut(for: ack)
      }
    }

    /// Background command path. Extract only strict `Data` from the non-Sendable
    /// property-list dictionary before crossing a concurrency boundary.
    nonisolated public func session(
      _ session: WCSession,
      didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
      guard
        let commandData = userInfo[LorvexWatchConnectivityKey.commandEnvelopeV1] as? Data
      else { return }
      Task {
        guard let ack = await self.applyCommandData(commandData),
          let ackData = Self.wireData(for: ack)
        else { return }
        Self.queueBackgroundAck(ackData, on: session)
        await self.schedulePostCommitFanOut(for: ack)
      }
    }
  }
#endif
