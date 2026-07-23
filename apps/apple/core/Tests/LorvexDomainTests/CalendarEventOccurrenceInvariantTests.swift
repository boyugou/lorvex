import XCTest

@testable import LorvexDomain

final class CalendarEventOccurrenceInvariantTests: XCTestCase {
  private let generation = "1800000000000_0001_1111111111111111"
  private let topology = "1800000000000_0002_2222222222222222"

  func testPlainBaseRequiresOnlyTopologyVersion() throws {
    try assertValid(
      recurrence: nil, seriesId: nil, instanceDate: nil, state: nil,
      generation: nil, topology: topology)

    XCTAssertThrowsError(
      try assertValid(
        recurrence: nil, seriesId: nil, instanceDate: nil, state: nil,
        generation: nil, topology: nil))
    XCTAssertThrowsError(
      try assertValid(
        recurrence: nil, seriesId: nil, instanceDate: nil, state: nil,
        generation: generation, topology: topology))
  }

  func testRecurringMasterRequiresGenerationAndTopology() throws {
    try assertValid(
      recurrence: #"{"FREQ":"WEEKLY"}"#, seriesId: nil, instanceDate: nil, state: nil,
      generation: generation, topology: topology)

    for (missingGeneration, missingTopology) in [(true, false), (false, true)] {
      XCTAssertThrowsError(
        try assertValid(
          recurrence: #"{"FREQ":"WEEKLY"}"#, seriesId: nil, instanceDate: nil, state: nil,
          generation: missingGeneration ? nil : generation,
          topology: missingTopology ? nil : topology))
    }
  }

  func testEveryDecisionStateUsesTheSameCanonicalShape() throws {
    for state in CalendarOccurrenceState.allCases {
      try assertValid(
        recurrence: nil, seriesId: "master-1", instanceDate: "2026-08-10", state: state,
        generation: generation, topology: nil)
    }
  }

  func testMalformedDecisionShapesAreRejected() {
    let cases: [(String?, String?, CalendarOccurrenceState?, String?, String?)] = [
      ("master-1", nil, .replacement, generation, nil),
      (nil, "2026-08-10", .replacement, generation, nil),
      ("master-1", "2026-08-10", nil, generation, nil),
      ("master-1", "2026-08-10", .replacement, nil, nil),
      ("master-1", "2026-08-10", .replacement, generation, topology),
    ]
    for (seriesId, date, state, generation, topology) in cases {
      XCTAssertThrowsError(
        try assertValid(
          recurrence: nil, seriesId: seriesId, instanceDate: date, state: state,
          generation: generation, topology: topology))
    }
  }

  func testDecisionRejectsRecurrenceInvalidDateEmptySeriesAndSelfReference() {
    for (eventId, seriesId, date, recurrence) in [
      ("decision", "master", "2026-08-10", #"{"FREQ":"DAILY"}"#),
      ("decision", "master", "2026-02-30", nil),
      ("decision", "", "2026-08-10", nil),
      ("decision", "decision", "2026-08-10", nil),
    ] {
      XCTAssertThrowsError(
        try assertValid(
          eventId: eventId, recurrence: recurrence, seriesId: seriesId,
          instanceDate: date, state: .replacement, generation: generation, topology: nil))
    }
  }

  func testGenerationAndTopologyMustBeCanonicalHlcStrings() {
    for invalid in [
      "1800000000000_1_1111111111111111",
      "1800000000000_0001_ABCDEFABCDEFABCD",
      "not-an-hlc",
    ] {
      XCTAssertThrowsError(
        try assertValid(
          recurrence: nil, seriesId: "master", instanceDate: "2026-08-10",
          state: .replacement, generation: invalid, topology: nil))
      XCTAssertThrowsError(
        try assertValid(
          recurrence: nil, seriesId: nil, instanceDate: nil,
          state: nil, generation: nil, topology: invalid))
    }
  }

  private func assertValid(
    eventId: String = "decision",
    recurrence: String?,
    seriesId: String?,
    instanceDate: String?,
    state: CalendarOccurrenceState?,
    generation: String?,
    topology: String?
  ) throws {
    switch CalendarEventOccurrenceInvariant.validate(
      eventId: eventId,
      recurrence: recurrence,
      seriesId: seriesId,
      recurrenceInstanceDate: instanceDate,
      occurrenceState: state,
      recurrenceGeneration: generation,
      recurrenceTopologyVersion: topology)
    {
    case .success:
      return
    case .failure(let error):
      throw error
    }
  }
}
