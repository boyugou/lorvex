import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Event search finds titles and locations written with other accents, case,
/// or letter variants than the query when the FTS index finds nothing, and
/// reaches events in scripts without word spaces; the provider mirror search
/// compares folded text on both sides.
final class CalendarSearchFoldTests: XCTestCase {

  private func insertEvent(
    _ db: Database, _ id: String, _ title: String, location: String? = nil,
    description: String? = nil
  ) throws {
    try CalendarEventWriteRepo.createCalendarEvent(
      db,
      params: CalendarEventCreateParams(
        id: id, title: title, description: description, timezone: "UTC",
        startDate: "2026-09-10", startTime: "10:00", endDate: "2026-09-10", endTime: "11:00",
        allDay: false, location: location, eventType: "event",
        seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
        recurrenceGeneration: nil,
        recurrenceTopologyVersion: "0000000000000_0000_0000000000000000",
        version: "0000000000000_0000_0000000000000000", now: "2026-09-01T00:00:00Z"))
  }

  private func found(_ store: LorvexStore, _ query: String) throws -> [String] {
    try store.writer.read { db in
      try CalendarTimelineQueries.searchCalendarEvents(
        db, predicate: CalendarSearchPredicate(query: query), limit: 10
      ).map(\.id)
    }
  }

  func testEventSearchFindsTitlesAndLocationsTypedWithOtherLettersOrCase() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEvent(db, "pl", "Spotkanie w Łodzi", location: "Biuro")
      try self.insertEvent(db, "ru", "Встреча: всё ещё в силе", location: "Офис")
      try self.insertEvent(db, "tr", "Weekly sync", location: "Işık Plaza")
      try self.insertEvent(db, "vi", "Cuộc họp đội", location: "Hà Nội")
      try self.insertEvent(db, "other", "Dentist", location: "Main street")
    }
    let cases: [(query: String, id: String)] = [
      ("lodzi", "pl"), ("ŁÓDZI", "pl"), ("spotkanie lodzi", "pl"),
      ("все еще", "ru"), ("ВСЁ", "ru"), ("isik", "tr"), ("ışık plaza", "tr"),
      ("hop doi", "vi"), ("ha noi", "vi"), ("DOI", "vi"),
    ]
    for (query, id) in cases {
      XCTAssertEqual(try found(store, query), [id], query)
    }
    XCTAssertEqual(try found(store, "nothing like this"), [])
  }

  func testEventSearchDoesNotWidenAnIndexHit() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEvent(db, "exact", "lodz notes")
      try self.insertEvent(db, "accented", "Łódź trip")
    }
    XCTAssertEqual(try found(store, "lodz"), ["exact"])
  }

  func testEventSearchFindsWordsInsideUnspacedScriptText() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEvent(db, "th", "ประชุมทีมพรุ่งนี้", location: "สำนักงานใหญ่")
      try self.insertEvent(db, "other", "Dentist")
    }
    XCTAssertEqual(try found(store, "ทีม"), ["th"])
    XCTAssertEqual(try found(store, "พรุ่งนี้"), ["th"])
    XCTAssertEqual(try found(store, "ไม่มี"), [])
  }

  func testProviderSearchIgnoresCaseAccentsAndLetterVariantsInEveryScript() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      for (key, title, location) in [
        ("ek-1", "Встреча всё ещё в силе", "Офис"),
        ("ek-2", "Spotkanie", "Łódź"),
        ("ek-3", "Weekly sync", "Işık Plaza"),
      ] {
        try db.execute(
          sql: """
            INSERT INTO provider_calendar_events \
              (provider_kind, provider_scope, provider_event_key, title, location, \
               start_date, start_time, end_date, end_time, all_day, last_seen_at) \
            VALUES ('eventkit', 'device', ?, ?, ?, \
                    '2026-06-02', '10:00', '2026-06-02', '11:00', 0, '2026-06-01T00:00:00Z')
            """,
          arguments: [key, title, location])
      }
      try db.execute(
        sql: """
          INSERT INTO provider_scope_runtime_state \
            (provider_kind, provider_scope, availability_state, \
             last_refresh_success_at, last_refresh_result) \
          VALUES ('eventkit', 'device', 'enabled', '2026-06-01T00:00:00Z', 'success')
          """)
    }
    let cases: [(query: String, key: String)] = [
      ("ВСЁ ЕЩЁ", "ek-1"), ("все еще", "ek-1"), ("lodz", "ek-2"), ("ŁÓDŹ", "ek-2"),
      ("isik", "ek-3"), ("WEEKLY", "ek-3"),
    ]
    for (query, key) in cases {
      let hits = try store.writer.read { db in
        try CalendarTimelineQueries.searchProviderCalendarEvents(
          db, predicate: CalendarSearchPredicate(query: query), limit: 10)
      }
      XCTAssertEqual(hits.map(\.id), ["eventkit:device:\(key)"], query)
    }
  }
}
