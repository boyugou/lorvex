import XCTest

@testable import LorvexDomain

/// Ports the Rust HLC test suite. Asserts on the canonical wire format,
/// strict parse + suffix shape, ordering, the cross-string comparator
/// fallback, the test-version constant, and the surface tag.
final class HlcTests: XCTestCase {
  // MARK: - Display / format

  func testDisplayMatchesCanonicalWidths() throws {
    let hlc = try Hlc(physicalMs: 1_711_060_000, counter: 42, deviceSuffix: "abcdef0123456789")
    // 13-digit zero-padded ms + 4-digit zero-padded counter + 16-char suffix.
    XCTAssertEqual(hlc.description, "0001711060000_0042_abcdef0123456789")
  }

  func testDisplayAtMaxPhysicalAndMaxCounter() throws {
    let hlc = try Hlc(
      physicalMs: Hlc.maxPhysicalMs, counter: Hlc.maxCounter,
      deviceSuffix: "0123456789abcdef")
    XCTAssertEqual(hlc.description, "9999999999999_9999_0123456789abcdef")
  }

  func testOperationalWireBoundaryReservesExactlyOneDayOfPhysicalHeadroom() throws {
    XCTAssertEqual(
      Hlc.maxPhysicalMs - Hlc.maxOperationalWirePhysicalMs,
      86_400_000)
    let atBoundary = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs, counter: Hlc.maxCounter,
      deviceSuffix: "ffffffffffffffff")
    let aboveBoundary = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
      deviceSuffix: "0000000000000000")
    XCTAssertTrue(Hlc.isOperationallyAcceptableWire(atBoundary))
    XCTAssertFalse(Hlc.isOperationallyAcceptableWire(aboveBoundary))
    XCTAssertFalse(Hlc.hasOperationalWireSuccessor(after: atBoundary))
    XCTAssertTrue(
      Hlc.hasOperationalWireSuccessor(
        after: try Hlc(
          physicalMs: Hlc.maxOperationalWirePhysicalMs,
          counter: Hlc.maxCounter - 1,
          deviceSuffix: "ffffffffffffffff")))
    XCTAssertFalse(Hlc.hasOperationalWireSuccessor(after: aboveBoundary))
  }

  // MARK: - Construction

  func testNewLowercasesMixedCaseSuffix() throws {
    let hlc = try Hlc(physicalMs: 0, counter: 0, deviceSuffix: "ABCDEF0123456789")
    XCTAssertEqual(hlc.deviceSuffix, "abcdef0123456789")
  }

  func testNewRejectsBadSuffixLength() {
    XCTAssertThrowsError(try Hlc(physicalMs: 0, counter: 0, deviceSuffix: "short"))
    XCTAssertThrowsError(try Hlc(physicalMs: 0, counter: 0, deviceSuffix: "00112233445566778899"))
  }

  func testNewRejectsNonHexSuffix() {
    XCTAssertThrowsError(try Hlc(physicalMs: 0, counter: 0, deviceSuffix: "not-hex-but16chrs"))
  }

  func testNewRejectsPhysicalMsAboveCeiling() {
    XCTAssertThrowsError(
      try Hlc(physicalMs: Hlc.maxPhysicalMs + 1, counter: 0, deviceSuffix: "0123456789abcdef")
    ) { error in
      XCTAssertEqual(error as? HlcParseError, .physicalMsOutOfRange(Hlc.maxPhysicalMs + 1))
    }
  }

  func testNewRejectsCounterAboveCeiling() {
    XCTAssertThrowsError(
      try Hlc(physicalMs: 0, counter: Hlc.maxCounter + 1, deviceSuffix: "0123456789abcdef")
    ) { error in
      XCTAssertEqual(error as? HlcParseError, .counterOutOfRange(Hlc.maxCounter + 1))
    }
  }

  // MARK: - Parse

  func testParseAcceptsCanonicalForm() throws {
    let hlc = try Hlc.parse("0001711060000_0042_abcdef0123456789")
    XCTAssertEqual(hlc.physicalMs, 1_711_060_000)
    XCTAssertEqual(hlc.counter, 42)
    XCTAssertEqual(hlc.deviceSuffix, "abcdef0123456789")
  }

  func testParseNormalizesMixedCaseSuffix() throws {
    let lower = try Hlc.parse("0001711060000_0042_abcdef0123456789")
    let upper = try Hlc.parse("0001711060000_0042_ABCDEF0123456789")
    XCTAssertEqual(upper, lower)
    XCTAssertEqual(upper.deviceSuffix, "abcdef0123456789")
  }

  func testParseAcceptsUnpaddedSegments() throws {
    // Strictly more permissive than Display on width; suffix shape is
    // still enforced. The numeric fields parse to the same logical value.
    let hlc = try Hlc.parse("1711060000_42_abcdef0123456789")
    XCTAssertEqual(hlc.physicalMs, 1_711_060_000)
    XCTAssertEqual(hlc.counter, 42)
  }

  func testParseRejectsMalformed() {
    XCTAssertThrowsError(try Hlc.parse("not-an-hlc"))
    XCTAssertThrowsError(try Hlc.parse("0001711060000__abcdef0123456789"))
    XCTAssertThrowsError(try Hlc.parse("0001711060000_0042_"))
  }

  func testParseRejectsSignPrefixedNumericSegments() {
    // Swift's integer initializers accept a leading '+' (and "-0"), but a sign
    // byte sorts below '0', so a sign-prefixed segment would let the numeric
    // ordering disagree with the raw-byte (SQLite BINARY) collation of the same
    // stored strings. The canonical parse must reject any non-digit.
    XCTAssertThrowsError(try Hlc.parse("+001711060000_0042_abcdef0123456789"))
    XCTAssertThrowsError(try Hlc.parse("0001711060000_+042_abcdef0123456789"))
    XCTAssertThrowsError(try Hlc.parse("0001711060000_-042_abcdef0123456789"))
    XCTAssertThrowsError(try Hlc.parse("0001711060000_-0_abcdef0123456789"))
  }

  func testParseRejectsNonHexSuffix() {
    // A 16-char suffix that is not all lowercase-hex is not canonical.
    XCTAssertThrowsError(try Hlc.parse("0001711060000_0042_zzzzzzzzzzzzzzzz"))
    XCTAssertThrowsError(try Hlc.parse("0001711060000_0042_abcdef012345678!"))
  }

  func testParseRejectsPhysicalAboveCeiling() {
    XCTAssertThrowsError(try Hlc.parse("99999999999999_0000_abcdef0123456789"))
  }

  func testRoundTripCanonicalForm() throws {
    let canonical = "0001711060000_0042_abcdef0123456789"
    XCTAssertEqual(try Hlc.parse(canonical).description, canonical)
  }

  func testParseCanonicalRejectsNormalizableButNoncanonicalForms() throws {
    let canonical = "0001711060000_0042_abcdef0123456789"
    XCTAssertEqual(try Hlc.parseCanonical(canonical).description, canonical)
    XCTAssertThrowsError(try Hlc.parseCanonical("1711060000_42_abcdef0123456789"))
    XCTAssertThrowsError(try Hlc.parseCanonical("0001711060000_0042_ABCDEF0123456789"))
  }

  // MARK: - Ordering

  func testOrderingByPhysicalThenCounterThenSuffix() throws {
    let a = try Hlc(physicalMs: 100, counter: 0, deviceSuffix: "abcdef0123456789")
    let b = try Hlc(physicalMs: 101, counter: 0, deviceSuffix: "abcdef0123456789")
    let c = try Hlc(physicalMs: 100, counter: 1, deviceSuffix: "abcdef0123456789")
    let d = try Hlc(physicalMs: 100, counter: 0, deviceSuffix: "bbcdef0123456789")
    XCTAssertLessThan(a, b)
    XCTAssertLessThan(a, c)
    XCTAssertLessThan(c, b)
    XCTAssertLessThan(a, d)
  }

  // MARK: - Cross-string comparator

  func testCompareWithFallbackParsesCanonical() {
    let l = "0001711060000_0042_abcdef0123456789"
    let r = "0001711060000_0043_abcdef0123456789"
    XCTAssertEqual(compareVersionsWithFallback(l, r), .orderedAscending)
  }

  func testCompareWithFallbackByteSortsMixedCaseSuffix() {
    // A mixed-case suffix is non-canonical — canonical HLCs are lowercase hex —
    // so it routes to byte-compare, the SQLite BINARY ground truth, rather than a
    // case-folding fast path. 'A' (0x41) sorts below 'a' (0x61).
    XCTAssertEqual(
      compareVersionsWithFallback(
        "0001711060000_0042_ABCDEF0123456789",
        "0001711060000_0042_abcdef0123456789"),
      .orderedAscending)
  }

  func testCompareWithFallbackByteSortsSignPrefixedSegment() {
    // A sign-prefixed counter ("+042") is non-canonical and routes to
    // byte-compare rather than the numeric fast path. '+' (0x2B) sorts below
    // '0' (0x30), so the signed string precedes its canonical twin — matching
    // SQLite BINARY, which the numeric fast path (42 == 42) would contradict.
    let signed = "0001711060000_+042_abcdef0123456789"
    let canonical = "0001711060000_0042_abcdef0123456789"
    XCTAssertEqual(compareVersionsWithFallback(signed, canonical), .orderedAscending)
  }

  func testCanonicalComparatorAndTypedOrderAgreeWithByteOrder() throws {
    // Convergence contract: for every ACCEPTED canonical HLC, the string
    // comparator's numeric fast path, the typed `Hlc` Comparable, and a raw
    // utf8 byte compare (SQLite BINARY) must produce identical orderings — LWW
    // resolution and SQL `MAX(version)` must never disagree.
    let canonical = [
      "0000000000000_0000_0000000000000000",
      "0000000000000_0000_abcdef0123456789",
      "0000000000000_0001_0000000000000000",
      "0001711060000_0042_abcdef0123456789",
      "0001711060000_0042_abcdef012345678a",
      "0001711060000_0043_0000000000000000",
      "0009999999999_9999_ffffffffffffffff",
      "9999999999999_9999_ffffffffffffffff",
    ]
    for l in canonical {
      for r in canonical {
        let byte: ComparisonResult =
          l == r
          ? .orderedSame
          : (l.utf8.lexicographicallyPrecedes(r.utf8) ? .orderedAscending : .orderedDescending)
        XCTAssertEqual(
          compareVersionsWithFallback(l, r), byte, "string comparator disagrees: \(l) vs \(r)")
        let lh = try Hlc.parse(l)
        let rh = try Hlc.parse(r)
        let typed: ComparisonResult =
          lh == rh ? .orderedSame : (lh < rh ? .orderedAscending : .orderedDescending)
        XCTAssertEqual(typed, byte, "typed Hlc order disagrees: \(l) vs \(r)")
      }
    }
  }

  func testCompareWithFallbackByteComparesUnparseable() {
    // Both unparseable — byte-compare fallback. "garbage-a" < "garbage-b".
    XCTAssertEqual(
      compareVersionsWithFallback("garbage-a", "garbage-b"), .orderedAscending)
  }

  func testCompareWithFallbackByteSortsOverRangeCounter() {
    // An over-range counter segment ("10000", 5 digits) is non-canonical, so
    // both strings route to byte-compare — the documented ground truth — not
    // the numeric fast path. Numeric order would call 9999 < 10000
    // (ascending); byte order calls "10000…" < "9999…" because '1' < '9'.
    let canonical = "0001711060000_9999_abcdef0123456789"
    let overRange = "0001711060000_10000_abcdef0123456789"
    XCTAssertEqual(
      compareVersionsWithFallback(canonical, overRange), .orderedDescending)
  }

  func testCompareWithFallbackByteSortsWrongLengthSuffix() {
    // A truncated device suffix (15 hex chars) is non-canonical and routes to
    // byte-compare rather than the case-folding canonical path.
    let truncated = "0001711060000_0042_abcdef012345678"
    let canonical = "0001711060000_0042_abcdef0123456789"
    XCTAssertEqual(
      compareVersionsWithFallback(truncated, canonical), .orderedAscending)
  }

  // MARK: - canonicalPreferringDominates (shared LWW canonical-beats-tainted tiebreak)

  func testCanonicalPreferringDominatesBothParseUsesTypedCompare() {
    let older = "0001711060000_0001_abcdef0123456789"
    let newer = "0001711060000_0002_abcdef0123456789"
    XCTAssertTrue(canonicalPreferringDominates(incoming: newer, existing: older))
    XCTAssertFalse(canonicalPreferringDominates(incoming: older, existing: newer))
    // Equal is not strict domination.
    XCTAssertFalse(canonicalPreferringDominates(incoming: newer, existing: newer))
  }

  func testCanonicalPreferringDominatesCanonicalBeatsTainted() {
    let canonical = "0001711060000_0001_abcdef0123456789"
    let tainted = "not-an-hlc"
    // A canonical incoming clears a tainted existing regardless of raw bytes.
    XCTAssertTrue(canonicalPreferringDominates(incoming: canonical, existing: tainted))
    // A tainted incoming never displaces a canonical existing, even if it would
    // byte-sort above it ("not-an-hlc" > "0001…").
    XCTAssertFalse(canonicalPreferringDominates(incoming: tainted, existing: canonical))
  }

  func testCanonicalPreferringDominatesTreatsParseableNoncanonicalAsTainted() {
    let canonical = "0001711060000_0001_abcdef0123456789"
    let unpadded = "1711060000_2_abcdef0123456789"
    let uppercase = "0001711060000_0002_ABCDEF0123456789"
    XCTAssertNoThrow(try Hlc.parse(unpadded))
    XCTAssertNoThrow(try Hlc.parse(uppercase))

    XCTAssertTrue(canonicalPreferringDominates(incoming: canonical, existing: unpadded))
    XCTAssertTrue(canonicalPreferringDominates(incoming: canonical, existing: uppercase))
    XCTAssertFalse(canonicalPreferringDominates(incoming: unpadded, existing: canonical))
    XCTAssertFalse(canonicalPreferringDominates(incoming: uppercase, existing: canonical))
  }

  func testCanonicalPreferringDominatesNeitherParsesUsesByteCompare() {
    // Both tainted: raw UTF-8 byte compare. "garbage-b" dominates "garbage-a".
    XCTAssertTrue(canonicalPreferringDominates(incoming: "garbage-b", existing: "garbage-a"))
    XCTAssertFalse(canonicalPreferringDominates(incoming: "garbage-a", existing: "garbage-b"))
    // Equal tainted strings do not dominate.
    XCTAssertFalse(canonicalPreferringDominates(incoming: "garbage-a", existing: "garbage-a"))
  }

  func testDescriptionUsesCanonicalWidths() throws {
    let hlc = try Hlc(physicalMs: 42, counter: 7, deviceSuffix: "abcdef0123456789")
    XCTAssertEqual(hlc.description, "0000000000042_0007_abcdef0123456789")
  }

  // MARK: - Codable

  func testCodableRoundTrip() throws {
    let hlc = try Hlc(physicalMs: 1_711_060_000, counter: 42, deviceSuffix: "abcdef0123456789")
    let data = try JSONEncoder().encode(hlc)
    let back = try JSONDecoder().decode(Hlc.self, from: data)
    XCTAssertEqual(back, hlc)
    // Encoded as the canonical string.
    XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(hlc.description)\"")
  }

  func testCodableRejectsParseableButNoncanonicalWireValues() {
    for value in [
      "1711060000_42_abcdef0123456789",
      "0001711060000_0042_ABCDEF0123456789",
    ] {
      XCTAssertNoThrow(try Hlc.parse(value))
      XCTAssertThrowsError(
        try JSONDecoder().decode(Hlc.self, from: Data("\"\(value)\"".utf8)))
    }
  }

  // MARK: - HlcSurface

  func testHlcSurfaceWireTagsAreFrozen() {
    XCTAssertEqual(HlcSurface.app.rawValue, "app")
    XCTAssertEqual(HlcSurface.appIntent.rawValue, "app_intent")
    XCTAssertEqual(HlcSurface.widget.rawValue, "widget")
    XCTAssertEqual(HlcSurface.notification.rawValue, "notification")
    XCTAssertEqual(HlcSurface.mobile.rawValue, "mobile")
    XCTAssertEqual(HlcSurface.mcp.rawValue, "mcp")
    XCTAssertEqual(
      HlcSurface.allSurfaces,
      [.app, .appIntent, .widget, .notification, .mobile, .mcp])
  }

  // MARK: - Test version constant

  func testTestVersionSortsBelowRealisticHlc() throws {
    let realistic = try Hlc(
      physicalMs: 1_711_060_000_000, counter: 0, deviceSuffix: "abcdef0123456789")
    XCTAssertTrue(Hlc.testVersion < realistic.description)
    XCTAssertTrue(Hlc.testVersion.first!.isNumber, "testVersion must start with a digit")
  }
}

