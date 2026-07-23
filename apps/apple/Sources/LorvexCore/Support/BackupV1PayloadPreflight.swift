import Foundation
import LorvexDomain

/// Shared semantic preflight for both public-v1 containers and the defensive
/// programmatic apply entry point. A backup that fails here is rejected before
/// preview and, critically, before any list/tag root can be written.
enum BackupV1PayloadPreflight {
  static func validate(_ payload: LorvexDataExportPayload) throws {
    try validateParentMemberRelationships(payload)
    try validateUniqueIdentities(payload)
    try validateImportablePreferences(payload.preferences ?? [])
    try validateCrossCategoryRelationships(payload)
    if let graph = payload.nativeTaskGraph {
      do {
        _ = try NativeTaskGraphRestoreAdapter.prepareVersion1(graph)
      } catch let error as NativeTaskGraphValidationError {
        if case .incompatibleSchemaVersion(let version) = error {
          throw LorvexDataImporter.ImportError.incompatibleNativeTaskGraph(
            found: version, supported: BackupV1Contract.nativeTaskGraphSchemaVersion)
        }
        throw LorvexDataImporter.ImportError.invalidNativeTaskGraph(error.description)
      } catch {
        throw LorvexDataImporter.ImportError.invalidNativeTaskGraph(error.localizedDescription)
      }
    }
    try LorvexDataImporter.validateBackupV1TaskProjection(payload)
  }

  static func validateParentMemberRelationships(
    _ payload: LorvexDataExportPayload
  ) throws {
    if payload.nativeTaskGraph != nil, payload.tasks == nil {
      throw LorvexDataImporter.ImportError.manifestCountMismatch(
        "nativeTaskGraph is present without its tasks category")
    }
    if payload.calendarSeriesCutovers != nil, payload.calendarEvents == nil {
      throw LorvexDataImporter.ImportError.manifestCountMismatch(
        "calendarSeriesCutovers is present without its calendar_events category")
    }
  }

