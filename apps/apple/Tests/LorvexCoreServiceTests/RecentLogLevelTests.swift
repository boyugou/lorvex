import LorvexDomain
import Testing

@testable import LorvexCore

/// `recentLogChangelogLevel` maps a changelog row onto a diagnostic level.
/// Focus plan/schedule clears are recorded as `delete` operations but are
/// routine planning actions, so they must not surface as `warn`.
@Suite("Recent-log changelog level mapping")
struct RecentLogLevelTests {
  @Test("focus plan/schedule clears stay info even when the op is delete")
  func focusClearsAreInfo() {
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "delete", entityType: .currentFocus) == .info)
    #expect(
      SwiftLorvexCoreService.recentLogChangelogLevel(
        operation: "delete", entityType: .focusSchedule) == .info)
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
