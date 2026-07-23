import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime

extension SwiftLorvexCoreService {
  /// Transaction-scoped HLC handle. A transaction starts on the normal lane;
  /// once it must dominate a future floor it permanently switches to the
  /// detached lane. This prevents a single explicit repair/edit from poisoning
  /// unrelated future writes while preserving strict ordering among every row
  /// and outbox envelope minted by the repairing transaction itself.
  final class HlcTransactionHandle: HlcDominatingStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let clock: HlcClock
    private var detachedState: HlcState?
    private var pendingDetachedFirst: Hlc?
    private var isDetached = false
    private var normalHighWater: Hlc?
    private var detachedHighWater: Hlc?
    /// Non-throwing HLC protocols cannot surface exhaustion at the mint call.
    /// Record it here and make transaction finalization throw before any data or
    /// high-water reservation can commit.
    private var terminalFailure: HlcHighWaterError?

    init(clock: HlcClock, detachedHighWater: Hlc?) {
      self.clock = clock
      self.detachedHighWater = detachedHighWater
    }

    func generate() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      if !isDetached {
        let minted = clock.generateNormal()
        recordNormal(minted)
        return minted
      }
      if let first = pendingDetachedFirst {
        pendingDetachedFirst = nil
        return first
      }
      return generateDetached(dominating: nil)
    }

    func generate(dominating floor: Hlc?) -> Hlc {
      lock.lock()
      defer { lock.unlock() }

      if !isDetached {
        let candidate = clock.generateNormal()
        recordNormal(candidate)
        guard let floor, candidate <= floor else { return candidate }
        enterDetached(anchor: candidate, floor: floor)
        let first = pendingDetachedFirst!
        pendingDetachedFirst = nil
        return first
      }
      if let first = pendingDetachedFirst, floor.map({ first > $0 }) ?? true {
        pendingDetachedFirst = nil
        return first
      }
      pendingDetachedFirst = nil
      return generateDetached(dominating: floor)
    }

    /// Force the lane switch before replaying a transaction that already lost an
    /// LWW gate. The first mint in the replay will dominate `floor`, and all
    /// subsequent row/changelog/outbox mints remain in the same detached run.
    func enterDetached(dominating floor: Hlc) {
      lock.lock()
      defer { lock.unlock() }
      if !isDetached {
        let anchor = clock.generateNormal()
        recordNormal(anchor)
        enterDetached(anchor: anchor, floor: floor)
        return
      }
      pendingDetachedFirst = nil
      guard let detachedState else {
        recordTerminalFailure(at: floor)
        return
      }
      let first = advanceDetachedState(detachedState, dominating: floor)
      pendingDetachedFirst = first
      recordDetached(first)
    }

    /// Reserve a bounded normal-lane successor for a deterministic aggregate
    /// merge HLC minted directly by the sync engine. The merge row keeps its
    /// exact deterministic stamp; this reservation only prevents a restart from
    /// re-minting the same normal-era value and is persisted with the transaction.
    func reserveAfterDeterministicMerge(_ value: Hlc) {
      lock.lock()
      defer { lock.unlock() }
      if isDetached {
        // A merge HLC is minted outside this handle and can be above the first
        // detached reservation. Replace any pending value with a current-suffix
        // successor so the next convergence emission is guaranteed to dominate
        // the merge and the durable detached high-water remains self-authored.
        pendingDetachedFirst = nil
        let reservation = generateDetached(dominating: value)
        pendingDetachedFirst = reservation
        return
      }
      recordNormal(clock.reserveAfterDeterministicMerge(value))
    }

    /// Persist every value reserved by this handle inside the same SQLite
    /// transaction as the rows that use it. Rollback therefore removes both the
    /// data and its durable reservation; a committed row can never outlive its
    /// trusted high-water.
    func persistHighWaters(_ db: Database) throws {
      lock.lock()
      let normal = normalHighWater
      let failure = terminalFailure
      lock.unlock()
      if let failure { throw failure }
      if let normal {
        try SyncCheckpoints.set(db, key: clock.normalHighWaterKey, value: normal.description)
      }
      if isDetached, let detachedHighWater {
        try SyncCheckpoints.set(
          db, key: clock.detachedHighWaterKey, value: detachedHighWater.description)
      }
    }

    private func recordNormal(_ value: Hlc) {
      guard Hlc.isOperationallyAcceptableWire(value) else {
        recordTerminalFailure(at: value)
        return
      }
      normalHighWater = normalHighWater.map { max($0, value) } ?? value
    }

    /// Start the exceptional future lane past both the requested floor and the
    /// last committed detached value. The detached checkpoint is independent of
    /// the normal lane: exceptional edits remain globally unique and causally
    /// ordered without pinning ordinary writes to a peer's bad wall clock.
    private func enterDetached(anchor: Hlc, floor: Hlc) {
      let base = detachedHighWater.map { max(max(anchor, floor), $0) } ?? max(anchor, floor)
      do {
        let detached = try HlcState(deviceSuffix: clock.deviceSuffix)
        detachedState = detached
        // `updateOnReceive` itself advances to the first strict successor. Do
        // not call `generate()` again: at the operational boundary that would
        // consume two counter slots and falsely make a mathematically editable
        // counter-9998 floor unrecoverable.
        let first = advanceDetachedState(detached, dominating: base)
        guard first > base else {
          recordTerminalFailure(at: base)
          pendingDetachedFirst = base
          isDetached = true
          return
        }
        pendingDetachedFirst = first
        recordDetached(first)
        isDetached = true
      } catch {
        recordTerminalFailure(at: base)
        pendingDetachedFirst = base
        isDetached = true
      }
    }

    private func generateDetached(dominating floor: Hlc?) -> Hlc {
      guard let detachedState else {
        let fallback = floor ?? detachedHighWater ?? clock.generateNormal()
        recordTerminalFailure(at: fallback)
        return fallback
      }
      let prior = detachedHighWater
      let minted = floor.map { advanceDetachedState(detachedState, dominating: $0) }
        ?? detachedState.generate()
      guard floor.map({ minted > $0 }) ?? true,
        prior.map({ minted > $0 }) ?? true
      else {
        let exhaustedAt = floor.map { max($0, prior ?? $0) } ?? prior ?? minted
        recordTerminalFailure(at: exhaustedAt)
        return minted
      }
      recordDetached(minted)
      return minted
    }

    /// Advance-and-return the exact successor produced by `updateOnReceive`.
    /// The mutable state exposes its canonical components, so reconstruction is
    /// infallible for a suffix validated when the clock was created.
    private func advanceDetachedState(_ state: HlcState, dominating floor: Hlc) -> Hlc {
      state.updateOnReceive(remote: floor, physicalMs: Self.nowMs())
      do {
        return try Hlc(
          physicalMs: state.lastPhysicalMs, counter: state.counter,
          deviceSuffix: state.deviceSuffix)
      } catch {
        recordTerminalFailure(at: floor)
        return floor
      }
    }

    private func recordDetached(_ value: Hlc) {
      guard Hlc.isOperationallyAcceptableWire(value) else {
        recordTerminalFailure(at: value)
        return
      }
      detachedHighWater = detachedHighWater.map { max($0, value) } ?? value
    }

    private func recordTerminalFailure(at value: Hlc) {
      if terminalFailure == nil {
        terminalFailure = .unrecoverableFloor(value: value.description)
      }
    }

    private static func nowMs() -> UInt64 {
      HlcClock.nowMs()
    }
  }
}