  private static func validateUniqueIdentities(
    _ payload: LorvexDataExportPayload
  ) throws {
    try requireUnique(payload.tasks?.map(\.id) ?? [], label: "task id")
    try requireUnique(payload.lists?.map(\.id) ?? [], label: "list id")
    try requireUnique(payload.tags?.map(\.id) ?? [], label: "tag id")
    try requireUnique(payload.habits?.map(\.id) ?? [], label: "habit id")
    try requireUnique(
      payload.calendarSeriesCutovers?.map(\.id) ?? [], label: "calendar cutover id")
    try requireUnique(
      payload.calendarSeriesCutovers?.map { "\($0.lineageRootId)\u{0}\($0.cutoverDate)" } ?? [],
      label: "calendar cutover lineage/date")
    try requireUnique(payload.calendarEvents?.map(\.id) ?? [], label: "calendar event id")
    try requireUnique(
      payload.calendarEvents?.compactMap { event in
        guard let seriesID = event.seriesId,
          let generation = event.recurrenceGeneration,
          let date = event.recurrenceInstanceDate
        else { return nil }
        return "\(seriesID)\u{0}\(generation)\u{0}\(date)"
      } ?? [],
      label: "calendar occurrence identity")
    try requireUnique(payload.dailyReviews?.map(\.date) ?? [], label: "daily review date")
    try requireUnique(payload.currentFocus?.map(\.date) ?? [], label: "current-focus date")
    try requireUnique(payload.focusSchedules?.map(\.date) ?? [], label: "focus-schedule date")
    try requireUnique(
      payload.taskCalendarEventLinks?.map { taskCalendarLinkID($0) } ?? [],
      label: "task-calendar link")
    try requireUnique(payload.memory?.compactMap(\.id) ?? [], label: "memory id")
    try requireUnique(payload.memory?.map(\.key) ?? [], label: "memory key")
    try requireUnique(payload.preferences?.map(\.key) ?? [], label: "preference key")

    var checklistIDs: [String] = []
    var reminderIDs: [String] = []
    for task in payload.tasks ?? [] {
      checklistIDs.append(contentsOf: task.checklist?.compactMap(\.id) ?? [])
      reminderIDs.append(contentsOf: task.reminders?.compactMap(\.id) ?? [])
      try requireUnique(task.dependsOn ?? [], label: "task \(task.id) dependency")
      try requireUnique(task.tags ?? [], label: "task \(task.id) tag")
      try requireUnique(
        task.recurrenceExceptions ?? [], label: "task \(task.id) recurrence exception")
    }
    try requireUnique(checklistIDs, label: "task checklist id")
    try requireUnique(reminderIDs, label: "task reminder id")

    var habitReminderPolicyIDs: [String] = []
    var activeHabitLookupKeys: [String] = []
    for habit in payload.habits ?? [] {
      if !habit.archived {
        activeHabitLookupKeys.append(normalizeLookupKey(habit.name))
      }
      try requireUnique(
        habit.completions.map(\.completedDate),
        label: "habit \(habit.id) completion date")
      habitReminderPolicyIDs.append(contentsOf: habit.reminderPolicies.map(\.id))
      try requireUnique(
        habit.reminderPolicies.map(\.reminderTime),
        label: "habit \(habit.id) reminder time")
    }
    try requireUnique(activeHabitLookupKeys, label: "active habit lookup key")
    try requireUnique(habitReminderPolicyIDs, label: "habit reminder-policy id")

    for focus in payload.currentFocus ?? [] {
      try requireUnique(focus.taskIDs, label: "current-focus \(focus.date) task id")
    }
    for review in payload.dailyReviews ?? [] {
      try requireUnique(review.linkedTaskIDs, label: "daily-review \(review.date) task link")
      try requireUnique(review.linkedListIDs, label: "daily-review \(review.date) list link")
    }
    for schedule in payload.focusSchedules ?? [] {
      let positions = schedule.blocks.map(\.position)
      try requireUnique(
        positions.map(String.init), label: "focus-schedule \(schedule.date) position")
      guard positions.sorted() == Array(0..<positions.count) else {
        throw inconsistent(
          "focus-schedule \(schedule.date) positions must be contiguous from zero")
      }
      for block in schedule.blocks {
        try validateFocusScheduleBlock(block, date: schedule.date)
      }
    }
  }

