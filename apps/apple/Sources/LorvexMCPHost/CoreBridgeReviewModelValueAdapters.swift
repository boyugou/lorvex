import Foundation
import LorvexCore
import MCP

/// Maps the `LorvexCore` review model types onto the MCP `Value` JSON shapes the
/// review tool handlers return. Field names and shapes mirror the contract
/// expected by existing MCP clients, so external integrations see stable
/// objects while the implementation stays pure Swift.
extension CoreBridgeClient {
  static func dailyReviewValue(from review: DailyReviewEntry) -> Value {
    .object([
      "date": .string(review.date),
      "summary": .string(review.summary),
      "mood": review.mood.map(Value.int) ?? .null,
      "energy_level": review.energyLevel.map(Value.int) ?? .null,
      "wins": review.wins.map(Value.string) ?? .null,
      "blockers": review.blockers.map(Value.string) ?? .null,
      "learnings": review.learnings.map(Value.string) ?? .null,
      "timezone": review.timezone.map(Value.string) ?? .null,
      "updated_at": review.updatedAt.map(Value.string) ?? .null,
      "linked_task_ids": .array(review.linkedTaskIDs.map(Value.string)),
      "linked_list_ids": .array(review.linkedListIDs.map(Value.string)),
    ])
  }

  static func weeklyReviewBriefValue(from brief: WeeklyReviewBriefModel) -> Value {
    func items(_ rows: [WeeklyReviewBriefModel.TaskItem]) -> Value {
      .array(
        rows.map { row in
          slimTaskSummaryValue(
            id: row.id, title: row.title, status: row.status,
            listID: row.listID, priority: nil, dueDate: row.dueDate, plannedDate: nil,
            extra: [
              "completed_at": row.completedAt.map(Value.string) ?? .null,
              "defer_count": .int(row.deferCount),
            ])
        })
    }
    func meta(_ entry: WeeklyReviewBriefModel.SectionEntry) -> Value {
      .object([
        "limit": .int(entry.limit),
        "total_matching": .int(entry.totalMatching),
        "returned": .int(entry.returned),
        "truncated": .bool(entry.truncated),
      ])
    }
    return .object([
      "window": .object([
        "label": .string(brief.window.label),
        "days": .int(brief.window.days),
      ]),
      "completed_this_week": items(brief.completedThisWeek),
      "stalled_lists": .array(
        brief.stalledLists.map { list in
          .object([
            "id": .string(list.id),
            "name": .string(list.name),
            "icon": list.icon.map(Value.string) ?? .null,
            "color": list.color.map(Value.string) ?? .null,
            "open_task_count": .int(list.openTaskCount),
            "last_activity": list.lastActivity.map(Value.string) ?? .null,
          ])
        }),
      "frequently_deferred": items(brief.frequentlyDeferred),
      "overdue_count": .int(brief.overdueCount),
      "someday_items": items(brief.somedayItems),
      "created_this_week": .int(brief.createdThisWeek),
      "estimate_summary": .object([
        "completed_total": .int(brief.estimateSummary.completedTotal),
        "completed_with_estimate_count": .int(brief.estimateSummary.completedWithEstimateCount),
        "estimate_coverage_ratio": brief.estimateSummary.estimateCoverageRatio.map(Value.double)
          ?? .null,
      ]),
      "section_meta": .object([
        "completed_this_week": meta(brief.sectionMeta.completedThisWeek),
        "stalled_lists": meta(brief.sectionMeta.stalledLists),
        "frequently_deferred": meta(brief.sectionMeta.frequentlyDeferred),
        "someday_items": meta(brief.sectionMeta.somedayItems),
      ]),
    ])
  }
}
