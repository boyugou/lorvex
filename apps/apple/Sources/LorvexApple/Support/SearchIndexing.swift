import Foundation
import LorvexCore

protocol TaskSearchIndexing: Sendable {
  func replaceIndexedTasks(_ tasks: [LorvexTask]) async throws
}

protocol ContentSearchIndexing: Sendable {
  func replaceIndexedLists(_ lists: [LorvexList]) async throws
  func replaceIndexedHabits(_ habits: [LorvexHabit]) async throws
  func replaceIndexedDailyReview(_ review: DailyReviewEntry?) async throws
  func replaceIndexedCalendarEvents(_ events: [CalendarTimelineEvent]) async throws
}

struct NoopTaskSearchIndexer: TaskSearchIndexing {
  func replaceIndexedTasks(_ tasks: [LorvexTask]) async throws {}
}

struct NoopContentSearchIndexer: ContentSearchIndexing {
  func replaceIndexedLists(_ lists: [LorvexList]) async throws {}
  func replaceIndexedHabits(_ habits: [LorvexHabit]) async throws {}
  func replaceIndexedDailyReview(_ review: DailyReviewEntry?) async throws {}
  func replaceIndexedCalendarEvents(_ events: [CalendarTimelineEvent]) async throws {}
}
