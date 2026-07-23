import Foundation
import MCP
import Testing

@testable import LorvexCore
@testable import LorvexMCPHost

private func contractYmd(daysFromToday offset: Int) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = .current
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: Date(timeIntervalSinceNow: TimeInterval(offset) * 86_400))
}

// MARK: - SwiftLorvexCoreService review-extended operations

@Suite("SwiftLorvexCoreService — review extended")
struct ReviewExtendedPreviewServiceTests {

  @Test("amendDailyReview patches only provided fields")
  func amendPatches() async throws {
    let service = try await makeSeededInMemoryCore()
    // The seeded core carries a review for "2026-05-22".
    let patch = DailyReviewPatch(mood: 5, wins: "Patched wins")
    let result = try await service.amendDailyReview(date: "2026-05-22", patch: patch)
    #expect(result.mood == 5)
    #expect(result.wins == "Patched wins")
    // Summary unchanged
    #expect(!result.summary.isEmpty)
  }

  @Test("amendDailyReview throws for unknown date")
  func amendUnknownDate() async throws {
    let service = try await makeSeededInMemoryCore()
    await #expect(throws: (any Error).self) {
      try await service.amendDailyReview(
        date: "1999-01-01",
        patch: DailyReviewPatch(mood: 3)
      )
    }
  }

  @Test("amendDailyReview rejects invalid mood")
  func amendInvalidMood() async throws {
    let service = try await makeSeededInMemoryCore()
    await #expect(throws: (any Error).self) {
      try await service.amendDailyReview(
        date: "2026-05-22",
        patch: DailyReviewPatch(mood: 99)
      )
    }
  }

  @Test("getReviewHistory returns reviews newest first")
  func reviewHistoryOrder() async throws {
    let service = try await makeSeededInMemoryCore()
    // Add a second review so we have two to sort.
    _ = try await service.upsertDailyReviewPreservingLinks(
      date: contractYmd(daysFromToday: -1),
      summary: "Another day",
      mood: nil,
      energyLevel: nil,
      wins: nil,
      blockers: nil,
      learnings: nil
    )
    let history = try await service.getReviewHistory(from: nil, to: nil, limit: nil)
    #expect(history.count >= 2)
    // Newest first
    #expect(history[0].date >= history[1].date)
  }

  @Test("getReviewHistory respects date window")
  func reviewHistoryWindow() async throws {
    let service = try await makeSeededInMemoryCore()
    let history = try await service.getReviewHistory(
      from: "2026-05-22", to: "2026-05-22", limit: nil)
    #expect(history.allSatisfy { $0.date == "2026-05-22" })
  }

  @Test("getReviewHistory respects limit")
  func reviewHistoryLimit() async throws {
    let service = try await makeSeededInMemoryCore()
    // Seed several reviews
    for d in (1...4).map({ contractYmd(daysFromToday: -$0) }) {
      _ = try await service.upsertDailyReviewPreservingLinks(
        date: d, summary: "Day \(d)", mood: nil, energyLevel: nil,
        wins: nil, blockers: nil, learnings: nil
      )
    }
    let history = try await service.getReviewHistory(from: nil, to: nil, limit: 2)
    #expect(history.count <= 2)
  }

  @Test("getWeeklyReviewSnapshot returns non-nil snapshot")
  func weeklySnapshot() async throws {
    let service = try await makeSeededInMemoryCore()
    let snapshot = try await service.getWeeklyReviewSnapshot(weekOf: nil)
    #expect(!snapshot.windowTitle.isEmpty)
  }
}

// MARK: - MCP ToolRegistry review-extended tools

private func call(
  _ registry: ToolRegistry,
  tool name: String,
  arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

private func textContent(_ result: CallTool.Result) -> String {
  result.content.compactMap {
    if case .text(let text, _, _) = $0 { return text }
    return nil
  }.joined()
}

@Suite("MCP ToolRegistry — review extended tools")
struct ReviewExtendedRegistryTests {

  @Test("amend_daily_review patches an existing review")
  func amendTool() async throws {
    // The seeded core carries a review for "2026-05-22"; amend has no
    // staleness window (unlike add_daily_review), only an existence check.
    let registry = try await mcpSeededRegistry()
    let amendResult = try await call(
      registry, tool: "amend_daily_review",
      arguments: [
        "date": .string("2026-05-22"),
        "mood": .int(5),
      ]
    )
    #expect(amendResult.isError != true)
    let mood = amendResult.structuredContent?.objectValue?["mood"]?.intValue
    #expect(mood == 5)
  }

  @Test("amend_daily_review requires date")
  func amendMissingDate() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await call(registry, tool: "amend_daily_review", arguments: [:])
    #expect(result.isError == true)
  }

  @Test("amend_daily_review returns error for unknown date")
  func amendUnknownDate() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await call(
      registry, tool: "amend_daily_review",
      arguments: ["date": .string("1999-12-31"), "mood": .int(3)]
    )
    #expect(result.isError == true)
    #expect(textContent(result).contains("No review"))
  }

  @Test("get_review_history returns reviews array")
  func reviewHistoryTool() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await call(registry, tool: "get_review_history")
    #expect(result.isError != true)
    let reviews = result.structuredContent?.objectValue?["reviews"]?.arrayValue
    #expect(reviews != nil)
  }

  @Test("get_review_history listed and dispatched without orphan")
  func reviewHistoryNotOrphan() async throws {
    let tools = ToolRegistry.listTools()
    #expect(tools.contains { $0.name == "get_review_history" })
  }

  @Test("get_weekly_brief returns non-error result")
  func weeklyBriefTool() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await call(registry, tool: "get_weekly_brief")
    #expect(result.isError != true)
    #expect(result.structuredContent != nil)
  }

  @Test("amend_daily_review is listed in catalog")
  func amendIsListed() async throws {
    let tools = ToolRegistry.listTools()
    #expect(tools.contains { $0.name == "amend_daily_review" })
  }

  @Test("get_weekly_brief is listed in catalog")
  func weeklyBriefIsListed() async throws {
    let tools = ToolRegistry.listTools()
    #expect(tools.contains { $0.name == "get_weekly_brief" })
    #expect(!tools.contains { $0.name == "get_weekly_review_snapshot" })
  }
}
