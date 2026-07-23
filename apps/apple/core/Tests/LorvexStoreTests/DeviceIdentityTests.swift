import LorvexDomain
import XCTest

@testable import LorvexStore

final class DeviceIdentityTests: XCTestCase {
  func testHlcSuffixLengthLowercaseHex() {
    let suffix = DeviceIdentity.deviceIdToHlcSuffix(
      "aabbccdd-1122-3344-5566-778899001122", surface: .app)
    XCTAssertEqual(suffix.count, HlcConstants.deviceSuffixHexLen)
    XCTAssertEqual(suffix.count, 16)
    XCTAssertEqual(suffix, suffix.lowercased())
    for c in suffix {
      XCTAssertTrue(c.isHexDigit, "non-hex char in suffix: \(c)")
    }
  }

  func testHlcSuffixIsDeterministic() {
    let a = DeviceIdentity.deviceIdToHlcSuffix(
      "aabbccdd-1122-3344-5566-778899001122", surface: .mcp)
    let b = DeviceIdentity.deviceIdToHlcSuffix(
      "aabbccdd-1122-3344-5566-778899001122", surface: .mcp)
    XCTAssertEqual(a, b)
  }

  func testHlcSuffixDiffersAcrossSurfaces() {
    let id = "aabbccdd-1122-3344-5566-778899001122"
    let suffixes = HlcSurface.allSurfaces.map {
      DeviceIdentity.deviceIdToHlcSuffix(id, surface: $0)
    }
    XCTAssertEqual(Set(suffixes).count, HlcSurface.allSurfaces.count)
  }

  func testHlcSuffixDiffersAcrossDevicesForSameSurface() {
    let a = DeviceIdentity.deviceIdToHlcSuffix(
      "01936e3a-f000-7aaa-bbbb-111111111111", surface: .app)
    let b = DeviceIdentity.deviceIdToHlcSuffix(
      "01936e3a-f000-7ccc-dddd-222222222222", surface: .app)
    XCTAssertNotEqual(a, b)
  }

  func testHlcSuffixCaseInsensitiveOnDeviceId() {
    let lower = DeviceIdentity.deviceIdToHlcSuffix(
      "aabbccdd-1122-3344-5566-778899001122", surface: .app)
    let upper = DeviceIdentity.deviceIdToHlcSuffix(
      "AABBCCDD-1122-3344-5566-778899001122", surface: .app)
    XCTAssertEqual(lower, upper)
  }

  /// Parity fixture: hand-computed via
  /// `SHA-256("aabbccdd112233445566778899001122|<surface>")[:8]` hex-encoded.
  /// Locks the byte composition (dash-stripped + lowercased device id, then
  /// `b"|"`, then surface tag).
  func testHlcSuffixParityFixture() {
    let id = "aabbccdd-1122-3344-5566-778899001122"
    XCTAssertEqual(
      DeviceIdentity.deviceIdToHlcSuffix(id, surface: .app), "814a40b92ecdf47d")
    XCTAssertEqual(
      DeviceIdentity.deviceIdToHlcSuffix(id, surface: .appIntent), "e19537f98800c3b1")
    XCTAssertEqual(
      DeviceIdentity.deviceIdToHlcSuffix(id, surface: .widget), "49e6b048ea62b3ab")
    XCTAssertEqual(
      DeviceIdentity.deviceIdToHlcSuffix(id, surface: .notification), "d7da352f0731cef4")
    XCTAssertEqual(
      DeviceIdentity.deviceIdToHlcSuffix(id, surface: .mobile), "effd8acf8005068c")
    XCTAssertEqual(
      DeviceIdentity.deviceIdToHlcSuffix(id, surface: .mcp), "e939e41940d0f76a")
  }
}