  private static func validateCrossCategoryRelationships(
    _ payload: LorvexDataExportPayload
  ) throws {
    let includedTaskIDs = payload.tasks.map { Set($0.map(\.id)) }
    let archivedTaskIDs = Set(
      (payload.tasks ?? []).lazy.filter { $0.archivedAt != nil }.map(\.id))
    let includedListIDs = payload.lists.map { Set($0.map(\.id)) }
    let includedEventIDs = payload.calendarEvents.map { Set($0.map(\.id)) }
    let eventsByID = Dictionary(
      uniqueKeysWithValues: (payload.calendarEvents ?? []).map { ($0.id, $0) })
    let cutoversByID = Dictionary(
      uniqueKeysWithValues: (payload.calendarSeriesCutovers ?? []).map { ($0.id, $0) })

    if let includedTaskIDs {
      for task in payload.tasks ?? [] {
        try requireSubset(
          task.dependsOn ?? [], of: includedTaskIDs,
          label: "task \(task.id) dependency")
      }
      for focus in payload.currentFocus ?? [] {
        try requireSubset(
          focus.taskIDs, of: includedTaskIDs,
          label: "current-focus \(focus.date) task")
        if let archived = focus.taskIDs.first(where: archivedTaskIDs.contains) {
          throw inconsistent(
            "current-focus \(focus.date) references archived task \(archived)")
        }
      }
      for review in payload.dailyReviews ?? [] {
        try requireSubset(
          review.linkedTaskIDs, of: includedTaskIDs,
          label: "daily-review \(review.date) task link")
      }
    }
    if let includedListIDs {
      for task in payload.tasks ?? [] {
        if let listID = task.listID, !includedListIDs.contains(listID) {
          throw inconsistent("task \(task.id) references omitted list \(listID)")
        }
      }
      for review in payload.dailyReviews ?? [] {
        try requireSubset(
          review.linkedListIDs, of: includedListIDs,
          label: "daily-review \(review.date) list link")
      }
      for preference in payload.preferences ?? []
      where preference.key == PreferenceKeys.prefDefaultListId {
        let logicalListID = SwiftLorvexCoreService.preferenceString(preference.value)
        if let logicalListID, !includedListIDs.contains(logicalListID) {
          throw inconsistent(
            "default_list_id preference references omitted list \(logicalListID)")
        }
      }
    }

    if let includedEventIDs {
      for event in payload.calendarEvents ?? [] {
        if let seriesID = event.seriesId, !includedEventIDs.contains(seriesID) {
          throw inconsistent(
            "calendar occurrence \(event.id) references omitted series \(seriesID)")
        }
        if let marker = event.seriesCutoverId {
          guard cutoversByID[marker] != nil else {
            throw inconsistent(
              "calendar segment \(event.id) references omitted boundary \(marker)")
          }
          guard event.id == marker else {
            throw inconsistent(
              "calendar segment \(event.id) does not match boundary \(marker)")
          }
        }
      }
      for cutover in payload.calendarSeriesCutovers ?? [] {
        guard cutover.state == "active" || cutover.state == "deleted" else {
          throw inconsistent(
            "calendar boundary \(cutover.id) has unknown state \(cutover.state)")
        }
        guard cutover.state == "active" else { continue }
        guard let segment = eventsByID[cutover.id] else {
          throw inconsistent(
            "active calendar boundary \(cutover.id) has no segment event")
        }
        guard segment.seriesCutoverId == cutover.id, segment.seriesId == nil,
          segment.recurrenceInstanceDate == nil, segment.occurrenceState == nil
        else {
          throw inconsistent(
            "active calendar boundary \(cutover.id) has a malformed segment event")
        }
      }
    }

    for schedule in payload.focusSchedules ?? [] {
      for block in schedule.blocks {
        if block.blockType == "task", let taskID = block.taskID,
          let includedTaskIDs, !includedTaskIDs.contains(taskID)
        {
          throw inconsistent(
            "focus-schedule \(schedule.date) references omitted task \(taskID)")
        }
        if block.blockType == "task", let taskID = block.taskID,
          archivedTaskIDs.contains(taskID)
        {
          throw inconsistent(
            "focus-schedule \(schedule.date) references archived task \(taskID)")
        }
        if block.blockType == "event", block.eventSource == .canonical,
          let calendarEventID = block.calendarEventID, let includedEventIDs,
          !includedEventIDs.contains(calendarEventID)
        {
          throw inconsistent(
            "focus-schedule \(schedule.date) references omitted calendar event \(calendarEventID)")
        }
      }
    }

    let liveLinkIDs = Set((payload.taskCalendarEventLinks ?? []).map(taskCalendarLinkID))
    for link in payload.taskCalendarEventLinks ?? [] {
      if let includedTaskIDs, !includedTaskIDs.contains(link.taskID) {
        throw inconsistent("task-calendar link references omitted task \(link.taskID)")
      }
      if let includedEventIDs, !includedEventIDs.contains(link.calendarEventID) {
        throw inconsistent(
          "task-calendar link references omitted calendar event \(link.calendarEventID)")
      }
    }

    guard let graph = payload.nativeTaskGraph else { return }
    let linkTombstoneIDs = Set(
      graph.tombstones.lazy
        .filter { $0.entityType == .taskCalendarEventLink }
        .map(\.entityID))
    let linkShadowIDs = Set(
      graph.payloadShadows.lazy
        .filter { $0.entityType == .taskCalendarEventLink }
        .map(\.entityID))
    if payload.taskCalendarEventLinks == nil,
      !linkTombstoneIDs.isEmpty || !linkShadowIDs.isEmpty
    {
      throw inconsistent(
        "the native task graph carries task-calendar link state while that category is omitted")
    }
    if let contradiction = liveLinkIDs.intersection(linkTombstoneIDs).sorted().first {
      throw inconsistent("task-calendar link \(contradiction) is both live and tombstoned")
    }
    if let orphanShadow = linkShadowIDs.subtracting(liveLinkIDs).sorted().first {
      throw inconsistent(
        "task-calendar payload shadow \(orphanShadow) has no live link row")
    }
  }

