import XCTest

@testable import LorvexDomain

/// `Result<Void, _>` is not `Equatable` (Void cannot conform), so void-result
/// validators are checked by extracting and comparing the failure error.
func assertFailure(
  _ result: Result<Void, ValidationError>, _ expected: ValidationError,
  file: StaticString = #filePath, line: UInt = #line
) {
  switch result {
  case .success:
    XCTFail("expected failure \(expected), got success", file: file, line: line)
  case .failure(let e):
    XCTAssertEqual(e, expected, file: file, line: line)
  }
}