/// Ports the Rust `HlcState` tests: monotonicity, generate-on-backward-clock,
/// receive-on-remote, counter overflow recovery, and the lex-ceiling guard.
final class HlcStateTests: XCTestCase {
  private func newState(_ suffix: String = "0123456789abcdef") -> HlcState {
    try! HlcState(deviceSuffix: suffix)
  }

  func testGenerateMonotonicForwardClock() {
    let s = newState()
    let v1 = s.generate(withPhysicalMs: 1_000)
    let v2 = s.generate(withPhysicalMs: 1_001)
    XCTAssertLessThan(v1, v2)
    XCTAssertEqual(v2.counter, 0, "counter resets when clock advances")
  }

  func testGenerateMonotonicBackwardClock() {
    let s = newState()
    let v1 = s.generate(withPhysicalMs: 1_000)
    let v2 = s.generate(withPhysicalMs: 500)  // backward
    XCTAssertLessThan(v1, v2, "monotonicity holds via counter even when clock goes backward")
    XCTAssertEqual(v2.physicalMs, 1_000)
    XCTAssertEqual(v2.counter, 1)
  }

  func testGenerateSameMillisecondIncrementsCounter() {
    let s = newState()
    let v1 = s.generate(withPhysicalMs: 1_000)
    let v2 = s.generate(withPhysicalMs: 1_000)
    XCTAssertEqual(v1.counter, 0)
    XCTAssertEqual(v2.counter, 1)
  }

