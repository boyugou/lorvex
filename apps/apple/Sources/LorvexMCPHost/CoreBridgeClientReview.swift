import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func loadDailyReview(date: String) async throws -> Value {
    guard let review = try await service.loadDailyReview(date: date) else { return .null }
    return Self.dailyReviewValue(from: review)
  }

  func loadWeeklyReviewBrief(arguments: [String: Value]) async throws -> Value {
    Self.weeklyReviewBriefValue(
      from: try await service.getWeeklyReviewBrief(
        completedLimit: try StrictScalarArguments.optionalInt(
          arguments["completed_limit"], field: "completed_limit"),
        stalledListsLimit: try StrictScalarArguments.optionalInt(
          arguments["stalled_lists_limit"], field: "stalled_lists_limit"),
        deferredLimit: try StrictScalarArguments.optionalInt(
          arguments["deferred_limit"], field: "deferred_limit"),
        somedayLimit: try StrictScalarArguments.optionalInt(
          arguments["someday_limit"], field: "someday_limit")))
  }

  func upsertDailyReview(
    date: String,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    linkedTaskIDs: [String]?,
    linkedListIDs: [String]?
  ) async throws -> Value {
    let review = try await service.upsertDailyReview(
      date: date,
      summary: summary,
      mood: mood,
      energyLevel: energyLevel,
      wins: wins,
      blockers: blockers,
      learnings: learnings,
      linkedTaskIDs: linkedTaskIDs ?? [],
      linkedListIDs: linkedListIDs ?? []
    )
    return Self.dailyReviewValue(from: review)
  }

  func amendDailyReview(arguments: [String: Value]) async throws -> Value {
    guard let date = arguments["date"]?.stringValue, !date.isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A review date is required.")
    }
    guard try await service.loadDailyReview(date: date) != nil else {
      throw DailyReviewToolStoreError(message: "No review found for date '\(date)'.")
    }
    let patch = DailyReviewPatch(
      summary: try StrictScalarArguments.optionalString(arguments["summary"], field: "summary"),
      mood: try StrictScalarArguments.optionalInt(arguments["mood"], field: "mood"),
      energyLevel: try StrictScalarArguments.optionalInt(
        arguments["energy_level"], field: "energy_level"),
      wins: try StrictScalarArguments.optionalString(arguments["wins"], field: "wins"),
      blockers: try StrictScalarArguments.optionalString(arguments["blockers"], field: "blockers"),
      learnings: try StrictScalarArguments.optionalString(
        arguments["learnings"], field: "learnings"),
      linkedTaskIDs: try StrictArgumentArray.optionalStrings(
        arguments["linked_task_ids"], field: "linked_task_ids"),
      linkedListIDs: try StrictArgumentArray.optionalStrings(
        arguments["linked_list_ids"], field: "linked_list_ids")
    )
    return Self.dailyReviewValue(from: try await service.amendDailyReview(date: date, patch: patch))
  }

  func loadReviewHistory(arguments: [String: Value]) async throws -> Value {
    let requestedLimit = min(
      max(try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 30), 0),
      100)
    // Fetch one extra row so `truncated` reflects reality: if the source has
    // more than `requestedLimit` matching reviews, the page is trimmed and
    // `total_matching` is null (unknown, more exist) rather than a fabricated
    // total that equals the page size.
    let reviews = try await service.getReviewHistory(
      from: try StrictScalarArguments.optionalString(arguments["from"], field: "from"),
      to: try StrictScalarArguments.optionalString(arguments["to"], field: "to"),
      limit: requestedLimit + 1
    )
    let truncated = reviews.count > requestedLimit
    let page = reviews.prefix(requestedLimit).map(Self.dailyReviewValue(from:))
    return MCPPagination.object(
      domain: ["reviews": .array(Array(page))],
      totalMatching: truncated ? nil : page.count, returned: page.count, limit: requestedLimit,
      offset: 0, nextOffset: nil, truncated: truncated)
  }
}
