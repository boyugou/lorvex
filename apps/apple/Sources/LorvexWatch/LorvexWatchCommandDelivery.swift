import Foundation
import LorvexCore

protocol LorvexWatchCommandChannel: Sendable {
  func deliveryState() async -> LorvexWatchDeliveryChannelState
  func sendDirect(_ commandData: Data) async throws -> Data
  func hasOutstandingBackgroundCommand(_ commandData: Data) async -> Bool
  func enqueueBackground(_ commandData: Data) async throws
}

/// Serial FIFO delivery engine shared by the concrete WCSession forwarder and
/// host-side fake-channel tests.
actor LorvexWatchCommandDelivery {
  typealias StatusHandler = @Sendable (LorvexWatchDeliveryStatus) -> Void

  private let journal: LorvexWatchCommandJournal
  private let replicaStore: LorvexWatchReplicaStore
  private let channel: any LorvexWatchCommandChannel
  private let retryPolicy: LorvexWatchDeliveryRetryPolicy
  private let now: @Sendable () -> Date
  private let schedulesRetries: Bool

  private var statusHandler: StatusHandler = { _ in }
  private var isDraining = false
  private var drainRequested = false
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []
  private var scheduledRetry: Task<Void, Never>?

  init(
    journal: LorvexWatchCommandJournal,
    replicaStore: LorvexWatchReplicaStore,
    channel: any LorvexWatchCommandChannel,
    retryPolicy: LorvexWatchDeliveryRetryPolicy = LorvexWatchDeliveryRetryPolicy(),
    now: @escaping @Sendable () -> Date = Date.init,
    schedulesRetries: Bool = true
  ) {
    self.journal = journal
    self.replicaStore = replicaStore
    self.channel = channel
    self.retryPolicy = retryPolicy
    self.now = now
    self.schedulesRetries = schedulesRetries
  }

  deinit {
    scheduledRetry?.cancel()
  }

  func setStatusHandler(_ handler: @escaping StatusHandler) async {
    statusHandler = handler
    await publishStatus()
  }

  /// Returns only after the command has been atomically persisted. Transport is
  /// deliberately a separate trigger so the store can apply optimistic UI at
  /// this exact durability boundary rather than waiting for the phone.
  @discardableResult
  func enqueue(_ mutation: LorvexWatchMutation) async throws -> LorvexWatchJournalCommand {
    let workspaceInstanceID = try await replicaStore.currentWorkspaceInstanceID()
    let command = try await journal.enqueue(
      mutation: mutation,
      workspaceInstanceID: workspaceInstanceID,
      createdAt: LorvexDateFormatters.iso8601Fractional.string(from: now()))
    await publishStatus()
    return command
  }

  func dismissRejectedCommand(id: String) async {
    do {
      _ = try await journal.dismissRejected(commandID: id)
      await publishStatus()
      await drain()
    } catch {
      // A failed journal write must leave the rejected row visible. The next
      // status callback therefore intentionally remains unchanged.
    }
  }

  /// Drains direct commands to terminal ACKs in sequence, or queues exactly one
  /// background command and stops until its application ACK arrives.
  func drain() async {
    guard !isDraining else {
      drainRequested = true
      return
    }
    isDraining = true
    defer {
      isDraining = false
      let waiters = drainWaiters
      drainWaiters = []
      for waiter in waiters { waiter.resume() }
    }

    repeat {
      drainRequested = false
      await drainPass()
    } while drainRequested
  }

  /// Used by a SwiftUI watch-connectivity background task. If a delegate-triggered
  /// drain is already active, wait for that exact work to quiesce instead of
  /// treating `WCSession.hasContentPending` as an outgoing delivery guarantee.
  func drainAndWait() async {
    if isDraining {
      drainRequested = true
      await withCheckedContinuation { drainWaiters.append($0) }
      return
    }
    await drain()
  }

  func receiveAcknowledgementData(_ data: Data) async {
    do {
      let acknowledgement = try LorvexWatchCommandAck.decodeWireData(data)
      let entry = await journal.nextDeliverable(at: .distantFuture)
      let attempt = entry?.attemptCount ?? 1
      let retryAt = now().addingTimeInterval(retryPolicy.retryDelay(afterAttempt: attempt))
      let resolution = try await journal.applyAcknowledgement(
        acknowledgement,
        retryAt: retryAt)
      await publishStatus()
      switch resolution {
      case .applied, .rejected:
        await drain()
      case .retryable:
        await scheduleRetryIfNeeded()
      case .duplicate:
        break
      }
    } catch {
      // Strict decode or identity failure never consumes the FIFO head. A later
      // retry or duplicate valid ACK resolves it.
    }
  }

  /// A WatchConnectivity transfer completion is only a transport signal. It
  /// adjusts retry timing but never removes a journal entry.
  func backgroundTransferFinished(commandData: Data, error: Error?) async {
    do {
      let command = try LorvexWatchCommand.decodeWireData(commandData)
      let retryAt: Date
      if error != nil {
        let head = await journal.nextDeliverable(at: .distantFuture)
        let attempt = head?.attemptCount ?? 1
        retryAt = now().addingTimeInterval(retryPolicy.retryDelay(afterAttempt: attempt))
        try await journal.markRetryable(
          commandID: command.commandID,
          retryAt: retryAt)
      } else {
        retryAt = now().addingTimeInterval(retryPolicy.acknowledgementTimeout)
        try await journal.markWaitingForAcknowledgement(
          commandID: command.commandID,
          retryAt: retryAt)
      }
      await publishStatus()
      await scheduleRetryIfNeeded()
    } catch {
      // A stale didFinish callback can race a real application ACK. Never turn
      // that transport callback into a second state transition.
    }
  }

  private func drainPass() async {
    while true {
      let workspaceInstanceID: String
      do {
        workspaceInstanceID = try await replicaStore.currentWorkspaceInstanceID()
        let workspaceChanged = try await journal.rejectCommandsOutsideWorkspace(
          workspaceInstanceID,
          code: LorvexWatchDeliveryRejectionText.workspaceReplacedCode)
        if workspaceChanged { await publishStatus() }
      } catch {
        return
      }

      guard let entry = await journal.nextDeliverable(at: now()) else {
        await scheduleRetryIfNeeded()
        return
      }
      guard entry.command.workspaceInstanceID == workspaceInstanceID else {
        continue
      }

      let commandData: Data
      do {
        commandData = try entry.command.wireCommand().wireData()
      } catch {
        // Loaded entries were validated through the same Core initializer. If
        // this ever fails now, leave the journal intact and fail closed.
        return
      }

      switch await channel.deliveryState() {
      case .inactive:
        return
      case .background:
        if await channel.hasOutstandingBackgroundCommand(commandData) {
          try? await journal.markWaitingForAcknowledgement(
            commandID: entry.command.id,
            retryAt: now().addingTimeInterval(retryPolicy.acknowledgementTimeout))
          await scheduleRetryIfNeeded()
          return
        }
        do {
          try await journal.markAttemptStarted(commandID: entry.command.id)
          try await channel.enqueueBackground(commandData)
          try await journal.markWaitingForAcknowledgement(
            commandID: entry.command.id,
            retryAt: now().addingTimeInterval(retryPolicy.acknowledgementTimeout))
          await publishStatus()
          await scheduleRetryIfNeeded()
        } catch {
          await recordTransportFailure(entry: entry)
        }
        return
      case .reachable:
        do {
          try await journal.markAttemptStarted(commandID: entry.command.id)
          let reply = try await channel.sendDirect(commandData)
          let acknowledgement = try LorvexWatchCommandAck.decodeWireData(reply)
          let wireCommand = try entry.command.wireCommand()
          guard acknowledgement.matches(wireCommand) else {
            throw LorvexWatchCommandJournalError.acknowledgementMismatch
          }
          let resolution = try await journal.applyAcknowledgement(
            acknowledgement,
            retryAt: now().addingTimeInterval(
              retryPolicy.retryDelay(afterAttempt: entry.attemptCount + 1)))
          await publishStatus()
          switch resolution {
          case .applied, .rejected, .duplicate:
            continue
          case .retryable:
            await scheduleRetryIfNeeded()
            return
          }
        } catch {
          await recordTransportFailure(entry: entry)
          return
        }
      }
    }
  }

  private func recordTransportFailure(entry: LorvexWatchJournalEntry) async {
    do {
      let retryAt = now().addingTimeInterval(
        retryPolicy.retryDelay(afterAttempt: entry.attemptCount + 1))
      try await journal.markRetryable(
        commandID: entry.command.id,
        retryAt: retryAt)
      await publishStatus()
      await scheduleRetryIfNeeded()
    } catch {
      // Preserve the last successfully persisted journal state.
    }
  }

  private func publishStatus() async {
    statusHandler(await journal.deliveryStatus())
  }

  private func scheduleRetryIfNeeded() async {
    guard schedulesRetries else { return }
    scheduledRetry?.cancel()
    scheduledRetry = nil
    guard let retryAt = await journal.nextPendingRetryDate() else { return }
    let delay = max(0, retryAt.timeIntervalSince(now()))
    scheduledRetry = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await self?.drain()
    }
  }
}