  func testCounterOverflowAdvancesPhysical() {
    let s = newState()
    // First call sets counter=0; the next maxCounter same-ms calls walk it
    // to maxCounter; one more triggers overflow → +1ms, counter resets.
    for _ in 0...(Int(Hlc.maxCounter) + 1) {
      _ = s.generate(withPhysicalMs: 1_000)
    }
    XCTAssertEqual(s.lastPhysicalMs, 1_001, "overflow bumps physical by 1ms")
    XCTAssertEqual(s.counter, 0, "and resets the counter")
  }

  func testGenerateClampsPhysicalAtCeiling() {
    let s = newState()
    let v = s.generate(withPhysicalMs: Hlc.maxPhysicalMs &+ 1_000)
    XCTAssertLessThanOrEqual(v.physicalMs, Hlc.maxPhysicalMs)
  }

  func testGenerateSaturatesAtAbsoluteCeilingNeverWrapsBackward() {
    let s = newState()
    // Pin the clock at the absolute lex-sort ceiling, then overflow the counter
    // within that same (ceiling) millisecond. Physical can't advance, so the only
    // monotonic option is to saturate the counter — never reset it to 0, which
    // would emit a backwards-sorting HLC and corrupt LWW ordering.
    var last = s.generate(withPhysicalMs: Hlc.maxPhysicalMs)
    for _ in 0...(Int(Hlc.maxCounter) + 5) {
      let next = s.generate(withPhysicalMs: Hlc.maxPhysicalMs)
      XCTAssertGreaterThanOrEqual(next, last, "ceiling HLC must never sort backward")
      last = next
    }
    XCTAssertEqual(s.lastPhysicalMs, Hlc.maxPhysicalMs)
    XCTAssertEqual(s.counter, Hlc.maxCounter, "counter saturates at the ceiling, never resets to 0")
  }

