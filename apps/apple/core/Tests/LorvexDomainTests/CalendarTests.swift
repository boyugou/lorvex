import XCTest

@testable import LorvexDomain

final class CalendarTests: XCTestCase {

  // MARK: - helpers

  private func d(_ s: String) -> LorvexDate {
    guard case let .success(v) = LorvexDate.parse(s) else {
      XCTFail("date parse failed: \(s)"); fatalError()
    }
    return v
  }

  private func t(_ s: String) -> TimeOfDay {
    guard case let .success(v) = TimeOfDay.parse(s) else {
      XCTFail("time parse failed: \(s)"); fatalError()
    }
    return v
  }

  // MARK: - CanonicalCalendarEventType

  func testCanonicalCalendarEventTypeRoundTrips() throws {
    for raw in ["event", "birthday", "anniversary", "memorial"] {
      guard let parsed = CanonicalCalendarEventType.parse(raw) else {
        XCTFail("parse failed: \(raw)"); return
      }
      XCTAssertEqual(parsed.asString, raw)
      let data = try JSONEncoder().encode(parsed)
      XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(raw)\"")
    }
  }

  func testCanonicalCalendarEventTypeRejectsUnknownValues() {
    switch CanonicalCalendarEventType.validate("meeting") {
    case .success: XCTFail("must reject")
    case let .failure(msg):
      XCTAssertTrue(msg.contains("event_type must be one of"))
    }
  }

  func testCanonicalCalendarEventTypeCodableRejectsUnknown() {
    let data = "\"holiday\"".data(using: .utf8)!
    XCTAssertThrowsError(try JSONDecoder().decode(CanonicalCalendarEventType.self, from: data))
  }

  func testCanonicalCalendarEventTypeValidateMatchesParse() {
    let validateErr: String
    switch CanonicalCalendarEventType.validate("meeting") {
    case .success: return XCTFail("must reject")
    case let .failure(msg): validateErr = msg
    }
    // parse returns nil; validate returns the canonical error wording.
    XCTAssertNil(CanonicalCalendarEventType.parse("meeting"))
    XCTAssertEqual(
      validateErr, "event_type must be one of: event, birthday, anniversary, memorial")
  }

  // MARK: - CalendarEventTiming construction + validation

  func testFromFlatAllDaySingleDayConstructsAllDayVariant() {
    guard
      case let .success(timing) = CalendarEventTiming.fromFlatFields(
        startDate: d("2026-05-04"),
        startTime: nil,
        endDate: nil,
        endTime: nil,
        allDay: true)
    else { return XCTFail() }
    XCTAssertEqual(timing, .allDay(start: d("2026-05-04"), end: nil))
    XCTAssertTrue(timing.allDay)
    XCTAssertEqual(timing.startDate, d("2026-05-04"))
    XCTAssertNil(timing.startTime)
    XCTAssertNil(timing.endDate)
    XCTAssertNil(timing.endTime)
  }

  func testFromFlatAllDayMultiDayConstructsAllDayWithEnd() {
    guard
      case let .success(timing) = CalendarEventTiming.fromFlatFields(
        startDate: d("2026-05-04"),
        startTime: nil,
        endDate: d("2026-05-06"),
        endTime: nil,
        allDay: true)
    else { return XCTFail() }
    XCTAssertEqual(timing, .allDay(start: d("2026-05-04"), end: d("2026-05-06")))
    XCTAssertEqual(timing.endDate, d("2026-05-06"))
  }

  func testFromFlatAllDayRejectsStartTime() {
    let r = CalendarEventTiming.fromFlatFields(
      startDate: d("2026-05-04"),
      startTime: t("09:00"),
      endDate: nil,
      endTime: nil,
      allDay: true)
    guard case let .failure(err) = r else { return XCTFail() }
    XCTAssertTrue(err.description.contains("all_day"))
  }

  func testFromFlatAllDayRejectsEndTime() {
    let r = CalendarEventTiming.fromFlatFields(
      startDate: d("2026-05-04"),
      startTime: nil,
      endDate: nil,
      endTime: t("17:00"),
      allDay: true)
    guard case let .failure(err) = r else { return XCTFail() }
    XCTAssertTrue(err.description.contains("all_day"))
  }

  func testFromFlatAllDayRejectsEndDateBeforeStart() {
    let r = CalendarEventTiming.fromFlatFields(
      startDate: d("2026-05-06"),
      startTime: nil,
      endDate: d("2026-05-04"),
      endTime: nil,
      allDay: true)
    guard case let .failure(err) = r else { return XCTFail() }
    XCTAssertTrue(err.description.contains("end_date"))
  }

  func testFromFlatTimedSingleDayConstructsWithOptionalEnd() {
    guard
      case let .success(point) = CalendarEventTiming.fromFlatFields(
        startDate: d("2026-05-04"),
        startTime: t("09:00"),
        endDate: nil,
        endTime: nil,
        allDay: false)
    else { return XCTFail() }
    XCTAssertEqual(point, .timedSingleDay(date: d("2026-05-04"), start: t("09:00"), end: nil))

    guard
      case let .success(span) = CalendarEventTiming.fromFlatFields(
        startDate: d("2026-05-04"),
        startTime: t("09:00"),
        endDate: nil,
        endTime: t("10:30"),
        allDay: false)
    else { return XCTFail() }
    XCTAssertEqual(
      span, .timedSingleDay(date: d("2026-05-04"), start: t("09:00"), end: t("10:30")))
  }

  func testFromFlatTimedSingleDayAcceptsEndDateEqualToStart() {
    guard
      case let .success(timing) = CalendarEventTiming.fromFlatFields(
        startDate: d("2026-05-04"),
        startTime: t("09:00"),
        endDate: d("2026-05-04"),
        endTime: t("10:00"),
        allDay: false)
    else { return XCTFail() }
    XCTAssertEqual(
      timing, .timedSingleDay(date: d("2026-05-04"), start: t("09:00"), end: t("10:00")))
    XCTAssertNil(timing.endDate)
  }

  func testFromFlatTimedRejectsMissingStartTime() {
    let r = CalendarEventTiming.fromFlatFields(
      startDate: d("2026-05-04"),
      startTime: nil,
      endDate: nil,
      endTime: nil,
      allDay: false)
    guard case let .failure(err) = r else { return XCTFail() }
    XCTAssertTrue(err.description.contains("start_time"))
  }

  func testFromFlatTimedSingleDayRejectsEndBeforeStart() {
    let r = CalendarEventTiming.fromFlatFields(
      startDate: d("2026-05-04"),
      startTime: t("10:00"),
      endDate: nil,
      endTime: t("09:00"),
      allDay: false)
    guard case let .failure(err) = r else { return XCTFail() }
    XCTAssertTrue(err.description.contains("end_time"))
  }

  func testFromFlatTimedMultiDayConstructsFullForm() {
    guard
      case let .success(timing) = CalendarEventTiming.fromFlatFields(
        startDate: d("2026-05-04"),
        startTime: t("18:00"),
        endDate: d("2026-05-06"),
        endTime: t("09:00"),
        allDay: false)
    else { return XCTFail() }
    XCTAssertEqual(
      timing,
      .timedMultiDay(
        startDate: d("2026-05-04"),
        startTime: t("18:00"),
        endDate: d("2026-05-06"),
        endTime: t("09:00")))
  }

  func testFromFlatTimedMultiDayRejectsMissingEndTime() {
    let r = CalendarEventTiming.fromFlatFields(
      startDate: d("2026-05-04"),
      startTime: t("09:00"),
      endDate: d("2026-05-06"),
      endTime: nil,
      allDay: false)
    guard case let .failure(err) = r else { return XCTFail() }
    XCTAssertTrue(err.description.contains("end_time"))
  }

  func testFromFlatTimedMultiDayRejectsEndDateBeforeStart() {
    let r = CalendarEventTiming.fromFlatFields(
      startDate: d("2026-05-06"),
      startTime: t("09:00"),
      endDate: d("2026-05-04"),
      endTime: t("10:00"),
      allDay: false)
    guard case let .failure(err) = r else { return XCTFail() }
    XCTAssertTrue(err.description.contains("end_date"))
  }

  // MARK: - AllDayPatch

  func testAllDayPatchFromOptionalBool() {
    XCTAssertEqual(AllDayPatch.fromOptionalBool(nil), .noChange)
    XCTAssertEqual(AllDayPatch.fromOptionalBool(true), .setAllDay)
    XCTAssertEqual(AllDayPatch.fromOptionalBool(false), .setTimed)
  }

  func testAllDayPatchTargetValueAndPresence() {
    XCTAssertNil(AllDayPatch.noChange.targetValue)
    XCTAssertEqual(AllDayPatch.setAllDay.targetValue, true)
    XCTAssertEqual(AllDayPatch.setTimed.targetValue, false)
    XCTAssertFalse(AllDayPatch.noChange.isPresent)
    XCTAssertTrue(AllDayPatch.setAllDay.isPresent)
    XCTAssertTrue(AllDayPatch.setTimed.isPresent)
  }
}
