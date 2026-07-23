import XCTest

@testable import LorvexDomain

final class CalendarIcsTests: XCTestCase {

  private func sampleEvent() -> CalendarIcsEvent {
    let res = CalendarIcsEvent.make(CalendarIcsEventFields(
      id: "evt-1",
      title: "Weekly planning",
      description: "Review the week",
      recurrence: nil,
      recurrenceExceptions: nil,
      startDate: try! LorvexDate.parse("2026-03-18").get(),
      startTime: try! TimeOfDay.parse("09:30").get(),
      endDate: nil,
      endTime: try! TimeOfDay.parse("10:30").get(),
      allDay: false,
      location: "Desk",
      timezone: nil,
      createdAt: "2026-03-17T08:00:00Z",
      updatedAt: "2026-03-18T08:30:00Z",
      sequence: 0
    ))
    return try! res.get()
  }

  // MARK: range validation

  func test_validateExportRange_rejectsReverseRange() {
    let result = validateExportRange(from: "2026-03-20", to: "2026-03-18")
    guard case .failure(let err) = result else {
      XCTFail("expected failure")
      return
    }
    XCTAssertEqual(err, .invalidRange(from: "2026-03-20", to: "2026-03-18"))
  }

  // MARK: emit basics

  func test_exportCalendarIcs_formatsTimedEvent() {
    let ics = try! exportCalendarIcs([sampleEvent()]).get()
    XCTAssertTrue(ics.contains("BEGIN:VCALENDAR"))
    XCTAssertTrue(ics.contains("UID:evt-1@lorvex"))
    XCTAssertTrue(ics.contains("DTSTART:20260318T093000Z"))
    XCTAssertTrue(ics.contains("DTEND:20260318T103000Z"))
    XCTAssertTrue(ics.contains("SUMMARY:Weekly planning"))
  }

  func test_exportCalendarIcs_emitsSequenceLine() {
    let event = sampleEvent()
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(ics.contains("SEQUENCE:0"))
  }

  func test_exportCalendarIcs_emitsNonzeroSequenceForEditedEvent() {
    var event = sampleEvent()
    event.sequence = 7
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(ics.contains("SEQUENCE:7"))
  }

  func test_exportCalendarIcs_replacementUsesSeriesUidAndOriginalTimedSlot() {
    var event = sampleEvent()
    event.uid = "series-1"
    event.recurrenceID = .dateTime(
      date: try! LorvexDate.parse("2026-03-20").get(),
      time: try! TimeOfDay.parse("09:30").get(),
      timezone: "America/New_York")
    event.timing = .timedSingleDay(
      date: try! LorvexDate.parse("2026-03-19").get(),
      start: try! TimeOfDay.parse("11:00").get(),
      end: try! TimeOfDay.parse("12:00").get())

    let ics = try! exportCalendarIcs([event]).get()

    XCTAssertTrue(ics.contains("UID:series-1@lorvex"), ics)
    XCTAssertTrue(ics.contains("RECURRENCE-ID:20260320T133000Z"), ics)
    XCTAssertTrue(ics.contains("DTSTART:20260319T110000Z"), ics)
  }

  func test_exportCalendarIcs_allDayReplacementUsesDateRecurrenceId() {
    var event = sampleEvent()
    event.uid = "series-2"
    event.recurrenceID = .date(try! LorvexDate.parse("2026-03-20").get())
    event.timing = .allDay(
      start: try! LorvexDate.parse("2026-03-22").get(), end: nil)

    let ics = try! exportCalendarIcs([event]).get()

    XCTAssertTrue(ics.contains("UID:series-2@lorvex"), ics)
    XCTAssertTrue(ics.contains("RECURRENCE-ID;VALUE=DATE:20260320"), ics)
    XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20260322"), ics)
  }

  // MARK: text cap / truncate

