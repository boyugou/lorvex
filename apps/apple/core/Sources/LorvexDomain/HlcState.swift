import Foundation

/// Mutable HLC generator state for a single device, holding the
/// monotonicity invariant: every generated HLC is strictly greater than
/// the previous, even if the physical clock goes backward.
///
/// Surfaces hold one instance behind their own lock (the type is `final class`
/// so all references see the same counter advance).
public final class HlcState {
  public private(set) var lastPhysicalMs: UInt64
  public private(set) var counter: UInt32
  public let deviceSuffix: String

  /// Construct a generator. The suffix is validated up front (via
  /// `Hlc(physicalMs:counter:deviceSuffix:)`) and canonicalized to
  /// lowercase so every subsequent `generate(...)` is infallible.
  public init(deviceSuffix: String) throws {
    let canon = try Hlc(physicalMs: 0, counter: 0, deviceSuffix: deviceSuffix)
    self.lastPhysicalMs = 0
    self.counter = 0
    self.deviceSuffix = canon.deviceSuffix
  }

  /// Generate an HLC using the supplied physical timestamp (Unix ms).
  /// Deterministic seam for testing — production callers use `generate()`.
  ///
  /// Clamps inputs and post-bump physical to `Hlc.maxPhysicalMs` so a
  /// future-dated NTP response or counter-overflow tail can't poison the
  /// lex-sort ceiling.
  @discardableResult
  public func generate(withPhysicalMs physicalMs: UInt64) -> Hlc {
    let phys = min(physicalMs, Hlc.maxPhysicalMs)
    lastPhysicalMs = min(lastPhysicalMs, Hlc.maxPhysicalMs)
    let newPhysical = max(lastPhysicalMs, phys)

    if newPhysical == lastPhysicalMs {
      // Same or backward clock — increment counter (saturating against u32
      // overflow from a tainted prior value; the MAX_COUNTER guard below
      // rolls forward immediately).
      counter = counter == UInt32.max ? UInt32.max : counter &+ 1
    } else {
      counter = 0
    }
    lastPhysicalMs = newPhysical

    if counter > Hlc.maxCounter {
      // Overflow recovery: advance physical by 1 ms and reset the counter. At the
      // absolute lex-sort ceiling physical cannot advance, so SATURATE the counter
      // at its max instead of resetting to 0 — resetting there would emit
      // `(maxPhysicalMs, 0)` right after `(maxPhysicalMs, maxCounter)`, a
      // backwards-sorting HLC that corrupts LWW ordering. Holding at
      // `(maxPhysicalMs, maxCounter)` keeps the stream monotonic non-decreasing
      // (rare ties resolve via the existing tie-break). Only reachable at the
      // far-future ceiling year or via a peer HLC pinned to maxPhysicalMs.
      if lastPhysicalMs == Hlc.maxPhysicalMs {
        counter = Hlc.maxCounter
      } else {
        lastPhysicalMs += 1
        counter = 0
      }
    }

    // Construction can only fail on suffix-shape violations, which are
    // ruled out by the constructor's up-front check.
    return Hlc(uncheckedPhysicalMs: lastPhysicalMs, counter: counter, deviceSuffix: deviceSuffix)
  }

  /// Generate using the current wall-clock time. Falls back to 0 on a
  /// pre-1970 clock so HLC generation never crashes the writer.
  @discardableResult
  public func generate() -> Hlc {
    let now = Date().timeIntervalSince1970
    let nowMs: UInt64 = now < 0 ? 0 : UInt64(now * 1000)
    return generate(withPhysicalMs: nowMs)
  }

  /// Default forward clock-skew bound for an inbound PEER envelope's HLC (ms).
  /// A peer with a wrong/future clock must not be able to drag this device's
  /// clock arbitrarily far forward — that would pin the whole fleet's clock and
  /// let the bad envelope's future timestamp dominate every honest concurrent
  /// edit. Five minutes dwarfs honest NTP skew (sub-second) yet sits far below
  /// `Hlc.maxPhysicalMs`, so within-bound the clamp is a literal no-op.
  public static let maxInboundForwardDriftMs: UInt64 = 5 * 60 * 1000

  /// Advance local state after receiving a remote HLC, so the next
  /// locally-minted HLC is strictly greater than the remote one. `physicalMs` is
  /// the current wall-clock at the moment of receive.
  ///
  /// UNBOUNDED — use only for advancing past a future row `version` an EXPLICIT
  /// local edit must supersede: a deliberate user mutation must always be able to
  /// dominate the row it edits. Every OBSERVED value whose physical time is not
  /// trusted — an inbound PEER envelope, the startup seed scan (rows matched by a
  /// device suffix a peer could forge), and a merge/clear HLC minted during apply
  /// from attacker-influenced participant versions — uses the bounded overload
  /// ``updateOnReceive(remote:physicalMs:maxForwardDriftMs:)`` instead, so a
  /// future-clocked value cannot pin this device's clock.
  public func updateOnReceive(remote: Hlc, physicalMs: UInt64) {
    applyRemote(
      remotePhysical: remote.physicalMs, remoteCounter: remote.counter, physicalMs: physicalMs)
  }

