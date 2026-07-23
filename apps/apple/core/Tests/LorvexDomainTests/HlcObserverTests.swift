import XCTest

@testable import LorvexDomain

/// Ports `lorvex-domain/src/hlc_observer/tests.rs`. The test observer is a
/// `@TaskLocal` overlay consulted before the production slot, so
/// `withTemporaryObserver` installs its own observer and restores on scope
/// exit (no cross-test bleed), matching Rust's thread-local + Guard-drop.
final class HlcObserverTests: XCTestCase {
  /// Thread-safe capture box for the observer closure (which is `@Sendable`).
  private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func mutate(_ f: (inout T) -> Void) {
      lock.lock(); defer { lock.unlock() }
      f(&value)
    }
    func get() -> T {
      lock.lock(); defer { lock.unlock() }
      return value
    }
  }

  func testObserveLocalEventIsNoopWithoutObserver() {
    // No test observer is installed in this scope; the production slot may or
    // may not be set by another test, but the call must not crash.
    let hlc = try! Hlc(physicalMs: 1_000_000_000_000, counter: 0, deviceSuffix: "abcdef0123456789")
    HlcObserver.observeLocalEvent(hlc)
  }

  func testWithTemporaryObserverCapturesEvent() {
    let captured = Box<[Hlc]>([])
    let hlc = try! Hlc(physicalMs: 1_000_000_000_000, counter: 5, deviceSuffix: "abcdef0123456789")

    HlcObserver.withTemporaryObserver({ observed in
      captured.mutate { $0.append(observed) }
    }) {
      HlcObserver.observeLocalEvent(hlc)
    }

    let result = captured.get()
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0], hlc)
  }

  /// S-03: the production observer slot is last-install-wins. After an in-process
  /// Settings DB switch hands a fresh service's live clock a new observer,
  /// merge-minted HLCs must advance THAT clock, not the old dead one the first
  /// service installed. The second install reports `.alreadyInstalled` (a prior
  /// observer existed) yet still takes effect, so the live observer fires and the
  /// stale one never does.
  func testProductionSlotIsLastInstallWins() {
    let stale = Box<Int>(0)
    let live = Box<Int>(0)
    _ = HlcObserver.setLocalEventObserver { _ in stale.mutate { $0 += 1 } }
    let secondOutcome = HlcObserver.setLocalEventObserver { _ in live.mutate { $0 += 1 } }
    XCTAssertEqual(
      secondOutcome, .alreadyInstalled,
      "replacing an existing observer reports alreadyInstalled while still taking effect")

    HlcObserver.observeLocalEvent(
      try! Hlc(physicalMs: 3_000_000_000_000, counter: 0, deviceSuffix: "0000000000000003"))

    XCTAssertEqual(live.get(), 1, "the last-installed (live) observer must fire")
    XCTAssertEqual(stale.get(), 0, "the replaced (stale) observer must not fire")
  }

  func testWithTemporaryObserverClearsOnDrop() {
    let count = Box<Int>(0)
    HlcObserver.withTemporaryObserver({ _ in
      count.mutate { $0 += 1 }
    }) {
      HlcObserver.observeLocalEvent(
        try! Hlc(physicalMs: 1_000_000_000_000, counter: 0, deviceSuffix: "0000000000000001"))
    }
    // Outside the helper: the test observer slot is restored, so this must NOT
    // re-fire the previous capture closure.
    HlcObserver.observeLocalEvent(
      try! Hlc(physicalMs: 2_000_000_000_000, counter: 0, deviceSuffix: "0000000000000002"))
    XCTAssertEqual(count.get(), 1)
  }
}
