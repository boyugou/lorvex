import Foundation
import LorvexDomain
import XCTest

@testable import LorvexRuntime

/// Ports `lorvex-runtime/src/device_identity/tests.rs`. The HLC-suffix
/// algorithm is the authoritative `LorvexStore.DeviceIdentity` re-export, so
/// these assertions also pin the parity contract for the runtime surface.
final class DeviceIdentityTests: XCTestCase {
  func testGetOrCreateDeviceIdPersistsFirstValue() throws {
    let store = try RuntimeTestSupport.freshStore()
    let first = try store.writer.write { try DeviceIdentity.getOrCreateDeviceId($0) }
    let second = try store.writer.write { try DeviceIdentity.getOrCreateDeviceId($0) }
    XCTAssertEqual(first, second)
    XCTAssertFalse(first.trimmingCharacters(in: .whitespaces).isEmpty)
  }

  func testHlcSuffixIsCorrectLengthLowercaseHex() {
    let suffix = DeviceIdentity.deviceIdToHlcSuffix(
      "aabbccdd-1122-3344-5566-778899001122", surface: .app)
    XCTAssertEqual(suffix.count, HlcConstants.deviceSuffixHexLen)
    XCTAssertEqual(suffix.count, 16)
    XCTAssertTrue(suffix.allSatisfy { $0.isHexDigit })
    XCTAssertEqual(suffix, suffix.lowercased())
  }

  func testHlcSuffixIsDeterministic() {
    let a = DeviceIdentity.deviceIdToHlcSuffix("aabbccdd-1122-3344-5566-778899001122", surface: .mcp)
    let b = DeviceIdentity.deviceIdToHlcSuffix("aabbccdd-1122-3344-5566-778899001122", surface: .mcp)
    XCTAssertEqual(a, b)
  }

  func testHlcSuffixDiffersAcrossSurfacesForSameDevice() {
    let deviceId = "aabbccdd-1122-3344-5566-778899001122"
    let suffixes = HlcSurface.allSurfaces.map {
      DeviceIdentity.deviceIdToHlcSuffix(deviceId, surface: $0)
    }
    XCTAssertEqual(Set(suffixes).count, HlcSurface.allSurfaces.count)
  }

  func testHlcSuffixDiffersAcrossDevicesForSameSurface() {
    let uuid1 = "01936e3a-f000-7aaa-bbbb-111111111111"
    let uuid2 = "01936e3a-f000-7ccc-dddd-222222222222"
    XCTAssertNotEqual(
      DeviceIdentity.deviceIdToHlcSuffix(uuid1, surface: .app),
      DeviceIdentity.deviceIdToHlcSuffix(uuid2, surface: .app))
  }

  func testHlcSuffixCaseInsensitiveOnDeviceId() {
    let lower = DeviceIdentity.deviceIdToHlcSuffix(
      "aabbccdd-1122-3344-5566-778899001122", surface: .app)
    let upper = DeviceIdentity.deviceIdToHlcSuffix(
      "AABBCCDD-1122-3344-5566-778899001122", surface: .app)
    XCTAssertEqual(lower, upper)
  }
}
