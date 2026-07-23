import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Tests for the calendar_event workflow subtree (create / update / load /
/// attendees / recurrence_skeleton) plus the calendar_normalization driver.
/// Ports the inline Rust tests from
/// `apps/tauri/lorvex-workflow/src/calendar_event/{tests,attendees,recurrence_skeleton}.rs`
/// and `apps/tauri/lorvex-workflow/src/calendar_normalization/tests.rs`.
final class CalendarEventTests: XCTestCase {

  // MARK: - HLC + store helpers

  private final class CountingHlcHandle: HlcDominatingStateHandle, @unchecked Sendable {
    private var counter: UInt64 = 0
    private let state = try! HlcState(deviceSuffix: "abcdef0123456789")

    func generate() -> Hlc {
      defer { counter += 1 }
      return state.generate(withPhysicalMs: counter)
    }

    func generate(dominating floor: Hlc?) -> Hlc {
      if let floor {
        state.updateOnReceive(remote: floor, physicalMs: counter)
      }
      return generate()
    }
  }
  private func makeSession() -> HlcSession { HlcSession(handle: CountingHlcHandle()) }

  private func freshStore() throws -> LorvexStore {
    try WorkflowTestSupport.freshStore()
  }

  private func existingFields(_ row: CalendarEventRow) -> CalendarUpdateExisting {
    CalendarUpdateExisting(
      startDate: row.startDate.asString,
      startTime: row.startTime?.asString,
      endDate: row.endDate?.asString,
      endTime: row.endTime?.asString,
      allDay: row.allDay,
      timezone: row.timezone,
      recurrence: row.recurrence)
  }

  // MARK: - Fixtures

  private func createInput() -> CalendarCreateInput {
    CalendarCreateInput(
      title: "Team sync", recurrence: nil,
      timezone: "America/New_York",
      startDate: "2026-05-01", startTime: "09:00",
      endDate: nil, endTime: "10:00", allDay: nil,
      description: nil, location: nil, url: nil, color: nil,
      eventType: nil, personName: nil)
  }

  private func updateInput() -> CalendarUpdateInput {
    CalendarUpdateInput()
  }

  private func existingFixture() -> CalendarUpdateExisting {
    CalendarUpdateExisting(
      startDate: "2026-05-01", startTime: "09:00",
      endDate: nil, endTime: "10:00", allDay: false,
      timezone: "America/New_York")
  }

  // MARK: - calendar_normalization create tests

  func testCreateRejectsEmptyTitleAfterUnicodeHygiene() {
    var input = createInput()
    input.title = "\u{200B}\u{202E}   "
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarCreate(input)) {
      error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("title must not be empty"), msg)
    }
  }

  func testCreateTrimsAndCanonicalizesAllowedURL() throws {
    var input = createInput()
    input.url = "  HTTPS://Example.com/Path  "
    let normalized = try CalendarNormalization.normalizeCalendarCreate(input)
    XCTAssertEqual(normalized.url, "https://Example.com/Path")
  }

  func testCreateRejectsDisallowedURLScheme() {
    var input = createInput()
    input.url = "javascript:alert(1)"
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarCreate(input)) {
      error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("scheme"), msg)
    }
  }

  func testCreateRejectsInvalidTimezone() {
    var input = createInput()
    input.timezone = "America/Not_A_Zone"
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarCreate(input)) {
      error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("timezone"), msg)
    }
  }

  func testCreateAllDayClearsTimes() throws {
    var input = createInput()
    input.allDay = true
    let normalized = try CalendarNormalization.normalizeCalendarCreate(input)
    XCTAssertTrue(normalized.allDay)
    XCTAssertNil(normalized.startTime)
    XCTAssertNil(normalized.endTime)
  }

  func testCreateInjectsBymonthdayForMonthlyAnchor() throws {
    var input = createInput()
    input.startDate = "2026-01-15"
    input.recurrence = #"{"FREQ":"MONTHLY","INTERVAL":1}"#
    let normalized = try CalendarNormalization.normalizeCalendarCreate(input)
    XCTAssertEqual(
      normalized.recurrence,
      #"{"BYMONTHDAY":[15],"FREQ":"MONTHLY","INTERVAL":1}"#)
  }

  func testCreateInjectsNegativeBymonthdayForMonthEndAnchor() throws {
    // R-3 (B): a month-end start anchor injects BYMONTHDAY=-1 (count-from-end),
    // not a positive day that would skip short months. This is the stored,
    // synced canonical rule — RFC-faithful and round-trips through ICS/EventKit.
    var input = createInput()
    input.startDate = "2026-01-31"
    input.recurrence = #"{"FREQ":"MONTHLY","INTERVAL":1}"#
    let normalized = try CalendarNormalization.normalizeCalendarCreate(input)
    XCTAssertEqual(
      normalized.recurrence,
      #"{"BYMONTHDAY":[-1],"FREQ":"MONTHLY","INTERVAL":1}"#)
  }

  func testCreateRejectsEndDateBeforeStartDate() {
    var input = createInput()
    input.endDate = "2026-04-30"
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarCreate(input)) {
      error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("end_date"), msg)
    }
  }

  func testCreateRejectsSameDayEndTimeBeforeStartTime() {
    var input = createInput()
    input.endTime = "08:00"
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarCreate(input)) {
      error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("end_time"), msg)
    }
  }

  func testCreateAcceptsZeroDurationTimedEvent() throws {
    var input = createInput()
    input.endTime = input.startTime
    let normalized = try CalendarNormalization.normalizeCalendarCreate(input)
    XCTAssertEqual(normalized.startTime, normalized.endTime)
  }

  func testCreateRejectsDstGap() {
    var input = createInput()
    input.startDate = "2026-03-08"
    input.startTime = "02:30"
    input.endTime = "03:30"
    XCTAssertThrowsError(try CalendarNormalization.normalizeCalendarCreate(input)) {
      error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("does not exist"), msg)
    }
  }

  func testCreateAcceptsDstAmbiguityWithWarningPayload() throws {
    var input = createInput()
    input.startDate = "2026-11-01"
    input.startTime = "01:30"
    input.endTime = "02:30"
    let normalized = try CalendarNormalization.normalizeCalendarCreate(input)
    guard case .ambiguous(let wallClock, let tz) = normalized.dstGuard else {
      return XCTFail("expected ambiguous DST guard, got \(normalized.dstGuard)")
    }
    XCTAssertEqual(wallClock, "2026-11-01 01:30")
    XCTAssertEqual(tz, "America/New_York")
  }

  // MARK: - calendar_normalization update tests

  func testUpdateNormalizesPatchesAndEffectiveFields() throws {
    var input = updateInput()
    input.title = "  Planning  "
    input.url = .set("MAILTO:team@example.com")
    input.timezone = .clear
    input.endTime = .clear
    let normalized = try CalendarNormalization.normalizeCalendarUpdate(
      input, existing: existingFixture())
    XCTAssertEqual(normalized.title, "Planning")
    XCTAssertEqual(normalized.url, .set("mailto:team@example.com"))
    XCTAssertEqual(normalized.timezone, .clear)
    XCTAssertEqual(normalized.endTime, .clear)
    XCTAssertNil(normalized.effective.timezone)
    XCTAssertNil(normalized.effective.endTime)
  }

  func testUpdateAllDayForcesTimeClears() throws {
    var input = updateInput()
    input.allDay = true
    let normalized = try CalendarNormalization.normalizeCalendarUpdate(
      input, existing: existingFixture())
    XCTAssertEqual(normalized.startTime, .clear)
    XCTAssertEqual(normalized.endTime, .clear)
    XCTAssertNil(normalized.effective.startTime)
    XCTAssertNil(normalized.effective.endTime)
  }

  func testUpdateRejectsDstGapAgainstEffectiveTimezone() {
    var input = updateInput()
    input.startDate = "2026-03-08"
    input.startTime = .set("02:30")
    XCTAssertThrowsError(
      try CalendarNormalization.normalizeCalendarUpdate(input, existing: existingFixture())
    ) { error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("does not exist"), msg)
    }
  }

  // MARK: - L8: start_date change re-normalizes recurrence to the new anchor

  func testUpdateReanchorsAutoInjectedBymonthdayOnStartDateChange() throws {
    // A monthly series created bare on Feb-28 (common) stores BYMONTHDAY=[28].
    // Moving its start to Jan-31 re-derives the auto-injected anchor day to [-1],
    // identical to creating the series at Jan-31 — the stale 28th is not kept.
    let existing = CalendarUpdateExisting(
      startDate: "2025-02-28", allDay: true,
      recurrence: #"{"BYMONTHDAY":[28],"FREQ":"MONTHLY","INTERVAL":1}"#)
    var input = updateInput()
    input.startDate = "2026-01-31"  // recurrence patch left .unset
    let normalized = try CalendarNormalization.normalizeCalendarUpdate(input, existing: existing)
    XCTAssertEqual(
      normalized.recurrence, .set(#"{"BYMONTHDAY":[-1],"FREQ":"MONTHLY","INTERVAL":1}"#))

    // Parity with create-at-that-anchor: creating a bare monthly at Jan-31 yields
    // the same rule the re-anchor produced.
    var create = createInput()
    create.startDate = "2026-01-31"
    create.startTime = nil
    create.endTime = nil
    create.allDay = true
    create.recurrence = #"{"FREQ":"MONTHLY","INTERVAL":1}"#
    let created = try CalendarNormalization.normalizeCalendarCreate(create)
    XCTAssertEqual(created.recurrence, #"{"BYMONTHDAY":[-1],"FREQ":"MONTHLY","INTERVAL":1}"#)
  }

  func testUpdatePreservesExplicitBymonthdayOnStartDateChange() throws {
    // The stored [1] does not match the old anchor's auto-injected day (the 5th
    // → [5]), so it is an explicit choice and survives a start_date move.
    let existing = CalendarUpdateExisting(
      startDate: "2026-01-05", allDay: true,
      recurrence: #"{"BYMONTHDAY":[1],"FREQ":"MONTHLY","INTERVAL":1}"#)
    var input = updateInput()
    input.startDate = "2026-02-10"
    let normalized = try CalendarNormalization.normalizeCalendarUpdate(input, existing: existing)
    XCTAssertEqual(
      normalized.recurrence, .set(#"{"BYMONTHDAY":[1],"FREQ":"MONTHLY","INTERVAL":1}"#))
  }

  func testUpdateRevalidatesWeeklyBydayAgainstNewStartDate() throws {
    // Moving a WEEKLY(BYDAY=[MO]) series' start from Monday to Wednesday must be
    // rejected — exactly as create-time rejects a Wednesday start with BYDAY=[MO].
    let existing = CalendarUpdateExisting(
      startDate: "2026-01-05", allDay: true,  // Monday
      recurrence: #"{"BYDAY":["MO"],"FREQ":"WEEKLY","INTERVAL":1}"#)
    var input = updateInput()
    input.startDate = "2026-01-07"  // Wednesday
    XCTAssertThrowsError(
      try CalendarNormalization.normalizeCalendarUpdate(input, existing: existing)
    ) { error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("BYDAY"), msg)
    }
  }

  func testUpdateLeavesRecurrenceUnsetWhenStartDateUnchanged() throws {
    // No start_date edit (or a same-value re-anchor) leaves the stored rule and
    // its EXDATE skeleton alone — the recurrence patch stays .unset.
    let existing = CalendarUpdateExisting(
      startDate: "2025-02-28", allDay: true,
      recurrence: #"{"BYMONTHDAY":[28],"FREQ":"MONTHLY","INTERVAL":1}"#)
    var input = updateInput()
    input.title = "Renamed"
    let normalized = try CalendarNormalization.normalizeCalendarUpdate(input, existing: existing)
    XCTAssertEqual(normalized.recurrence, .unset)
  }

  // MARK: - recurrence_skeleton tests

  func testSkeletonMatchesWhenOnlyUntilDiffers() {
    let a = #"{"FREQ":"WEEKLY","INTERVAL":1,"UNTIL":"2026-06-01"}"#
    let b = #"{"FREQ":"WEEKLY","INTERVAL":1,"UNTIL":"2027-01-01"}"#
    XCTAssertTrue(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  func testSkeletonDiffersWhenBydayChanges() {
    let a = #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"]}"#
    let b = #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["TU"]}"#
    XCTAssertFalse(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  func testSkeletonInvalidJsonDropsExdate() {
    XCTAssertFalse(
      CalendarEventRecurrence.recurrenceSkeletonMatches("not json", "not json"))
  }

  func testSkeletonDiffersWhenByhourChanges() {
    let a = #"{"FREQ":"WEEKLY","INTERVAL":1,"BYHOUR":[9]}"#
    let b = #"{"FREQ":"WEEKLY","INTERVAL":1,"BYHOUR":[10]}"#
    XCTAssertFalse(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  func testSkeletonDiffersWhenByminuteChanges() {
    let a = #"{"FREQ":"DAILY","INTERVAL":1,"BYMINUTE":[0]}"#
    let b = #"{"FREQ":"DAILY","INTERVAL":1,"BYMINUTE":[30]}"#
    XCTAssertFalse(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  func testSkeletonDiffersWhenBysecondChanges() {
    let a = #"{"FREQ":"DAILY","INTERVAL":1,"BYSECOND":[0]}"#
    let b = #"{"FREQ":"DAILY","INTERVAL":1,"BYSECOND":[15]}"#
    XCTAssertFalse(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  func testSkeletonMatchesWhenBydayReordered() {
    let a = #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","TU","WE"]}"#
    let b = #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["WE","MO","TU"]}"#
    XCTAssertTrue(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  func testSkeletonMatchesWhenBymonthReorderedAndDeduped() {
    let a = #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[1,3,6,6]}"#
    let b = #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[6,3,1]}"#
    XCTAssertTrue(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  func testSkeletonMatchesWhenByhourReordered() {
    let a = #"{"FREQ":"DAILY","INTERVAL":1,"BYHOUR":[9,17]}"#
    let b = #"{"FREQ":"DAILY","INTERVAL":1,"BYHOUR":[17,9]}"#
    XCTAssertTrue(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  func testCanonicalNormalizerRejectsRdateSoSkeletonCanIgnoreIt() {
    let result = ValidationRecurrence.normalizeCalendarRecurrence(
      #"{"FREQ":"WEEKLY","INTERVAL":1,"RDATE":["2026-05-04"]}"#)
    guard case .failure(let err) = result else {
      return XCTFail("RDATE must be rejected by the canonical normalizer")
    }
    let m = err.description
    XCTAssertTrue(
      m.contains("RDATE") || m.lowercased().contains("unknown"),
      "error should mention RDATE / unknown key: \(m)")
  }

  func testSkeletonStillDiffersWhenBydayActuallyChanges() {
    let a = #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","TU"]}"#
    let b = #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE"]}"#
    XCTAssertFalse(CalendarEventRecurrence.recurrenceSkeletonMatches(a, b))
  }

  // MARK: - is_anchor_shift tests (calendar_event/tests.rs)

  func testStartTimePatchSetWithSameValueIsNotShift() {
    let shifted = CalendarEventUpdate.isAnchorShift(
      normalizedStartTime: .set("09:00"),
      beforeStartTime: "09:00",
      normalizedStartDate: nil,
      beforeStartDate: "2026-01-01")
    XCTAssertFalse(shifted)
  }

  func testStartTimePatchSetWithDifferentValueIsShift() {
    let shifted = CalendarEventUpdate.isAnchorShift(
      normalizedStartTime: .set("10:00"),
      beforeStartTime: "09:00",
      normalizedStartDate: nil,
      beforeStartDate: "2026-01-01")
    XCTAssertTrue(shifted)
  }

  func testStartDatePatchSetWithDifferentValueIsShift() {
    let shifted = CalendarEventUpdate.isAnchorShift(
      normalizedStartTime: .unset,
      beforeStartTime: "09:00",
      normalizedStartDate: "2026-01-07",
      beforeStartDate: "2026-01-01")
    XCTAssertTrue(shifted)
  }

  func testStartDatePatchSetWithSameValueIsNotShift() {
    let shifted = CalendarEventUpdate.isAnchorShift(
      normalizedStartTime: .unset,
      beforeStartTime: "09:00",
      normalizedStartDate: "2026-01-01",
      beforeStartDate: "2026-01-01")
    XCTAssertFalse(shifted)
  }

  func testStartDatePatchUnsetIsNotShift() {
    let shifted = CalendarEventUpdate.isAnchorShift(
      normalizedStartTime: .unset,
      beforeStartTime: "09:00",
      normalizedStartDate: nil,
      beforeStartDate: "2026-01-01")
    XCTAssertFalse(shifted)
  }

  // MARK: - attendees serialization tests

  func testSerializeEmptyListReturnsNil() throws {
    XCTAssertNil(try CalendarEventAttendees.serialize([]))
  }

  func testSerializeNameOnlyAttendee() throws {
    // Empty email + a name is accepted: it serializes with an empty email string
    // (the deserializer treats "" as absent).
    let json = try XCTUnwrap(
      try CalendarEventAttendees.serialize(
        [CalendarAttendeeInput(email: "   ", name: "Anon")]))
    XCTAssertEqual(
      JSONValue.parse(json), .array([.object(["email": .string(""), "name": .string("Anon")])]))
  }

  func testSerializeCapsAttendeeCountAtTheBudgetBound() throws {
    let atCap = (1...PayloadByteBudget.maxCalendarAttendees).map {
      CalendarAttendeeInput(email: "a\($0)@example.com")
    }
    XCTAssertNotNil(try CalendarEventAttendees.serialize(atCap), "the cap itself must pass")

    let overCap = atCap + [CalendarAttendeeInput(email: "one-too-many@example.com")]
    XCTAssertThrowsError(try CalendarEventAttendees.serialize(overCap)) { error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("at most"), "error must state the cap; got \(msg)")
    }
  }

  func testSerializeCapsAttendeeFieldLengthAtTheBudgetBound() throws {
    let atCap = String(repeating: "n", count: PayloadByteBudget.maxAttendeeFieldLength)
    XCTAssertNotNil(
      try CalendarEventAttendees.serialize([CalendarAttendeeInput(email: "", name: atCap)]))

    let overCap = atCap + "n"
    XCTAssertThrowsError(
      try CalendarEventAttendees.serialize([CalendarAttendeeInput(email: "", name: overCap)])
    ) { error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(msg.contains("maximum length"), "error must state the cap; got \(msg)")
    }
  }

  func testSerializeFullyEmptyAttendeeIsRejected() throws {
    XCTAssertThrowsError(
      try CalendarEventAttendees.serialize([CalendarAttendeeInput(email: "   ", name: "   ")])
    ) { error in
      guard case CalendarEventOpError.validation(let msg) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(
        msg.contains("email or a name"), "error must explain the requirement; got \(msg)")
    }
  }

  func testSerializeKeepsDuplicateAndDistinctEntriesVerbatim() throws {
    // Attendees are a plain annotation, not a keyed set: duplicates and distinct
    // entries alike are preserved in order (no identity dedup).
    let json = try XCTUnwrap(
      try CalendarEventAttendees.serialize([
        CalendarAttendeeInput(email: "alice@example.com", name: "Alice"),
        CalendarAttendeeInput(email: "alice@example.com", name: "Alice (work)"),
        CalendarAttendeeInput(email: "bob@example.com", name: "Bob"),
      ]))
    guard case .array(let items) = try XCTUnwrap(JSONValue.parse(json)) else {
      return XCTFail("serialized attendees must be a JSON array")
    }
    XCTAssertEqual(items.count, 3, "every entry is preserved verbatim")
  }

  // MARK: - End-to-end create + update + load smoke tests

  func testCreateCalendarEventPersistsRowAndAttendees() throws {
    let store = try freshStore()
    let session = makeSession()
    let result = try store.writer.write { db in
      try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: "evt-smoke-1",
        input: CalendarEventCreateInput(
          title: "Demo", startDate: "2026-05-01", startTime: "09:00",
          endTime: "10:00", allDay: false,
          attendees: [
            CalendarAttendeeInput(email: "ada@example.com", name: "Ada")
          ]))
    }
    XCTAssertEqual(result.eventId, "evt-smoke-1")
    XCTAssertEqual(result.summary, "Created calendar event 'Demo'")
    guard case .object(let obj) = result.event else {
      return XCTFail("event must be object")
    }
    XCTAssertEqual(obj["title"], .string("Demo"))
    XCTAssertEqual(obj["all_day"], .bool(false))
    guard case .array(let atts) = obj["attendees"] ?? .null else {
      return XCTFail("attendees must be array")
    }
    XCTAssertEqual(atts.count, 1)
  }

  func testUpdateCalendarEventTitleUpdatesRowAndBumpsVersion() throws {
    let store = try freshStore()
    let session = makeSession()
    _ = try store.writer.write { db in
      try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: "evt-upd-1",
        input: CalendarEventCreateInput(
          title: "First", startDate: "2026-05-01",
          startTime: "09:00", endTime: "10:00", allDay: false))
    }
    let result = try store.writer.write { db in
      let before = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: "evt-upd-1")!
      let existing = CalendarUpdateExisting(
        startDate: "2026-05-01", startTime: "09:00", endDate: nil,
        endTime: "10:00", allDay: false, timezone: nil)
      return try CalendarEventUpdate.updateCalendarEvent(
        db, hlc: session,
        input: CalendarEventUpdateInput(id: "evt-upd-1", title: "Second"),
        before: before, beforeRecurrence: nil, existing: existing)
    }
    XCTAssertEqual(result.summary, "Updated calendar event 'Second'")
    guard case .object(let obj) = result.event else {
      return XCTFail("event must be object")
    }
    XCTAssertEqual(obj["title"], .string("Second"))
  }

  func testTitleOnlyUpdateAdvancesOnlyContentRegister() throws {
    let store = try freshStore()
    let session = makeSession()
    try store.writer.write { db in
      _ = try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: "content-only",
        input: CalendarEventCreateInput(
          title: "First", startDate: "2026-05-01",
          startTime: "09:00", endTime: "10:00", allDay: false))
      let before = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: "content-only"))
      _ = try CalendarEventUpdate.updateCalendarEvent(
        db, hlc: session,
        input: CalendarEventUpdateInput(id: before.id, title: "Second"),
        before: try XCTUnwrap(
          CalendarEventLoad.loadCalendarEventJSON(db, eventId: before.id)),
        beforeRecurrence: before.recurrence,
        existing: existingFields(before))
      let after = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: before.id))

      XCTAssertGreaterThan(try XCTUnwrap(after.contentVersion), try XCTUnwrap(before.contentVersion))
      XCTAssertEqual(after.recurrenceTopologyVersion, before.recurrenceTopologyVersion)
      XCTAssertEqual(after.version, after.contentVersion)
    }
  }

  func testTimeOnlyUpdateAdvancesOnlyTopologyRegister() throws {
    let store = try freshStore()
    let session = makeSession()
    try store.writer.write { db in
      _ = try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: "topology-only",
        input: CalendarEventCreateInput(
          title: "Focus", startDate: "2026-05-01",
          startTime: "09:00", endTime: "10:00", allDay: false))
      let before = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: "topology-only"))
      _ = try CalendarEventUpdate.updateCalendarEvent(
        db, hlc: session,
        input: CalendarEventUpdateInput(id: before.id, startTime: .set("09:30")),
        before: try XCTUnwrap(
          CalendarEventLoad.loadCalendarEventJSON(db, eventId: before.id)),
        beforeRecurrence: before.recurrence,
        existing: existingFields(before))
      let after = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: before.id))

      XCTAssertEqual(after.contentVersion, before.contentVersion)
      XCTAssertGreaterThan(
        try XCTUnwrap(after.recurrenceTopologyVersion),
        try XCTUnwrap(before.recurrenceTopologyVersion))
      XCTAssertEqual(after.version, after.recurrenceTopologyVersion)
    }
  }

  func testMixedUpdateAdvancesBothRegistersTogether() throws {
    let store = try freshStore()
    let session = makeSession()
    try store.writer.write { db in
      _ = try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: "mixed",
        input: CalendarEventCreateInput(
          title: "Focus", startDate: "2026-05-01",
          startTime: "09:00", endTime: "10:00", allDay: false))
      let before = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: "mixed"))
      _ = try CalendarEventUpdate.updateCalendarEvent(
        db, hlc: session,
        input: CalendarEventUpdateInput(
          id: before.id, title: "Deep focus", startTime: .set("09:30")),
        before: try XCTUnwrap(
          CalendarEventLoad.loadCalendarEventJSON(db, eventId: before.id)),
        beforeRecurrence: before.recurrence,
        existing: existingFields(before))
      let after = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: before.id))

      XCTAssertGreaterThan(try XCTUnwrap(after.contentVersion), try XCTUnwrap(before.contentVersion))
      XCTAssertGreaterThan(
        try XCTUnwrap(after.recurrenceTopologyVersion),
        try XCTUnwrap(before.recurrenceTopologyVersion))
      XCTAssertEqual(after.contentVersion, after.recurrenceTopologyVersion)
      XCTAssertEqual(after.version, after.contentVersion)
    }
  }

  func testExplicitDecisionResetAdvancesGenerationAndTopologyForMetadataEdit() throws {
    let store = try freshStore()
    let session = makeSession()
    try store.writer.write { db in
      _ = try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: "reset",
        input: CalendarEventCreateInput(
          title: "Daily", recurrence: #"{"FREQ":"DAILY"}"#,
          startDate: "2026-05-01", startTime: "09:00",
          endTime: "10:00", allDay: false))
      let before = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: "reset"))
      _ = try CalendarEventUpdate.updateCalendarEvent(
        db, hlc: session,
        input: CalendarEventUpdateInput(
          id: before.id, title: "Renamed daily", resetOccurrenceDecisions: true),
        before: try XCTUnwrap(
          CalendarEventLoad.loadCalendarEventJSON(db, eventId: before.id)),
        beforeRecurrence: before.recurrence,
        existing: existingFields(before))
      let after = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: before.id))

      XCTAssertGreaterThan(
        try XCTUnwrap(after.recurrenceGeneration),
        try XCTUnwrap(before.recurrenceGeneration))
      XCTAssertGreaterThan(
        try XCTUnwrap(after.recurrenceTopologyVersion),
        try XCTUnwrap(before.recurrenceTopologyVersion))
      XCTAssertEqual(after.recurrenceGeneration, after.version)
      XCTAssertEqual(after.recurrenceTopologyVersion, after.version)
      XCTAssertEqual(after.contentVersion, after.version)
    }
  }

  func testDecisionEditAdvancesWholeRowWithoutGroupRegisters() throws {
    let store = try freshStore()
    let session = makeSession()
    let masterID = "decision-master"
    let occurrenceDate = "2026-05-02"
    try store.writer.write { db in
      _ = try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: masterID,
        input: CalendarEventCreateInput(
          title: "Daily", recurrence: #"{"FREQ":"DAILY"}"#,
          startDate: "2026-05-01", startTime: "09:00",
          endTime: "10:00", allDay: false))
      let master = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: masterID))
      let generation = try XCTUnwrap(master.recurrenceGeneration)
      let decisionID = CalendarOccurrenceDecisionID.make(
        seriesId: masterID, recurrenceGeneration: generation,
        recurrenceInstanceDate: occurrenceDate)
      _ = try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: decisionID,
        input: CalendarEventCreateInput(
          title: "Moved", startDate: occurrenceDate, startTime: "11:00",
          endTime: "12:00", allDay: false, seriesId: masterID,
          recurrenceInstanceDate: occurrenceDate,
          occurrenceState: .replacement, recurrenceGeneration: generation))
      let before = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: decisionID))
      _ = try CalendarEventUpdate.updateCalendarEvent(
        db, hlc: session,
        input: CalendarEventUpdateInput(id: decisionID, title: "Moved again"),
        before: try XCTUnwrap(
          CalendarEventLoad.loadCalendarEventJSON(db, eventId: decisionID)),
        beforeRecurrence: before.recurrence,
        existing: existingFields(before))
      let after = try XCTUnwrap(
        CalendarTimelineQueries.getStoredCalendarEvent(db, id: decisionID))

      XCTAssertGreaterThan(after.version, before.version)
      XCTAssertNil(after.contentVersion)
      XCTAssertNil(after.recurrenceTopologyVersion)
    }
  }

  func testUpdateStartDateClearIsRejected() throws {
    let store = try freshStore()
    let session = makeSession()
    _ = try store.writer.write { db in
      try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: "evt-clear-1",
        input: CalendarEventCreateInput(
          title: "T", startDate: "2026-05-01",
          startTime: "09:00", endTime: "10:00", allDay: false))
    }
    do {
      try store.writer.write { db in
        let before = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: "evt-clear-1")!
        let existing = CalendarUpdateExisting(
          startDate: "2026-05-01", startTime: "09:00", endDate: nil,
          endTime: "10:00", allDay: false, timezone: nil)
        _ = try CalendarEventUpdate.updateCalendarEvent(
          db, hlc: session,
          input: CalendarEventUpdateInput(id: "evt-clear-1", startDate: .clear),
          before: before, beforeRecurrence: nil, existing: existing)
      }
      XCTFail("clear on start_date must reject")
    } catch let error as CalendarEventOpError {
      guard case .validation(let m) = error else {
        return XCTFail("expected validation error, got \(error)")
      }
      XCTAssertTrue(m.contains("start_date cannot be cleared"), m)
    }
  }

  func testCreateRejectsRecurringSingleOccurrenceOverrideBeforeInsert() throws {
    let store = try freshStore()
    let session = makeSession()

    XCTAssertThrowsError(
      try store.writer.write { db in
        try CalendarEventCreate.createCalendarEvent(
          db, hlc: session, eventId: "evt-invalid-override",
          input: CalendarEventCreateInput(
            title: "Invalid override",
            recurrence: #"{"FREQ":"DAILY"}"#,
            startDate: "2026-08-10",
            startTime: "09:00",
            allDay: false,
            seriesId: "master-1",
            recurrenceInstanceDate: "2026-08-10"))
      }
    ) { error in
      XCTAssertTrue(String(describing: error).contains("must not carry recurrence"))
    }

    let count = try store.writer.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM calendar_events WHERE id = ?",
        arguments: ["evt-invalid-override"])
    }
    XCTAssertEqual(count, 0)
  }

  func testUpdateRejectsAddingRecurrenceToOverrideWithoutChangingRow() throws {
    let store = try freshStore()
    let session = makeSession()
    let seriesId = "master-1"
    let generation = "1711234599000_0000_dec0000200000002"
    let occurrenceDate = "2026-08-10"
    let decisionId = CalendarOccurrenceDecisionID.make(
      seriesId: seriesId,
      recurrenceGeneration: generation,
      recurrenceInstanceDate: occurrenceDate)
    try store.writer.write { db in
      _ = try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: seriesId,
        input: CalendarEventCreateInput(
          title: "Daily series",
          recurrence: #"{"FREQ":"DAILY"}"#,
          startDate: occurrenceDate,
          startTime: "09:00",
          allDay: false,
          recurrenceGeneration: generation))
      _ = try CalendarEventCreate.createCalendarEvent(
        db, hlc: session, eventId: decisionId,
        input: CalendarEventCreateInput(
          title: "Valid override",
          startDate: occurrenceDate,
          startTime: "09:00",
          allDay: false,
          seriesId: seriesId,
          recurrenceInstanceDate: occurrenceDate,
          occurrenceState: .replacement,
          recurrenceGeneration: generation))
    }
    let before = try store.writer.read { db in
      try XCTUnwrap(CalendarTimelineQueries.getCalendarEvent(db, id: decisionId))
    }

    XCTAssertThrowsError(
      try store.writer.write { db in
        let beforeJSON = try XCTUnwrap(
          CalendarEventLoad.loadCalendarEventJSON(db, eventId: decisionId))
        let existing = CalendarUpdateExisting(
          startDate: before.startDate.asString,
          startTime: before.startTime?.asString,
          endDate: before.endDate?.asString,
          endTime: before.endTime?.asString,
          allDay: before.allDay,
          timezone: before.timezone,
          recurrence: before.recurrence)
        _ = try CalendarEventUpdate.updateCalendarEvent(
          db,
          hlc: session,
          input: CalendarEventUpdateInput(
            id: decisionId,
            recurrence: .set(#"{"FREQ":"DAILY"}"#)),
          before: beforeJSON,
          beforeRecurrence: before.recurrence,
          existing: existing)
      }
    ) { error in
      XCTAssertTrue(String(describing: error).contains("must not carry recurrence"))
    }

    let after = try store.writer.read { db in
      try XCTUnwrap(CalendarTimelineQueries.getCalendarEvent(db, id: decisionId))
    }
    XCTAssertNil(after.recurrence)
    XCTAssertEqual(after.version, before.version)
  }
}
