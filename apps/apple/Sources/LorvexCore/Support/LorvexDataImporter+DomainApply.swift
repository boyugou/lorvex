import Foundation

extension LorvexDataImporter {
  static func applyLists(
    _ lists: [ExportList], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportIssue]) {
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportIssue] = []
    let importer = core as? any LorvexNativeImportServicing
    for list in lists {
      do {
        // Atomic non-destructive restore: a stale backup must not overwrite an id
        // a concurrent create already landed, nor resurrect one the user deleted
        // after the backup (either would mint a dominating HLC and re-propagate the
        // list fleet-wide). The presence + tombstone check and the insert share one
        // transaction. A brand-new id still inserts. A backend without the native
        // seam falls back to a plain LWW import.
        if let importer {
          let (_, didImport) = try await importer.importListIfAbsent(
            id: list.id,
            name: list.name,
            description: list.description.flatMap { $0.isEmpty ? nil : $0 },
            color: list.color,
            icon: list.icon,
            aiNotes: list.aiNotes,
            archivedAt: list.archivedAt,
            position: list.position)
          if didImport { imported += 1 } else { skipped += 1 }
        } else {
          _ = try await core.importList(
            id: list.id,
            name: list.name,
            description: list.description.flatMap { $0.isEmpty ? nil : $0 },
            color: list.color,
            icon: list.icon,
            aiNotes: list.aiNotes,
            archivedAt: list.archivedAt,
            position: list.position)
          imported += 1
        }
      } catch {
        errors.append(
          LorvexImportIssue(
            category: .lists, record: .named(id: list.id, name: list.name),
            outcome: .notImported, detail: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(category: .lists, imported: imported, skipped: skipped), errors
    )
  }

  static func applyTags(
    _ tags: [ExportTag], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportIssue]) {
    guard let importer = core as? any LorvexNativeImportServicing else {
      let errors = tags.map {
        LorvexImportIssue(
          category: .tags, record: .named(id: $0.id, name: $0.displayName),
          outcome: .notImported, detail: "Tag import is unsupported by this backend.")
      }
      return (
        LorvexImportCategoryResult(category: .tags, imported: 0, skipped: tags.count),
        errors
      )
    }
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportIssue] = []
    for tag in tags {
      do {
        // Atomic non-destructive restore, resolving by id OR name the way the
        // importer resolves a tag: skip a tag a concurrent write already holds or
        // the user deleted after the backup, in one transaction with the insert.
        if try await importer.importTagIfAbsent(tag) {
          imported += 1
        } else {
          skipped += 1
        }
      } catch {
        errors.append(
          LorvexImportIssue(
            category: .tags, record: .named(id: tag.id, name: tag.displayName),
            outcome: .notImported, detail: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(category: .tags, imported: imported, skipped: skipped), errors
    )
  }

  static func applyHabits(
    _ habits: [ExportHabit], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportIssue]) {
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportIssue] = []
    // Restore each habit record atomically when the backend supports it: a
    // presence + tombstone guard, then upsert + completions + skipped days + reminder policies,
    // all in one transaction. So the restore never overwrites a habit a concurrent
    // create landed nor resurrects one the user deleted after the backup (either
    // would mint a dominating HLC and re-propagate the habit fleet-wide), and a
    // completion/policy failure rolls the whole habit — and its outbox envelopes —
    // back. Fall back to a best-effort per-operation restore otherwise.
    let importer = core as? any LorvexNativeImportServicing
    for habit in habits {
      do {
        if let importer {
          if try await importer.importHabitRecordTransactionally(habit) {
            imported += 1
          } else {
            skipped += 1
          }
        } else {
          try await applyHabitPerOperation(habit, using: core)
          imported += 1
        }
      } catch {
        errors.append(
          LorvexImportIssue(
            category: .habits, record: .named(id: habit.id, name: habit.name),
            outcome: .notImported, detail: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(category: .habits, imported: imported, skipped: skipped), errors
    )
  }

  /// Best-effort per-operation habit restore for a backend without the
  /// transactional record seam: upsert the habit, then its completions, skipped
  /// days and reminder policies as independent operations.
  private static func applyHabitPerOperation(
    _ habit: ExportHabit, using core: any LorvexCoreServicing
  ) async throws {
    _ = try await core.importHabit(
      id: habit.id,
      name: habit.name,
      icon: habit.icon,
      color: habit.color,
      cue: habit.cue.isEmpty ? nil : habit.cue,
      frequencyType: habit.frequencyType,
      weekdays: habit.weekdays,
      perPeriodTarget: habit.perPeriodTarget,
      dayOfMonth: habit.dayOfMonth,
      targetCount: habit.targetCount,
      milestoneTarget: habit.milestoneTarget,
      archived: habit.archived,
      position: habit.position,
      createdAt: habit.createdAt)
    if !habit.completions.isEmpty {
      guard let completionImporter = core as? any LorvexNativeImportServicing else {
        throw LorvexCoreError.unsupportedOperation(
          "Habit completion history restore is not supported by this backend.")
      }
      for completion in habit.completions {
        try await completionImporter.importHabitCompletion(
          habitID: habit.id, completion: completion)
      }
    }
    if !habit.skips.isEmpty {
      guard let skipImporter = core as? any LorvexNativeImportServicing else {
        throw LorvexCoreError.unsupportedOperation(
          "Habit skipped-day restore is not supported by this backend.")
      }
      for skip in habit.skips {
        try await skipImporter.importHabitSkip(habitID: habit.id, skip: skip)
      }
    }
    if !habit.reminderPolicies.isEmpty {
      guard let policyImporter = core as? any LorvexNativeImportServicing else {
        throw LorvexCoreError.unsupportedOperation(
          "Habit reminder policy restore is not supported by this backend.")
      }
      for policy in habit.reminderPolicies {
        try await policyImporter.importHabitReminderPolicy(habitID: habit.id, policy: policy)
      }
    }
  }

  /// Restore Calendar Events and their internal durable boundaries as one
  /// semantic unit. The backend owns the atomic bundle transaction through
  /// ``LorvexNativeImportServicing``; a backend without that seam restores no
  /// calendar data and reports one error when the payload carries any.
  static func applyCalendarBundle(
    cutovers: [ExportCalendarSeriesCutover], events: [ExportCalendarEvent],
    using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportIssue]) {
    guard let importer = core as? any LorvexNativeImportServicing else {
      return (
        LorvexImportCategoryResult(
          category: .calendarEvents, imported: 0, skipped: events.count),
        cutovers.isEmpty && events.isEmpty
          ? []
          : [
            LorvexImportIssue(
              category: .calendarEvents, record: .wholeCategory, outcome: .notImported,
              detail: "Calendar event restore is not supported by this backend.")
          ])
    }
    do {
      let result = try await importer.importCalendarBundle(cutovers: cutovers, events: events)
      return (
        LorvexImportCategoryResult(
          category: .calendarEvents,
          imported: result.importedEvents,
          skipped: result.skippedEvents),
        [])
    } catch {
      return (
        LorvexImportCategoryResult(
          category: .calendarEvents, imported: 0, skipped: events.count),
        [
          LorvexImportIssue(
            category: .calendarEvents, record: .wholeCategory, outcome: .notImported,
            detail: error.localizedDescription)
        ])
    }
  }
}
