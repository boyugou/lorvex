import XCTest

@testable import LorvexDomain

/// `PayloadByteBudget.canonicalEscapedUTF8Count` must count exactly the bytes
/// the real canonical serializer emits for a string value — the budgets bound
/// wire size, so any drift between the counter and the serializer would let a
/// budget-legal field overflow the payload cap (or reject a legal one).
final class PayloadByteBudgetTests: XCTestCase {

  /// Fixed overhead of `{"k":""}` around the escaped string bytes.
  private let envelopeOverhead = 8

  private func serializedEscapedBytes(_ value: String) throws -> Int {
    let json = try canonicalizeJSON(.object(["k": .string(value)]))
    return json.utf8.count - envelopeOverhead
  }

  func testEscapedCountMatchesSerializerAcrossAdversarialCorpus() throws {
    let corpus: [String] = [
      "",
      "plain ascii",
      "quote \" and backslash \\",
      "newline \n return \r tab \t",
      "backspace \u{08} formfeed \u{0C}",
      "other controls \u{01}\u{1F}\u{0B}\u{7F}",
      "two-byte é ñ ü",
      "three-byte 中文字符",
      "four-byte emoji 😀🎉",
      "astral plane \u{10000}\u{10FFFF}",
      "line separators \u{2028}\u{2029}",
      String(repeating: "😀", count: 1_000),
      String(repeating: "\u{01}", count: 500),
      String(repeating: "\"\\\n", count: 300),
      "mixed \" \\ \n \u{01} é 中 😀 \u{2028}",
    ]
    for value in corpus {
      XCTAssertEqual(
        PayloadByteBudget.canonicalEscapedUTF8Count(value),
        try serializedEscapedBytes(value),
        "escaped-byte count must match the canonical serializer for \(value.debugDescription)")
    }
  }

  func testBudgetBoundaryAcceptsAtAndRejectsAboveTheLimit() {
    let atBudget = String(repeating: "a", count: 100)
    if case .failure = PayloadByteBudget.validateEscapedBudget(
      atBudget, field: "f", budget: 100)
    {
      XCTFail("a value exactly at its byte budget must pass")
    }

    // An escape-inflating control character pushes the same codepoint count
    // over the byte budget: 99 ASCII + 1 C0 control = 105 escaped bytes.
    let inflated = String(repeating: "a", count: 99) + "\u{01}"
    guard
      case .failure(let error) = PayloadByteBudget.validateEscapedBudget(
        inflated, field: "f", budget: 100)
    else {
      return XCTFail("escape inflation past the budget must reject")
    }
    guard case .tooLong(let field, let max, let actual) = error else {
      return XCTFail("expected tooLong, got \(error)")
    }
    XCTAssertEqual(field, "f")
    XCTAssertEqual(max, 100)
    XCTAssertEqual(actual, 105)
  }

  func testOptionalVariantPassesNilAndDelegatesOtherwise() {
    if case .failure = PayloadByteBudget.validateOptionalEscapedBudget(
      nil, field: "f", budget: 1)
    {
      XCTFail("nil always passes")
    }
    if case .success = PayloadByteBudget.validateOptionalEscapedBudget(
      "toolong", field: "f", budget: 1)
    {
      XCTFail("a present over-budget value must reject")
    }
  }
}