  func test_exportCalendarIcs_truncatesOversizeSummary() {
    let hugeTitle = String(repeating: "x", count: maxVeventTextLength + 50)
    var event = sampleEvent()
    event.title = hugeTitle
    let (ics, warnings) = try! exportCalendarIcsWithWarnings([event]).get()
    XCTAssertTrue(ics.contains("\u{2026}"))
    let truncated = warnings.contains { w in
      if case .textTruncated(let field, let originalChars, let truncatedTo) = w {
        return field == "SUMMARY" && originalChars == maxVeventTextLength + 50 && truncatedTo == maxVeventTextLength
      }
      return false
    }
    XCTAssertTrue(truncated, "must emit TextTruncated warning; got: \(warnings)")
  }

  func test_exportCalendarIcs_doesNotWarnForSummaryAtCap() {
    let exactTitle = String(repeating: "x", count: maxVeventTextLength)
    var event = sampleEvent()
    event.title = exactTitle
    let (_, warnings) = try! exportCalendarIcsWithWarnings([event]).get()
    let truncated = warnings.contains { if case .textTruncated = $0 { return true } else { return false } }
    XCTAssertFalse(truncated)
  }

  // MARK: PRODID

  func test_exportCalendarIcs_prodidIncludesAppVersion() {
    let ics = try! exportCalendarIcs([sampleEvent()]).get()
    let expected = "PRODID:-//Lorvex//Calendar \(LorvexVersion.appVersion)//EN"
    XCTAssertTrue(ics.contains(expected), "got:\n\(ics)")
  }

  // MARK: timezone conversion

  func test_exportCalendarIcs_convertsLocalTimeToUtcForNyTz() {
    var event = sampleEvent()
    event.timezone = "America/New_York"
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(ics.contains("DTSTART:20260318T133000Z"), "got: \(ics)")
    XCTAssertTrue(ics.contains("DTEND:20260318T143000Z"), "got: \(ics)")
  }

  func test_exportCalendarIcs_convertsExdateSameAsDtstart() {
    var event = sampleEvent()
    event.timezone = "America/New_York"
    event.recurrence = #"{"FREQ":"WEEKLY","INTERVAL":1}"#
    event.recurrenceExceptions = #"["2026-03-25"]"#
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(ics.contains("EXDATE:20260325T133000Z"), "got: \(ics)")
  }

  // MARK: exception JSON / dates

  func test_exportCalendarIcs_rejectsInvalidExceptionJson() {
    var event = sampleEvent()
    event.recurrenceExceptions = "[1,2,3]"
    let result = exportCalendarIcs([event])
    XCTAssertEqual(result, .failure(.invalidRecurrenceExceptionJson("[1,2,3]")))
  }

  func test_exportCalendarIcs_rejectsInvalidExceptionDate() {
    var event = sampleEvent()
    event.recurrenceExceptions = "[\"2026-02-30\"]"
    let result = exportCalendarIcs([event])
    XCTAssertEqual(result, .failure(.invalidRecurrenceExceptionDate("2026-02-30")))
  }

  // MARK: RRULE serializer

