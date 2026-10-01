import Foundation
import Testing

@testable import LorvexCore

/// The session context reports the current moment in the user's anchored time
/// zone, so an assistant can plan the rest of a day without reading a shell
/// clock or computing a weekday from a date.
@Suite("Session context clock")
struct SessionContextClockTests {
  private static func service(now iso: String, timezone: String) async throws
    -> SwiftLorvexCoreService
  {
    let now = try #require(ISO8601DateFormatter().date(from: iso))
    let service = try SwiftLorvexCoreService.inMemory(wallClock: { now })
    _ = try await service.setPreference(key: "timezone", value: "\"\(timezone)\"")
    return service
  }

  @Test("date, weekday, and local time describe one instant in the anchored zone")
  func reportsTheAnchoredMoment() async throws {
    // 15:30 UTC on Wednesday 2026-03-04 is already 00:30 on Thursday in Tokyo.
    let context = try await Self.service(now: "2026-03-04T15:30:00Z", timezone: "Asia/Tokyo")
      .getSessionContext()

    #expect(context.timezone == "Asia/Tokyo")
    #expect(context.date == "2026-03-05")
    #expect(context.weekday == "Thursday")
    #expect(context.localTime == "00:30")
  }

  @Test("the local time is truncated to the minute")
  func truncatesToTheMinute() async throws {
    let context = try await Self.service(now: "2026-03-04T23:59:59Z", timezone: "UTC")
      .getSessionContext()

    #expect(context.date == "2026-03-04")
    #expect(context.weekday == "Wednesday")
    #expect(context.localTime == "23:59")
  }
}
