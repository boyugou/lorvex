import XCTest

@testable import LorvexWorkflow

final class DailyReviewDateTests: XCTestCase {
  private func resolve(_ requested: String?, _ today: String) -> Result<
    String, DailyReviewDate.DateError
  > {
    DailyReviewDate.resolveDailyReviewWriteDate(requestedDate: requested, today: today)
  }

  func testResolvesMissingToToday() throws {
    XCTAssertEqual(try resolve(nil, "2026-05-13").get(), "2026-05-13")
  }

  func testAcceptsTodayStaleEdgeAndOneDayFuture() throws {
    XCTAssertEqual(try resolve("2026-05-13", "2026-05-13").get(), "2026-05-13")
    XCTAssertEqual(try resolve("2026-05-06", "2026-05-13").get(), "2026-05-06")
    XCTAssertEqual(try resolve("2026-05-14", "2026-05-13").get(), "2026-05-14")
  }

  func testRejectsMalformedStaleAndFarFuture() {
    if case .invalidDate = resolve("not-a-date", "2026-05-13").err() {} else {
      XCTFail("expected invalidDate")
    }
    if case .tooStale = resolve("2026-05-05", "2026-05-13").err() {} else {
      XCTFail("expected tooStale")
    }
    if case .tooFarFuture = resolve("2026-05-15", "2026-05-13").err() {} else {
      XCTFail("expected tooFarFuture")
    }
  }
}

extension Result {
  fileprivate func err() -> Failure? {
    if case .failure(let e) = self { return e }
    return nil
  }
}