  /// Validate every ordinary preference before any import category can write.
  ///
  /// Exported values are the JSON text stored in SQLite, not the plain-string
  /// convenience accepted by `setPreference`. Parsing that text directly keeps
  /// a malformed backup from being reinterpreted as a JSON string. Local-only
  /// and control-plane settings are intentionally ignored here because import
  /// skips them rather than restoring one device/account's private state.
  private static func validateImportablePreferences(
    _ preferences: [ExportPreference]
  ) throws {
    for preference in preferences {
      guard !PreferenceKeys.isExcludedFromPreferenceEntitySync(preference.key) else {
        continue
      }
      guard let parsed = JSONValue.parse(preference.value) else {
        throw inconsistent(
          "preference '\(preference.key)' value is not valid stored JSON")
      }
      let normalized: JSONValue
      switch PreferenceValueContract.normalize(key: preference.key, value: parsed) {
      case .success(let value):
        normalized = value
      case .failure(let error):
        throw inconsistent(
          "preference '\(preference.key)' value is invalid: \(error.description)")
      }
      do {
        _ = try canonicalizeJSON(normalized)
      } catch {
        throw inconsistent(
          "preference '\(preference.key)' value cannot be canonicalized")
      }
    }
  }

  private static func requireUnique(_ values: [String], label: String) throws {
    var seen = Set<String>()
    for value in values where !seen.insert(value).inserted {
      throw inconsistent("duplicate \(label) \(display(value))")
    }
  }

  private static func requireSubset(
    _ values: [String], of available: Set<String>, label: String
  ) throws {
    if let missing = values.first(where: { !available.contains($0) }) {
      throw inconsistent("\(label) references omitted identity \(missing)")
    }
  }

  private static func taskCalendarLinkID(_ link: ExportTaskCalendarEventLink) -> String {
    "\(link.taskID):\(link.calendarEventID)"
  }

  private static func validateFocusScheduleBlock(
    _ block: ExportFocusScheduleBlock, date: String
  ) throws {
    guard block.startMinutes >= 0, block.endMinutes > block.startMinutes,
      block.endMinutes <= 1440
    else {
      throw inconsistent("focus-schedule \(date) has invalid block minutes")
    }
    switch block.blockType {
    case "task":
      guard block.taskID != nil, block.calendarEventID == nil, block.eventSource == nil else {
        throw inconsistent("focus-schedule \(date) has a contradictory task block")
      }
    case "event":
      guard block.taskID == nil, let source = block.eventSource else {
        throw inconsistent("focus-schedule \(date) has a contradictory event block")
      }
      switch source {
      case .canonical:
        guard block.calendarEventID != nil else {
          throw inconsistent("focus-schedule \(date) has a canonical event block without an id")
        }
      case .provider, .freeform:
        guard block.calendarEventID == nil else {
          throw inconsistent(
            "focus-schedule \(date) has a noncanonical event block with an id")
        }
      }
    case "buffer":
      guard block.taskID == nil, block.calendarEventID == nil, block.eventSource == nil else {
        throw inconsistent("focus-schedule \(date) has a contradictory buffer block")
      }
    default:
      throw inconsistent("focus-schedule \(date) has unknown block type \(block.blockType)")
    }
  }

  private static func display(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "\u{0}", with: ":"))'"
  }

  private static func inconsistent(
    _ detail: String
  ) -> LorvexDataImporter.ImportError {
    .inconsistentBackupContents(detail)
  }
}
