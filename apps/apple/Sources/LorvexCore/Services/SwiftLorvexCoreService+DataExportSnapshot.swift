import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension SwiftLorvexCoreService {
  /// Captures the complete selected export in one GRDB read transaction. Every
  /// category, aggregate child, AI-access preference, and native task root is
  /// therefore projected from the same SQLite snapshot even while another app
  /// process writes the shared store.
  public func loadSnapshotForDataExport(
    entities: [String], forAI: Bool, includeNativeTaskGraph: Bool
  ) async throws -> LorvexDataExportSnapshot {
    let all = entities.isEmpty || entities.contains("all")
    let selected = Set(entities)
    let habitDate = LorvexDateFormatters.ymd.string(from: Date())
    return try read { db in
      let include = { (category: LorvexDataExportCategory) -> Bool in
        all || selected.contains(category.rawValue)
      }

      let tasks: [ExportTask]?
      let nativeTaskGraph: NativeTaskGraphSnapshot?
      if include(.tasks) {
        tasks = try Self.portableTasksForDataExport(db)
        if includeNativeTaskGraph {
          let graph = try Self.nativeTaskGraphForDataExport(
            db,
            includeTaskCalendarEventLinkControlState: include(.taskCalendarEventLinks))
          try Self.validateTaskExportIdentityClosure(
            portableTasks: tasks ?? [], nativeGraph: graph)
          nativeTaskGraph = graph
        } else {
          nativeTaskGraph = nil
        }
      } else {
        tasks = nil
        nativeTaskGraph = nil
      }

      let lists = include(.lists) ? try Self.listsForDataExport(db) : nil
      let tags = include(.tags) ? try Self.tagsForDataExport(db) : nil
      let habits =
        include(.habits)
        ? try Self.habitsForDataExport(db, date: habitDate)
        : nil

      let calendarBundle: ExportCalendarBundle?
      if include(.calendarEvents) {
        let cutovers = try Self.calendarSeriesCutoversForDataExport(db)
        Self.afterCalendarCutoverExportReadForTesting?()
        let events = try Self.calendarEventsForDataExport(db)
        try Self.validateCalendarBundleForDataExport(db, cutovers: cutovers, events: events)
        calendarBundle = ExportCalendarBundle(cutovers: cutovers, events: events)
      } else {
        calendarBundle = nil
      }

      let dailyReviews =
        include(.dailyReviews)
        ? try Self.dailyReviewsForDataExport(db)
        : nil
      let currentFocus =
        include(.currentFocus)
        ? try Self.currentFocusForDataExport(db)
        : nil

      let focusSchedules: [ExportFocusSchedule]?
      if include(.focusSchedules) {
        let includeProviderBlocks =
          forAI
          ? try DeviceStateRepo.readCalendarAiAccessMode(db).includesProvider
          : true
        focusSchedules = try Self.focusSchedulesForDataExport(
          db, includeProviderBlocks: includeProviderBlocks)
      } else {
        focusSchedules = nil
      }

      let taskCalendarEventLinks =
        include(.taskCalendarEventLinks)
        ? try Self.taskCalendarEventLinksForDataExport(db)
        : nil
      let memory = include(.memory) ? try Self.memoryForDataExport(db) : nil
      let preferences =
        include(.preferences)
        ? try Self.preferencesForDataExport(db)
        : nil

      if let nativeTaskGraph {
        do {
          try NativeTaskGraphArchiveClosureValidator.validate(
            nativeTaskGraph,
            exportedListIDs: lists.map { Set($0.map(\.id)) },
            exportedTagIDs: tags.map { Set($0.map(\.id)) })
        } catch {
          throw LorvexCoreError.validation(
            field: "nativeTaskGraph",
            message:
              "Task data is not closed under its selected list and tag roots. Retry after database recovery finishes."
          )
        }
      }

      let payload = LorvexDataExportPayload(
        tasks: tasks, nativeTaskGraph: nativeTaskGraph, lists: lists, tags: tags,
        habits: habits, calendarSeriesCutovers: calendarBundle?.cutovers,
        calendarEvents: calendarBundle?.events, dailyReviews: dailyReviews,
        currentFocus: currentFocus, focusSchedules: focusSchedules,
        taskCalendarEventLinks: taskCalendarEventLinks, memory: memory,
        preferences: preferences)
      let deviceID = try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId)
      return LorvexDataExportSnapshot(payload: payload, sourceDeviceID: deviceID)
    }
  }

  static func listsForDataExport(_ db: Database) throws -> [ExportList] {
    let active = try ListRepo.getAllListsWithCounts(db)
      .map(SwiftLorvexListDeserializers.list)
    afterActiveListsExportReadForTesting?()
    let archived = try ListRepo.getListsWithCountsPage(
      db, limit: nil, scope: .archived
    ).rows.map(SwiftLorvexListDeserializers.list)
    return (active + archived).map(ExportList.init(from:))
  }

  static func habitsForDataExport(
    _ db: Database, date: String
  ) throws -> [ExportHabit] {
    let active = try loadHabitsSnapshot(db, date: date).habits
    let archived = try loadHabitsSnapshot(db, date: date, archived: true).habits
    return try (active + archived).map { habit in
      let completionCount =
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM habit_completions WHERE habit_id = ?",
          arguments: [habit.id]) ?? 0
      try validateExportRowCount(
        category: "habit_completions:\(habit.id)", count: completionCount,
        limit: LorvexDataExportWindow.habitCompletionLimit)
      let completions = try habitCompletionsSnapshot(
        db, id: habit.id, from: nil, to: nil,
        limit: LorvexDataExportWindow.habitCompletionLimit
      ).completions.map(ExportHabitCompletion.init(from:))
      let reminderPolicies = try habitReminderPoliciesForDataExport(db, id: habit.id)
        .map(ExportHabitReminderPolicy.init(from:))
      return ExportHabit(
        from: habit, completions: completions, reminderPolicies: reminderPolicies)
    }
  }

  static func dailyReviewsForDataExport(_ db: Database) throws -> [ExportDailyReview] {
    let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_reviews") ?? 0
    try validateExportRowCount(
      category: LorvexDataExportCategory.dailyReviews.rawValue, count: count,
      limit: LorvexDataExportWindow.reviewHistoryLimit)
    return try reviewHistory(
      db, from: nil, to: nil, limit: LorvexDataExportWindow.reviewHistoryLimit
    ).map(ExportDailyReview.init(from:))
  }

  /// A bounded v1 in-memory export may reject an implausibly large category,
  /// but it must never silently return only the first `limit` rows.
  static func validateExportRowCount(category: String, count: Int, limit: Int) throws {
    if count > limit {
      throw LorvexDataExportError.categoryRowLimitExceeded(
        category: category, count: count, limit: limit)
    }
  }

  static func preferencesForDataExport(_ db: Database) throws -> [ExportPreference] {
    try readPreferences(db)
      .filter { !PreferenceKeys.isExcludedFromPreferenceEntitySync($0.key) }
      .sorted { $0.key < $1.key }
      .map { ExportPreference(key: $0.key, value: $0.value) }
  }
}