  func test_recurrenceToRrule_daily() {
    var warnings: [CalendarIcsWarning] = []
    let r = try! recurrenceToRrule(
      #"{"FREQ":"DAILY","INTERVAL":1}"#, isDateValue: true, warnings: &warnings).get()
    XCTAssertEqual(r, "RRULE:FREQ=DAILY")
    XCTAssertTrue(warnings.isEmpty)
  }

  func test_recurrenceToRrule_rejectsMalformedJson() {
    var warnings: [CalendarIcsWarning] = []
    let result = recurrenceToRrule("{bad json", isDateValue: true, warnings: &warnings)
    if case .failure(let err) = result {
      if case .invalidRecurrenceRule = err { return }
      XCTFail("expected invalidRecurrenceRule, got \(err)")
    } else {
      XCTFail("expected failure")
    }
  }

  func test_recurrenceToRrule_rejectsUnknownBydayCode() {
    var warnings: [CalendarIcsWarning] = []
    let result = recurrenceToRrule(
      #"{"FREQ":"WEEKLY","BYDAY":["MO","MX"]}"#, isDateValue: true, warnings: &warnings)
    guard case .failure(let err) = result, case .invalidRecurrenceRule(let msg) = err else {
      XCTFail("expected invalidRecurrenceRule")
      return
    }
    XCTAssertTrue(msg.contains("MX") && msg.contains("MO/TU/WE/TH/FR/SA/SU"),
      "got: \(msg)")
  }

  func test_recurrenceToRrule_acceptsAllValidBydayCodes() {
    var warnings: [CalendarIcsWarning] = []
    let r = try! recurrenceToRrule(
      #"{"FREQ":"WEEKLY","BYDAY":["MO","TU","WE","TH","FR","SA","SU"]}"#,
      isDateValue: true, warnings: &warnings).get()
    XCTAssertEqual(r, "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU")
  }

  func test_recurrenceToRrule_rejectsInvalidUntilDate() {
    var warnings: [CalendarIcsWarning] = []
    let result = recurrenceToRrule(
      #"{"FREQ":"DAILY","UNTIL":"2026-02-30"}"#, isDateValue: true, warnings: &warnings)
    guard case .failure(let err) = result, case .invalidRecurrenceRule(let msg) = err else {
      XCTFail("expected invalidRecurrenceRule, got \(result)")
      return
    }
    XCTAssertTrue(msg.contains("UNTIL") && msg.contains("2026-02-30"), "got: \(msg)")
  }

  /// RFC 5545 §3.3.10: UNTIL must share DTSTART's value type. A timed event
  /// (UTC DATE-TIME DTSTART) requires a UTC DATE-TIME UNTIL; a date-only event
  /// keeps the bare DATE. `recurrenceToRrule` branches on `isDateValue`.
  func test_recurrenceToRrule_untilMatchesDtstartValueType() {
    var warnings: [CalendarIcsWarning] = []
    let timed = try! recurrenceToRrule(
      #"{"FREQ":"DAILY","UNTIL":"2026-06-30"}"#, isDateValue: false, warnings: &warnings).get()
    XCTAssertEqual(timed, "RRULE:FREQ=DAILY;UNTIL=20260630T235959Z")
    let dateOnly = try! recurrenceToRrule(
      #"{"FREQ":"DAILY","UNTIL":"2026-06-30"}"#, isDateValue: true, warnings: &warnings).get()
    XCTAssertEqual(dateOnly, "RRULE:FREQ=DAILY;UNTIL=20260630")
  }

  func test_exportCalendarIcs_timedEventEmitsUtcDatetimeUntil() {
    var event = sampleEvent()
    event.recurrence = #"{"FREQ":"WEEKLY","UNTIL":"2026-06-30"}"#
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(
      ics.contains("RRULE:FREQ=WEEKLY;UNTIL=20260630T235959Z"), "got:\n\(ics)")
  }

  func test_exportCalendarIcs_allDayEventEmitsBareDateUntil() {
    let res = CalendarIcsEvent.make(CalendarIcsEventFields(
      id: "evt-allday",
      title: "All-day planning",
      description: nil,
      recurrence: #"{"FREQ":"WEEKLY","UNTIL":"2026-06-30"}"#,
      recurrenceExceptions: nil,
      startDate: try! LorvexDate.parse("2026-03-18").get(),
      startTime: nil,
      endDate: nil,
      endTime: nil,
      allDay: true,
      location: nil,
      timezone: nil,
      createdAt: "2026-03-17T08:00:00Z",
      updatedAt: "2026-03-18T08:30:00Z",
      sequence: 0))
    let event = try! res.get()
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(ics.contains("RRULE:FREQ=WEEKLY;UNTIL=20260630"), "got:\n\(ics)")
    XCTAssertFalse(
      ics.contains("UNTIL=20260630T"), "all-day UNTIL must stay a bare DATE; got:\n\(ics)")
  }

  /// West of UTC (America/Los_Angeles, UTC-7 in July): an evening timed
  /// occurrence on the local UNTIL day crosses midnight into the *next* UTC
  /// calendar day. Capping UNTIL at `<untilDay>T235959Z` would exclude that
  /// final occurrence, so UNTIL must be the end of the local UNTIL day
  /// converted to UTC (`20260801T065959Z`), which is ≥ the last occurrence's
  /// UTC instant (`20260801T030000Z` = 2026-07-31 20:00 PDT).
  func test_exportCalendarIcs_timedUntilKeepsFinalOccurrenceWestOfUtc() {
    let res = CalendarIcsEvent.make(CalendarIcsEventFields(
      id: "evt-west",
      title: "Evening standup",
      description: nil,
      recurrence: #"{"FREQ":"DAILY","UNTIL":"2026-07-31"}"#,
      recurrenceExceptions: nil,
      startDate: try! LorvexDate.parse("2026-07-01").get(),
      startTime: try! TimeOfDay.parse("20:00").get(),
      endDate: nil,
      endTime: nil,
      allDay: false,
      location: nil,
      timezone: "America/Los_Angeles",
      createdAt: "2026-06-30T08:00:00Z",
      updatedAt: "2026-06-30T08:30:00Z",
      sequence: 0))
    let event = try! res.get()
    let ics = try! exportCalendarIcs([event]).get()
    // Last occurrence: 2026-07-31 20:00 PDT == 20260801T030000Z (DTSTART time).
    XCTAssertTrue(ics.contains("DTSTART:20260702T030000Z"), "got:\n\(ics)")
    XCTAssertTrue(
      ics.contains("RRULE:FREQ=DAILY;UNTIL=20260801T065959Z"),
      "UNTIL must reach the next UTC day so the final local occurrence survives; got:\n\(ics)")
    // Guard against the regression: the old end-of-UTC-day cap dropped it.
    XCTAssertFalse(ics.contains("UNTIL=20260731T235959Z"), "got:\n\(ics)")
  }

  /// East of UTC (Asia/Tokyo, UTC+9): the last local occurrence
  /// (2026-07-31 20:00 JST == 20260731T110000Z) already falls on the same UTC
  /// day as its local date. UNTIL is the end of the local UNTIL day in UTC
  /// (`20260731T145959Z`) — ≥ the occurrence, but NOT rolled to the next day,
  /// so a blind `+1 day` cap that would add a phantom 2026-08-01 occurrence is
  /// avoided.
  func test_exportCalendarIcs_timedUntilNoPhantomOccurrenceEastOfUtc() {
    let res = CalendarIcsEvent.make(CalendarIcsEventFields(
      id: "evt-east",
      title: "Evening standup",
      description: nil,
      recurrence: #"{"FREQ":"DAILY","UNTIL":"2026-07-31"}"#,
      recurrenceExceptions: nil,
      startDate: try! LorvexDate.parse("2026-07-01").get(),
      startTime: try! TimeOfDay.parse("20:00").get(),
      endDate: nil,
      endTime: nil,
      allDay: false,
      location: nil,
      timezone: "Asia/Tokyo",
      createdAt: "2026-06-30T08:00:00Z",
      updatedAt: "2026-06-30T08:30:00Z",
      sequence: 0))
    let event = try! res.get()
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(ics.contains("DTSTART:20260701T110000Z"), "got:\n\(ics)")
    XCTAssertTrue(
      ics.contains("RRULE:FREQ=DAILY;UNTIL=20260731T145959Z"),
      "UNTIL must stay on the local UNTIL day's UTC instant, not overshoot; got:\n\(ics)")
    XCTAssertFalse(
      ics.contains("UNTIL=20260801"), "east-of-UTC UNTIL must not roll to the next day; got:\n\(ics)")
  }

  /// No timezone: the local wall time is treated as already-UTC (matching
  /// DTSTART emission), so the end-of-day UNTIL renders `YYYYMMDDT235959Z`.
  func test_exportCalendarIcs_timedUntilWithoutTimezoneCapsEndOfUtcDay() {
    var event = sampleEvent()
    event.recurrence = #"{"FREQ":"DAILY","UNTIL":"2026-06-30"}"#
    event.timezone = nil
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(
      ics.contains("RRULE:FREQ=DAILY;UNTIL=20260630T235959Z"), "got:\n\(ics)")
  }

  func test_recurrenceToRrule_emitsBysetposAndWkst() {
    var warnings: [CalendarIcsWarning] = []
    let r = try! recurrenceToRrule(
      #"{"FREQ":"MONTHLY","BYDAY":["MO"],"BYSETPOS":[1],"WKST":"MO"}"#,
      isDateValue: true, warnings: &warnings).get()!
    XCTAssertTrue(r.contains("BYDAY=MO") && r.contains("BYSETPOS=1") && r.contains("WKST=MO"), r)
  }

  func test_recurrenceToRrule_rejectsByhourByminute() {
    var warnings: [CalendarIcsWarning] = []
    let result = recurrenceToRrule(
      #"{"FREQ":"DAILY","BYHOUR":[9,17],"BYMINUTE":[0,30]}"#, isDateValue: true, warnings: &warnings)
    guard case .failure(let err) = result else {
      XCTFail("expected failure")
      return
    }
    XCTAssertTrue("\(err)".contains("BYHOUR"), "got: \(err)")
  }

  func test_recurrenceToRrule_emitsOrdinalByday() {
    var warnings: [CalendarIcsWarning] = []
    let r = try! recurrenceToRrule(
      #"{"FREQ":"MONTHLY","BYDAY":["1MO","-1FR"]}"#, isDateValue: true, warnings: &warnings).get()!
    XCTAssertTrue(r.contains("BYDAY=-1FR,1MO"), r)
  }

  func test_exportCalendarIcs_surfacesBymonthdaySkipWarning() {
    var event = sampleEvent()
    event.recurrence = #"{"FREQ":"MONTHLY","BYMONTHDAY":31}"#
    let (_, warnings) = try! exportCalendarIcsWithWarnings([event]).get()
    XCTAssertEqual(warnings, [.recurrence(.bymonthdaySkipsMonths(day: 31))])
  }

  func test_exportCalendarIcs_rejectsUnknownBydayViaValidator() {
    var event = sampleEvent()
    event.recurrence = #"{"FREQ":"WEEKLY","BYDAY":["XX"]}"#
    let result = exportCalendarIcs([event])
    guard case .failure(let err) = result, case .invalidRecurrenceRule(let msg) = err else {
      XCTFail("expected invalidRecurrenceRule")
      return
    }
    XCTAssertTrue(msg.contains("XX"), "got: \(msg)")
  }

  // MARK: DST

  func test_icsExport_shiftsForwardThroughDstSpringGap() {
    let out = localToUtcIcsTimestamp(
      date: try! LorvexDate.parse("2026-03-08").get(),
      time: try! TimeOfDay.parse("02:30").get(),
      timezone: "America/Los_Angeles")
    XCTAssertEqual(out, "20260308T100000Z")
  }

  func test_icsExport_ambiguousFallBackPicksEarliestOffset() {
    let out = localToUtcIcsTimestamp(
      date: try! LorvexDate.parse("2026-11-01").get(),
      time: try! TimeOfDay.parse("01:30").get(),
      timezone: "America/Los_Angeles")
    XCTAssertEqual(out, "20261101T083000Z")
  }

  // MARK: timestamp parsing

  func test_formatIcsTimestamp_warnsOnNaiveTSeparator() {
    var warnings: [CalendarIcsWarning] = []
    let out = try! formatIcsTimestamp(field: "created_at", raw: "2026-03-08T02:30:00", warnings: &warnings).get()
    XCTAssertEqual(out, "20260308T023000Z")
    XCTAssertEqual(warnings, [.legacyNaiveTimestamp(field: "created_at", value: "2026-03-08T02:30:00")])
  }

  func test_formatIcsTimestamp_warnsOnNaiveSpaceSeparator() {
    var warnings: [CalendarIcsWarning] = []
    let out = try! formatIcsTimestamp(field: "updated_at", raw: "2026-03-08 02:30:00", warnings: &warnings).get()
    XCTAssertEqual(out, "20260308T023000Z")
    XCTAssertEqual(warnings, [.legacyNaiveTimestamp(field: "updated_at", value: "2026-03-08 02:30:00")])
  }

  func test_formatIcsTimestamp_doesNotWarnOnRfc3339() {
    var warnings: [CalendarIcsWarning] = []
    _ = try! formatIcsTimestamp(field: "created_at", raw: "2026-03-08T02:30:00Z", warnings: &warnings).get()
    XCTAssertTrue(warnings.isEmpty)
  }

  func test_formatIcsTimestamp_rejectsPre1900YearTSeparator() {
    var warnings: [CalendarIcsWarning] = []
    let result = formatIcsTimestamp(field: "created_at", raw: "0099-01-01T00:00:00", warnings: &warnings)
    guard case .failure(let err) = result, case .preGregorianTimestampYear(let field, let year) = err else {
      XCTFail("got: \(result)")
      return
    }
    XCTAssertEqual(field, "created_at")
    XCTAssertEqual(year, 99)
  }

  func test_formatIcsTimestamp_rejectsPre1900YearSpaceSeparator() {
    var warnings: [CalendarIcsWarning] = []
    let result = formatIcsTimestamp(field: "updated_at", raw: "1899-12-31 23:59:59", warnings: &warnings)
    guard case .failure(let err) = result, case .preGregorianTimestampYear(let field, let year) = err else {
      XCTFail("got: \(result)")
      return
    }
    XCTAssertEqual(field, "updated_at")
    XCTAssertEqual(year, 1899)
  }

  func test_formatIcsTimestamp_acceptsYear1900AtCutoff() {
    var warnings: [CalendarIcsWarning] = []
    let out = try! formatIcsTimestamp(field: "created_at", raw: "1900-01-01T00:00:00", warnings: &warnings).get()
    XCTAssertEqual(out, "19000101T000000Z")
  }

  // MARK: EXDATE dedupe + cap

  func test_exportCalendarIcs_dedupesExdatesByCanonicalDate() {
    var event = sampleEvent()
    event.recurrence = #"{"FREQ":"WEEKLY"}"#
    event.recurrenceExceptions = #"["2026-03-25","2026-03-25","2026-03-25"]"#
    let ics = try! exportCalendarIcs([event]).get()
    let exdateLines = ics.components(separatedBy: "\r\n").filter { $0.hasPrefix("EXDATE") }.count
    XCTAssertEqual(exdateLines, 1, "got: \(ics)")
  }

  func test_exportCalendarIcs_rejectsOversizeExceptionList() {
    // Build 367 unique dates (one past 366 cap).
    var dates: [String] = []
    for i in 0..<367 {
      let base = LorvexDate(ymd: IsoDate.YMD(year: 2026, month: 1, day: 1))
      var cur = base
      for _ in 0..<i {
        cur = try! nextIcsDate(field: "x", cur).get()
      }
      dates.append(cur.asString)
    }
    let exceptionsJson = "[" + dates.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    var event = sampleEvent()
    event.recurrence = #"{"FREQ":"DAILY"}"#
    event.recurrenceExceptions = exceptionsJson
    let result = exportCalendarIcs([event])
    guard case .failure(let err) = result, case .recurrenceExdateLimitExceeded(let count, let limit) = err else {
      XCTFail("expected RecurrenceExdateLimitExceeded, got: \(result)")
      return
    }
    XCTAssertEqual(count, 367)
    XCTAssertEqual(limit, 366)
  }

  func test_exportCalendarIcs_acceptsExceptionListAtCap() {
    var dates: [String] = []
    let base = LorvexDate(ymd: IsoDate.YMD(year: 2026, month: 1, day: 1))
    var cur = base
    for i in 0..<366 {
      if i > 0 { cur = try! nextIcsDate(field: "x", cur).get() }
      dates.append(cur.asString)
    }
    let exceptionsJson = "[" + dates.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    var event = sampleEvent()
    event.timing = .allDay(start: try! LorvexDate.parse("2026-03-18").get(), end: nil)
    event.recurrence = #"{"FREQ":"DAILY"}"#
    event.recurrenceExceptions = exceptionsJson
    let ics = try! exportCalendarIcs([event]).get()
    // Account for line folding (continuation lines start with space, not EXDATE).
    let exdateLines = ics.split(separator: "\r\n").filter { $0.hasPrefix("EXDATE") }.count
    XCTAssertEqual(exdateLines, 366)
  }

  // MARK: EXDATE shape parity with DTSTART

  func test_exportCalendarIcs_exdateIsTimedWhenStartTimeIsPresentAndNotAllDay() {
    var event = sampleEvent()
    event.timezone = "America/New_York"
    event.recurrence = #"{"FREQ":"WEEKLY"}"#
    event.recurrenceExceptions = #"["2026-03-25"]"#
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(ics.contains("EXDATE:20260325T133000Z"), "got: \(ics)")
  }

  // MARK: bidi / zero-width stripping

  func test_exportCalendarIcs_stripsBidiAndZeroWidthCodepoints() {
    var event = sampleEvent()
    event.title = "paypal\u{202E}moc"
    event.description = "ad\u{200B}min\u{2060}note"
    event.location = "\u{FEFF}Office\u{200E}"
    let ics = try! exportCalendarIcs([event]).get()
    XCTAssertTrue(ics.contains("SUMMARY:paypalmoc"), ics)
    XCTAssertTrue(ics.contains("DESCRIPTION:adminnote"), ics)
    XCTAssertTrue(ics.contains("LOCATION:Office"), ics)
    let dangerous: [Unicode.Scalar] = [
      "\u{202E}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{200B}",
      "\u{200C}", "\u{200D}", "\u{200E}", "\u{200F}", "\u{2060}", "\u{FEFF}",
      "\u{2028}", "\u{2029}",
    ]
    for cp in dangerous {
      XCTAssertFalse(ics.unicodeScalars.contains(cp), "U+\(String(cp.value, radix: 16))")
    }
  }

  // MARK: line folding

  func test_foldLine_multibyteUtf8NotCorrupted() {
    let title = "\u{8FD9}\u{662F}\u{4E00}\u{4E2A}\u{975E}\u{5E38}\u{957F}\u{7684}\u{4E2D}\u{6587}\u{65E5}\u{5386}\u{4E8B}\u{4EF6}\u{6807}\u{9898}\u{9700}\u{8981}\u{8D85}\u{8FC7}\u{4E03}\u{5341}\u{4E94}"
    let line = "SUMMARY:\(title)"
    let folded = foldLine(line)
    XCTAssertEqual(folded.replacingOccurrences(of: "\r\n ", with: ""), line)
    let parts = folded.components(separatedBy: "\r\n")
    for (index, part) in parts.enumerated() {
      XCTAssertLessThanOrEqual(part.utf8.count, 75)
      if index > 0 {
        XCTAssertTrue(part.hasPrefix(" "))
      }
    }
  }

  // MARK: next_date overflow safety

  func test_nextDate_succeedsAtYear9999WithoutPanic() {
    let date = LorvexDate(ymd: IsoDate.YMD(year: 9999, month: 12, day: 31))
    let next = try! nextIcsDate(field: "end_date", date).get()
    XCTAssertEqual(next.ymd.year, 10000)
    XCTAssertEqual(next.ymd.month, 1)
    XCTAssertEqual(next.ymd.day, 1)
  }
}
