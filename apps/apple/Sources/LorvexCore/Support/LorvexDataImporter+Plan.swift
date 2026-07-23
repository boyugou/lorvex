import Foundation

extension LorvexDataImporter {
  /// Build the content plan from already-decoded bytes (JSON or ZIP). Pure: a
  /// decode plus per-category count, no service calls and no target-DB diff, so
  /// the counts are what the file contains, not what a restore will write.
  /// Returns the decoded import so confirm applies exactly what the user saw.
  public static func plan(from data: Data) throws -> (LorvexImportPlan, DecodedImport) {
    let decoded = try decodeFull(data)
    let plan = self.plan(for: decoded.payload)
    guard !plan.entries.isEmpty else { throw ImportError.noImportableData }
    return (plan, decoded)
  }

  /// Build the content plan for a decoded payload: for each category the file
  /// carries, the count of records it holds (not a target-DB diff). Lists only
  /// categories the file actually carries, in `LorvexDataExportCategory`
  /// declaration order.
  public static func plan(for payload: LorvexDataExportPayload) -> LorvexImportPlan {
    var entries: [LorvexImportPlanEntry] = []
    func add(
      _ category: LorvexDataExportCategory, _ count: Int?,
      hasInternalDependencyData: Bool = false
    ) {
      guard let count else { return }
      entries.append(
        LorvexImportPlanEntry(
          category: category,
          recordCount: count,
          isSupported: supportedCategories.contains(category),
          hasInternalDependencyData: hasInternalDependencyData))
    }
    // A native backup carries both an exact graph and its portable task
    // projection. Count the graph when the portable member is unexpectedly
    // absent so Apply still runs and reports the representation mismatch rather
    // than silently ignoring the native member.
    let nativeTaskGraphHasSyncState =
      !(payload.nativeTaskGraph?.tombstones.isEmpty ?? true)
      || !(payload.nativeTaskGraph?.payloadShadows.isEmpty ?? true)
    add(
      .tasks, payload.tasks?.count ?? payload.nativeTaskGraph?.tasks.count,
      hasInternalDependencyData: nativeTaskGraphHasSyncState)
    add(.lists, payload.lists?.count)
    add(.tags, payload.tags?.count)
    add(.habits, payload.habits?.count)
    if payload.calendarEvents != nil || payload.calendarSeriesCutovers != nil {
      entries.append(
        LorvexImportPlanEntry(
          category: .calendarEvents,
          recordCount: payload.calendarEvents?.count ?? 0,
          isSupported: supportedCategories.contains(.calendarEvents),
          hasInternalDependencyData: !(payload.calendarSeriesCutovers?.isEmpty ?? true)))
    }
    add(.dailyReviews, payload.dailyReviews?.count)
    add(.currentFocus, payload.currentFocus?.count)
    add(.focusSchedules, payload.focusSchedules?.count)
    add(.taskCalendarEventLinks, payload.taskCalendarEventLinks?.count)
    add(.memory, payload.memory?.count)
    add(.preferences, payload.preferences?.count)
    return LorvexImportPlan(entries: entries)
  }
}
