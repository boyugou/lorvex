import Foundation
import LorvexStore
import LorvexWorkflow

/// Maps the core's review shapes onto the app's `DailyReviewEntry` /
/// `WeeklyReviewSnapshot` / `ReviewTaskSummary` model types, preserving the
/// stable MCP/UI field shape.
enum SwiftLorvexReviewDeserializers {

  /// Lower a `daily_reviews` row (with rebuilt link projections) onto the app
  /// `DailyReviewEntry`. `Int64` mood/energy narrow to `Int`.
  static func dailyReview(_ row: DailyReviewRow) -> DailyReviewEntry {
    DailyReviewEntry(
      date: row.date,
      summary: row.summary,
      mood: row.mood.map(Int.init),
      energyLevel: row.energyLevel.map(Int.init),
      wins: row.wins,
      blockers: row.blockers,
      learnings: row.learnings,
      timezone: row.timezone,
      updatedAt: row.updatedAt,
      linkedTaskIDs: row.linkedTaskIds,
      linkedListIDs: row.linkedListIds)
  }

  /// Lower a `WeeklyReview.Snapshot` onto the app `WeeklyReviewSnapshot`. The
  /// window title is `"<from> - <to>"`, falling
  /// back to `"Last 7 days"` when either bound is empty.
  static func weeklyReviewBrief(_ brief: WeeklyReview.Brief) -> WeeklyReviewBriefModel {
    func items(_ rows: [WeeklyReview.TaskItem]) -> [WeeklyReviewBriefModel.TaskItem] {
      rows.map { row in
        WeeklyReviewBriefModel.TaskItem(
          id: row.id, title: row.title, listID: row.listId, status: row.status,
          completedAt: row.completedAt, dueDate: row.dueDate?.asString,
          deferCount: Int(row.deferCount))
      }
    }
    func entry(_ meta: WeeklyReview.BriefSectionEntry) -> WeeklyReviewBriefModel.SectionEntry {
      WeeklyReviewBriefModel.SectionEntry(
        limit: Int(meta.limit), totalMatching: Int(meta.totalMatching),
        returned: meta.returned, truncated: meta.truncated)
    }
    let from = brief.window.from
    let to = brief.window.to
    return WeeklyReviewBriefModel(
      window: WeeklyReviewBriefModel.Window(
        label: from.isEmpty || to.isEmpty ? "Last 7 days" : "\(from) - \(to)",
        days: Int(brief.window.days)),
      completedThisWeek: items(brief.completedThisWeek),
      stalledLists: brief.stalledLists.map { row in
        WeeklyReviewBriefModel.StalledList(
          id: row.id, name: row.name, icon: row.icon, color: row.color,
          openTaskCount: Int(row.openTaskCount), lastActivity: row.lastActivity)
      },
      frequentlyDeferred: items(brief.frequentlyDeferred),
      overdueCount: Int(brief.overdueCount),
      somedayItems: items(brief.somedayItems),
      createdThisWeek: Int(brief.createdThisWeek),
      estimateSummary: WeeklyReviewBriefModel.EstimateSummary(
        completedTotal: Int(brief.estimateSummary.completedTotal),
        completedWithEstimateCount: Int(brief.estimateSummary.completedWithEstimateCount),
        estimateCoverageRatio: brief.estimateSummary.estimateCoverageRatio),
      sectionMeta: WeeklyReviewBriefModel.SectionMeta(
        completedThisWeek: entry(brief.sectionMeta.completedThisWeek),
        stalledLists: entry(brief.sectionMeta.stalledLists),
        frequentlyDeferred: entry(brief.sectionMeta.frequentlyDeferred),
        somedayItems: entry(brief.sectionMeta.somedayItems)))
  }

  static func weeklyReview(_ snapshot: WeeklyReview.Snapshot) -> WeeklyReviewSnapshot {
    let from = snapshot.window.from
    let to = snapshot.window.to
    return WeeklyReviewSnapshot(
      windowTitle: from.isEmpty || to.isEmpty ? "Last 7 days" : "\(from) - \(to)",
      completedThisWeek: Int(snapshot.counts.completedThisWeek),
      createdThisWeek: Int(snapshot.counts.createdThisWeek),
      overdueOpen: Int(snapshot.counts.overdueOpen),
      deferredOpen: Int(snapshot.counts.deferredOpen),
      someday: Int(snapshot.counts.someday),
      estimateCoverageRatio: snapshot.estimateSummary.estimateCoverageRatio,
      topCompleted: snapshot.topCompleted.map(taskSummary),
      frequentlyDeferred: snapshot.frequentlyDeferred.map(taskSummary),
      topSomeday: snapshot.somedayItems.map(taskSummary))
  }

  static func taskSummary(_ item: WeeklyReview.TaskItem) -> ReviewTaskSummary {
    ReviewTaskSummary(
      id: item.id, title: item.title, status: item.status, deferCount: Int(item.deferCount))
  }
}
