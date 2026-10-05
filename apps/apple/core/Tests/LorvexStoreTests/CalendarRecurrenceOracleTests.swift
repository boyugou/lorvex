import Foundation
import XCTest

@testable import LorvexStore

/// Checks the recurrence expansion engine against vectors an independent RFC 5545
/// implementation (python-dateutil's `rrule`) produced for the same rules.
///
/// Two vector shapes share the file:
/// - `expected`: the first occurrence on or after `target` (never before `base`),
///   or null when the series ended.
/// - `successors`: the occurrences after `base`, each found from the previous
///   one the way a completed recurring task finds its successor. The fixture
///   lists at most ``successorLimit`` of them.
///
/// `spec/fixtures/recurrence/oracle-cases.json` is the committed set. Naming a
/// larger corpus made by `script/recurrence_oracle.py --cases` in the
/// `LORVEX_RECURRENCE_ORACLE_CASES` environment variable runs it as well.
final class CalendarRecurrenceOracleTests: XCTestCase {
  private static let successorLimit = 6

  func test_committed_vectors_match_the_oracle() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexStoreTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // core
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
    try check(
      vectorsAt: root.appendingPathComponent("spec/fixtures/recurrence/oracle-cases.json"),
      minimumCount: 900)
  }

  func test_vectors_named_by_the_environment_match_the_oracle() throws {
    guard let path = ProcessInfo.processInfo.environment["LORVEX_RECURRENCE_ORACLE_CASES"] else {
      throw XCTSkip("LORVEX_RECURRENCE_ORACLE_CASES names no corpus")
    }
    try check(vectorsAt: URL(fileURLWithPath: path), minimumCount: 1)
  }

  private func check(vectorsAt url: URL, minimumCount: Int) throws {
    let data = try Data(contentsOf: url)
    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let vectors = try XCTUnwrap(root["vectors"] as? [[String: Any]])
    XCTAssertGreaterThanOrEqual(vectors.count, minimumCount, "the vector set shrank")

    var disagreements: [String] = []
    for vector in vectors {
      let rule = try XCTUnwrap(vector["rule"] as? [String: Any])
      let ruleText = String(
        decoding: try JSONSerialization.data(withJSONObject: rule, options: [.sortedKeys]),
        as: UTF8.self)
      let base = try XCTUnwrap(vector["base"] as? String)
      do {
        if let expected = vector["successors"] as? [String] {
          let found = try successors(of: ruleText, from: base)
          if found != expected {
            disagreements.append("\(ruleText) from \(base): successors \(expected), engine \(found)")
          }
        } else {
          let target = try XCTUnwrap(vector["target"] as? String)
          let expected = vector["expected"] as? String
          let found = try CalendarRecurrence.firstOccurrenceOnOrAfter(
            recurrenceJson: ruleText, baseDateYmd: base, targetDateYmd: target)
          if found != expected {
            disagreements.append(
              "\(ruleText) from \(base) on or after \(target): expected \(expected ?? "nil"), engine \(found ?? "nil")"
            )
          }
        }
      } catch {
        disagreements.append("\(ruleText) from \(base): engine threw \(error)")
      }
    }
    XCTAssertTrue(
      disagreements.isEmpty,
      "\(disagreements.count) of \(vectors.count) vectors disagree with the oracle:\n"
        + disagreements.prefix(12).joined(separator: "\n"))
  }

  private func successors(of rule: String, from base: String) throws -> [String] {
    var found: [String] = []
    var current = base
    for _ in 0..<Self.successorLimit {
      guard
        let next = try CalendarRecurrence.calculateNextOccurrenceDate(
          recurrenceJson: rule, baseDateYmd: current)
      else { break }
      found.append(next)
      current = next
    }
    return found
  }
}
