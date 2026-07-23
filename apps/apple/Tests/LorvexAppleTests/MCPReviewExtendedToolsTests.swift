import Foundation
import LorvexCore
import MCP
import Testing

@testable import LorvexMCPHost

@Suite("MCP Extended — review registry")
struct MCPReviewExtendedToolsTests {
  @Test("add_daily_review then amend_daily_review preserves unchanged fields")
  func addThenAmendPreservesFields() async throws {
    let registry = try mcpInMemoryRegistry()
    // The core rejects review writes outside the staleness window around
    // today, so the fixture review must use today's date.
    let added = try await contentCall(
      registry,
      tool: "add_daily_review",
      arguments: [
        "summary": .string("Original summary"),
        "mood": .int(3),
        "wins": .string("Original win"),
      ]
    )
    #expect(added.isError != true)
    let date = try #require(added.structuredContent?.objectValue?["date"]?.stringValue)

    let amendResult = try await contentCall(
      registry,
      tool: "amend_daily_review",
      arguments: [
        "date": .string(date),
        "mood": .int(5),
      ]
    )
    #expect(amendResult.isError != true)
    #expect(amendResult.structuredContent?.objectValue?["mood"]?.intValue == 5)
    let fencedSummary: String = SecurityFencing.fence("Original summary")
    #expect(
      amendResult.structuredContent?.objectValue?["summary"]?.stringValue == fencedSummary
    )
  }

  @Test("add_daily_review omission clears existing task and list links")
  func addReplacementOmissionClearsLinks() async throws {
    let registry = try mcpInMemoryRegistry()
    let createdTask = try await contentCall(
      registry,
      tool: "create_task",
      arguments: ["title": .string("Review-linked task")]
    )
    let taskID = try #require(createdTask.structuredContent?.objectValue?["id"]?.stringValue)
    let createdList = try await contentCall(
      registry,
      tool: "create_list",
      arguments: ["name": .string("Review-linked list")]
    )
    let listID = try #require(createdList.structuredContent?.objectValue?["id"]?.stringValue)
    let added = try await contentCall(
      registry,
      tool: "add_daily_review",
      arguments: ["summary": .string("Initial linked review")]
    )
    #expect(added.isError != true)
    let date = try #require(added.structuredContent?.objectValue?["date"]?.stringValue)

    let amended = try await contentCall(
      registry,
      tool: "amend_daily_review",
      arguments: [
        "date": .string(date),
        "linked_task_ids": .array([.string(taskID)]),
        "linked_list_ids": .array([.string(listID)]),
      ]
    )
    #expect(amended.isError != true)
    #expect(
      amended.structuredContent?.objectValue?["linked_task_ids"]?.arrayValue?.isEmpty == false)
    #expect(
      amended.structuredContent?.objectValue?["linked_list_ids"]?.arrayValue?.isEmpty == false)

    let replaced = try await contentCall(
      registry,
      tool: "add_daily_review",
      arguments: [
        "date": .string(date),
        "summary": .string("Full replacement without links"),
      ]
    )
    #expect(replaced.isError != true)
    #expect(
      replaced.structuredContent?.objectValue?["linked_task_ids"]?.arrayValue?.isEmpty == true)
    #expect(
      replaced.structuredContent?.objectValue?["linked_list_ids"]?.arrayValue?.isEmpty == true)
  }

  @Test("get_review_history respects an empty date range")
  func reviewHistoryEmptyRange() async throws {
    let result = try await contentCall(
      try mcpInMemoryRegistry(),
      tool: "get_review_history",
      arguments: ["from": .string("2000-01-01"), "to": .string("2000-01-31")]
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["returned"]?.intValue == 0)
  }

  @Test("get_weekly_brief returns a sectioned brief")
  func weeklyBriefReturnsSections() async throws {
    let result = try await contentCall(
      try mcpInMemoryRegistry(),
      tool: "get_weekly_brief"
    )
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["section_meta"] != nil)
  }
}