  func testUpdateOnReceiveAdvancesPastRemote() throws {
    let s = newState()
    let remote = try Hlc(physicalMs: 5_000, counter: 7, deviceSuffix: "fedcba9876543210")
    s.updateOnReceive(remote: remote, physicalMs: 1_000)
    let next = s.generate(withPhysicalMs: 1_000)
    XCTAssertGreaterThan(next, remote, "next local stamp strictly greater than remote")
  }

  /// S-1: a far-future PEER envelope must not drag this device's clock beyond
  /// `now + drift` (otherwise one bad envelope permanently pins the whole fleet's
  /// clock). Fails on pre-S-1 code (no bounded overload).
  func testUpdateOnReceiveBoundsForwardDriftFromPeer() throws {
    let s = newState()
    let nowMs: UInt64 = 1_000_000
    let drift = HlcState.maxInboundForwardDriftMs
    let farFuture = try Hlc(
      physicalMs: Hlc.maxPhysicalMs, counter: 0, deviceSuffix: "fedcba9876543210")
    s.updateOnReceive(remote: farFuture, physicalMs: nowMs, maxForwardDriftMs: drift)
    XCTAssertLessThanOrEqual(
      s.lastPhysicalMs, nowMs &+ drift,
      "a far-future peer must not drag the local clock beyond now + drift")
  }