  /// Advance local state after OBSERVING an HLC whose physical time is not
  /// trusted — an inbound PEER envelope, the startup seed scan (rows matched by a
  /// forgeable device suffix), or a merge/clear HLC minted during apply from
  /// attacker-influenced participant versions — bounding the remote's forward
  /// reach to `phys + maxForwardDriftMs`. Forward-only: a past-dated remote is
  /// untouched. This is per-device clock hygiene only — it never changes which
  /// version wins LWW (a pure lexicographic compare of version strings on every
  /// peer), so a mixed fleet (some devices bounding, some not) still converges;
  /// only the local clock advance is contained, so no single untrusted future
  /// stamp — arriving on an envelope OR driving a merge HLC — can pin this
  /// device's clock beyond `now + drift`. The lone exception is an explicit local
  /// edit, which advances unbounded via ``updateOnReceive(remote:physicalMs:)`` so
  /// the user can always supersede the row they are editing.
  public func updateOnReceive(remote: Hlc, physicalMs: UInt64, maxForwardDriftMs: UInt64) {
    let phys = min(physicalMs, Hlc.maxPhysicalMs)
    let cappedRemotePhys = min(remote.physicalMs, phys &+ maxForwardDriftMs)
    applyRemote(
      remotePhysical: cappedRemotePhys, remoteCounter: remote.counter, physicalMs: physicalMs)
  }

  private func applyRemote(remotePhysical: UInt64, remoteCounter: UInt32, physicalMs: UInt64) {
    let phys = min(physicalMs, Hlc.maxPhysicalMs)
    lastPhysicalMs = min(lastPhysicalMs, Hlc.maxPhysicalMs)
    let remotePhys = min(remotePhysical, Hlc.maxPhysicalMs)
    let newPhysical = max(max(lastPhysicalMs, remotePhys), phys)

    if newPhysical == lastPhysicalMs && newPhysical == remotePhys {
      let m = max(counter, remoteCounter)
      counter = m == UInt32.max ? UInt32.max : m &+ 1
    } else if newPhysical == lastPhysicalMs {
      counter = counter == UInt32.max ? UInt32.max : counter &+ 1
    } else if newPhysical == remotePhys {
      counter = remoteCounter == UInt32.max ? UInt32.max : remoteCounter &+ 1
    } else {
      counter = 0
    }
    lastPhysicalMs = newPhysical

    if counter > Hlc.maxCounter {
      // See `generate(withPhysicalMs:)`: saturate at the absolute ceiling rather
      // than wrapping the counter backwards.
      if lastPhysicalMs == Hlc.maxPhysicalMs {
        counter = Hlc.maxCounter
      } else {
        lastPhysicalMs += 1
        counter = 0
      }
    }
  }
}

/// Storage-side handle that backs an `HlcSession`. Each surface
/// implements this for whatever container holds its `HlcState`.
public protocol HlcStateHandle: Sendable {
  /// Acquire the storage lock and mint the next strictly-monotonic HLC.
  /// Implementations must serialize concurrent calls.
  func generate() -> Hlc
}

/// Optional stronger clock capability used by explicit local operations that
/// must supersede a known future-stamped row. Keeping it separate from
/// ``HlcStateHandle`` preserves lightweight deterministic test handles while a
/// production clock can provide an atomic advance-and-mint implementation.
public protocol HlcDominatingStateHandle: HlcStateHandle {
  func generate(dominating floor: Hlc?) -> Hlc
}

/// Per-mutation HLC stamp session. Constructed once per top-level
/// mutation; `nextVersion()` is called once per row stamped within that
/// mutation. Unifies the API boundary across surfaces without touching
/// how each surface stores its `HlcState`.
public struct HlcSession {
  private let handle: any HlcStateHandle

  public init(handle: any HlcStateHandle) { self.handle = handle }

  /// Mint the next strictly-monotonic HLC.
  public func nextVersion() -> Hlc { handle.generate() }

  /// Mint after `floor` when the backing clock supports explicit dominance.
  /// Lightweight test handles fall back to their ordinary monotonic mint; the
  /// caller that requires dominance still validates the returned HLC.
  public func nextVersion(dominating floor: Hlc?) -> Hlc {
    if let dominating = handle as? any HlcDominatingStateHandle {
      return dominating.generate(dominating: floor)
    }
    return handle.generate()
  }

  /// Convenience: mint the next stamp and stringify it to the wire
  /// format. Avoids a `.description` at every call site.
  public func nextVersionString() -> String { nextVersion().description }

  public func nextVersionString(dominating floor: Hlc?) -> String {
    nextVersion(dominating: floor).description
  }
}
