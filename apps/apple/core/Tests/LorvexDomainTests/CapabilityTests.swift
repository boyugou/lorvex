import XCTest

@testable import LorvexDomain

final class CapabilityTests: XCTestCase {
  // Envelope
  func testEnvelopeZeroVersionIsInvalid() {
    XCTAssertEqual(
      Capability.checkEnvelopeVersion(envelopePayloadVersion: 0, localMaxVersion: 1),
      .rejectInvalid)
  }

  func testEnvelopeKnownVersionParseFully() {
    XCTAssertEqual(
      Capability.checkEnvelopeVersion(envelopePayloadVersion: 1, localMaxVersion: 1),
      .parseFully)
  }

  func testEnvelopeOlderVersion() {
    XCTAssertEqual(
      Capability.checkEnvelopeVersion(envelopePayloadVersion: 1, localMaxVersion: 3),
      .parseFully)
  }

  func testEnvelopeOneAhead() {
    XCTAssertEqual(
      Capability.checkEnvelopeVersion(envelopePayloadVersion: 2, localMaxVersion: 1),
      .parseForwardCompat)
  }

  func testEnvelopeTwoAhead() {
    XCTAssertEqual(
      Capability.checkEnvelopeVersion(envelopePayloadVersion: 3, localMaxVersion: 1),
      .deferToPendingInbox)
  }

  func testEnvelopeWayAhead() {
    XCTAssertEqual(
      Capability.checkEnvelopeVersion(envelopePayloadVersion: 100, localMaxVersion: 5),
      .deferToPendingInbox)
  }

  func testEnvelopeSame() {
    XCTAssertEqual(
      Capability.checkEnvelopeVersion(envelopePayloadVersion: 5, localMaxVersion: 5),
      .parseFully)
  }

  func testEnvelopeVersionCheckSaturatesAtUInt32Max() {
    XCTAssertEqual(
      Capability.checkEnvelopeVersion(
        envelopePayloadVersion: UInt32.max, localMaxVersion: UInt32.max),
      .parseFully)
  }
}
