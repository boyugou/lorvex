import Foundation
import LorvexDomain

extension LorvexDataImporter {
  static func applyMemory(
    _ entries: [ExportMemoryEntry], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportError]) {
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportError] = []
    let importer = core as? any LorvexNativeImportServicing
    for entry in entries {
      do {
        if let importer {
          // Atomic non-destructive restore: skip a key a concurrent write already
          // holds (no overwrite) or a memory the user deleted after the backup (no
          // resurrection at a fresh dominating import HLC), in one transaction with
          // the write. A new key still inserts.
          let (_, didImport) = try await importer.importMemoryEntryIfAbsent(entry)
          if didImport { imported += 1 } else { skipped += 1 }
        } else {
          // Best-effort for a backend without the restore capability: the latest
          // content survives; the exported timestamp does not.
          _ = try await core.upsertMemory(key: entry.key, content: entry.content)
          imported += 1
        }
      } catch {
        errors.append(
          LorvexImportError(
            category: .memory, recordRef: entry.key, message: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(category: .memory, imported: imported, skipped: skipped), errors
    )
  }

  static func applyDailyReviews(
    _ reviews: [ExportDailyReview], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportError]) {
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportError] = []
    let importer = core as? any LorvexNativeImportServicing
    for review in reviews {
      do {
        // Atomic non-destructive restore: a stale backup must not overwrite a daily
        // review already present locally (its fresh dominating HLC would revert
        // newer journal content and re-propagate the regression), nor resurrect one
        // the user deleted after the backup. The presence + tombstone check and the
        // upsert share one transaction. A date not present locally still imports; a
        // backend without the native seam falls back to a plain LWW import.
        if let importer {
          let didImport = try await importer.importDailyReviewIfAbsent(
            date: review.date,
            summary: review.summary,
            mood: review.mood,
            energyLevel: review.energyLevel,
            wins: review.wins.isEmpty ? nil : review.wins,
            blockers: review.blockers.isEmpty ? nil : review.blockers,
            learnings: review.learnings.isEmpty ? nil : review.learnings,
            timezone: review.timezone,
            updatedAt: review.updatedAt,
            linkedTaskIDs: review.linkedTaskIDs,
            linkedListIDs: review.linkedListIDs)
          if didImport { imported += 1 } else { skipped += 1 }
        } else {
          _ = try await core.importDailyReview(
            date: review.date,
            summary: review.summary,
            mood: review.mood,
            energyLevel: review.energyLevel,
            wins: review.wins.isEmpty ? nil : review.wins,
            blockers: review.blockers.isEmpty ? nil : review.blockers,
            learnings: review.learnings.isEmpty ? nil : review.learnings,
            timezone: review.timezone,
            updatedAt: review.updatedAt,
            linkedTaskIDs: review.linkedTaskIDs,
            linkedListIDs: review.linkedListIDs)
          imported += 1
        }
      } catch {
        errors.append(
          LorvexImportError(
            category: .dailyReviews, recordRef: review.date,
            message: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(category: .dailyReviews, imported: imported, skipped: skipped),
      errors
    )
  }

  static func applyPreferences(
    _ preferences: [ExportPreference], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportError]) {
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportError] = []
    for preference in preferences {
      // Device-local preferences encode one device's private/config state, and
      // control-plane preferences have dedicated account metadata. An import
      // must not materialize either as an ordinary preference row.
      guard !PreferenceKeys.isExcludedFromPreferenceEntitySync(preference.key) else {
        skipped += 1
        continue
      }
      do {
        // Preferences are singletons that carry read-time defaults, so a fresh
        // device may already hold a default `working_hours`/`timezone` row before
        // any restore. Unlike the user-authored content categories, importing a
        // preference is intentionally last-writer-wins (restore your settings)
        // rather than skip-if-exists — skipping would refuse to restore the user's
        // real value onto a device sitting on a default.
        _ = try await core.setPreference(key: preference.key, value: preference.value)
        imported += 1
      } catch {
        errors.append(
          LorvexImportError(
            category: .preferences, recordRef: preference.key,
            message: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(category: .preferences, imported: imported, skipped: skipped),
      errors
    )
  }

  static func applyCurrentFocus(
    _ entries: [ExportCurrentFocus], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportError]) {
    guard let importer = core as? any LorvexNativeImportServicing else {
      return unsupportedFocusResult(.currentFocus, entries.map(\.date))
    }
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportError] = []
    for entry in entries {
      do {
        // Atomic non-destructive restore: skip a date a concurrent write already
        // holds (a fresh-HLC import would revert a newer local plan and re-propagate
        // it) or one the user cleared after the backup, in one transaction with the
        // write. A date not present locally still imports.
        if try await importer.importCurrentFocusIfAbsent(entry) {
          imported += 1
        } else {
          skipped += 1
        }
      } catch {
        errors.append(
          LorvexImportError(
            category: .currentFocus, recordRef: entry.date, message: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(category: .currentFocus, imported: imported, skipped: skipped),
      errors
    )
  }

  static func applyFocusSchedules(
    _ schedules: [ExportFocusSchedule], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportError]) {
    guard let importer = core as? any LorvexNativeImportServicing else {
      return unsupportedFocusResult(.focusSchedules, schedules.map(\.date))
    }
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportError] = []
    for schedule in schedules {
      do {
        // Atomic non-destructive restore: skip a date a concurrent write already
        // holds (a fresh-HLC import would revert a newer local schedule and
        // re-propagate it) or one the user cleared after the backup, in one
        // transaction with the write. A date not present locally still imports.
        if try await importer.importFocusScheduleIfAbsent(schedule) {
          imported += 1
        } else {
          skipped += 1
        }
      } catch {
        errors.append(
          LorvexImportError(
            category: .focusSchedules, recordRef: schedule.date,
            message: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(category: .focusSchedules, imported: imported, skipped: skipped),
      errors
    )
  }

  private static func unsupportedFocusResult(
    _ category: LorvexDataExportCategory, _ refs: [String]
  ) -> (LorvexImportCategoryResult, [LorvexImportError]) {
    let errors = refs.map {
      LorvexImportError(
        category: category, recordRef: $0,
        message: "Focus aggregate import is unsupported by this backend.")
    }
    return (
      LorvexImportCategoryResult(category: category, imported: 0, skipped: refs.count),
      errors
    )
  }

  static func applyTaskCalendarEventLinks(
    _ links: [ExportTaskCalendarEventLink], using core: any LorvexCoreServicing
  ) async -> (LorvexImportCategoryResult, [LorvexImportError]) {
    guard let importer = core as? any LorvexNativeImportServicing else {
      let errors = links.map {
        LorvexImportError(
          category: .taskCalendarEventLinks,
          recordRef: "\($0.taskID):\($0.calendarEventID)",
          message: "Task-calendar link import is unsupported by this backend.")
      }
      return (
        LorvexImportCategoryResult(
          category: .taskCalendarEventLinks, imported: 0, skipped: links.count),
        errors
      )
    }
    var imported = 0
    var skipped = 0
    var errors: [LorvexImportError] = []
    for link in links {
      do {
        // The restore runs under `import` provenance, so `importTaskCalendarEventLink`
        // refuses to resurrect a link the user unlinked after the backup (returns
        // `false`); a fresh link — or one already present — counts as imported.
        if try await importer.importTaskCalendarEventLink(link) {
          imported += 1
        } else {
          skipped += 1
        }
      } catch {
        errors.append(
          LorvexImportError(
            category: .taskCalendarEventLinks,
            recordRef: "\(link.taskID):\(link.calendarEventID)",
            message: error.localizedDescription))
      }
    }
    return (
      LorvexImportCategoryResult(
        category: .taskCalendarEventLinks, imported: imported, skipped: skipped),
      errors
    )
  }
}
