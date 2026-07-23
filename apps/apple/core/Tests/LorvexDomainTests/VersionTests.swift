import XCTest
@testable import LorvexDomain

/// Ported from `lorvex_domain::version::tests`.
final class VersionTests: XCTestCase {
  func testAppVersionIsSemver() {
    let parts = LorvexVersion.appVersion.split(separator: ".")
    XCTAssertEqual(parts.count, 3, "appVersion must be semver")
    for part in parts {
      XCTAssertNotNil(UInt32(part), "each semver part must be numeric")
    }
  }
}
