import LorvexDomain
import Testing

@testable import LorvexCore

/// `recentLogChangelogLevel` maps a changelog row onto a diagnostic level.
/// A cleared briefing or cleared day of times is recorded as a `delete`
/// operation but is a routine planning action, so it must not surface as `warn`.
@Suite("Recent-log changelog level mapping")
struct RecentLogLevelTests {
  @Test("briefing clears and saved days stay info even when the op is delete")
  func dayPlanningIsInfo() {
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "delete", entityType: .dailyBriefing) == .info)
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "upsert", entityType: .dailySchedule) == .info)
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "delete", entityType: .dailySchedule) == .info)
  }

  @Test("genuine entity deletes and feedback warn")
  func destructiveOpsWarn() {
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "delete", entityType: .task) == .warn)
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "permanent_delete", entityType: .task) == .warn)
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "feedback", entityType: .task) == .warn)
  }

  @Test("ordinary upserts are info")
  func upsertsAreInfo() {
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "upsert", entityType: .task) == .info)
  }
}