  /// Within the drift window the bound is a no-op — the clock still advances
  /// exactly to the inbound HLC, so honest NTP skew never loses LWW.
  func testUpdateOnReceiveStillAdvancesFullyWithinDrift() throws {
    let s = newState()
    let nowMs: UInt64 = 1_000_000
    let drift = HlcState.maxInboundForwardDriftMs
    let withinBound = try Hlc(
      physicalMs: nowMs &+ 1_000, counter: 3, deviceSuffix: "fedcba9876543210")
    s.updateOnReceive(remote: withinBound, physicalMs: nowMs, maxForwardDriftMs: drift)
    XCTAssertEqual(
      s.lastPhysicalMs, nowMs &+ 1_000,
      "an inbound HLC within the drift bound advances the clock unclamped")
  }

  /// The UNBOUNDED overload (seed + local-merge path) must STILL advance fully to
  /// a far-future OWN HLC, or a device recovering from its own past forward-skew
  /// would re-mint below its prior writes and lose LWW to itself.
  func testUnboundedUpdateOnReceiveAdvancesPastFarFutureOwnHistory() throws {
    let s = newState()
    let farFutureOwn = try Hlc(
      physicalMs: Hlc.maxPhysicalMs, counter: 0, deviceSuffix: "0123456789abcdef")
    s.updateOnReceive(remote: farFutureOwn, physicalMs: 1_000)
    XCTAssertEqual(
      s.lastPhysicalMs, Hlc.maxPhysicalMs,
      "the unbounded overload (seed/merge) advances fully past far-future own history")
  }

  func testHlcSessionEmitsMonotonicStamps() throws {
    // Single-threaded handle backed by the state under test.
    final class TestHandle: HlcStateHandle, @unchecked Sendable {
      let state: HlcState
      init(_ state: HlcState) { self.state = state }
      func generate() -> Hlc { state.generate() }
    }
    let s = try HlcState(deviceSuffix: "0123456789abcdef")
    let session = HlcSession(handle: TestHandle(s))
    let v1 = session.nextVersion()
    let v2 = session.nextVersion()
    let v3 = session.nextVersion()
    XCTAssertLessThan(v1, v2)
    XCTAssertLessThan(v2, v3)
  }
}
