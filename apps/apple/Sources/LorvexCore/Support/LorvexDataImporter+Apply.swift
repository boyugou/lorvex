import Foundation
import os

extension LorvexDataImporter {
  /// Thrown by a host's import action when another import, factory reset, or
  /// iCloud-data deletion is still running.
  public struct BusyError: Error, Equatable, Sendable {
    public init() {}
  }

  /// Restore a decoded import.
  public static func apply(
    plan: LorvexImportPlan,
    decoded: DecodedImport,
    using core: any LorvexCoreServicing
  ) async -> LorvexImportSummary {
    await apply(plan: plan, payload: decoded.payload, using: core)
  }

  /// Restore the supported categories of `payload`. The `plan` is accepted so
  /// apply matches exactly what the user confirmed; only supported categories
  /// are written. Records that do not come back whole are collected as issues
  /// in the returned summary, each logged privately with its English finding;
  /// a backup that fails the whole-backup preflight is refused before anything
  /// is written, and the summary carries only the reason.
  public static func apply(
    plan: LorvexImportPlan,
    payload: LorvexDataExportPayload,
    using core: any LorvexCoreServicing
  ) async -> LorvexImportSummary {
    do {
      try BackupV1PayloadPreflight.validate(payload)
    } catch {
      // The preflight judges the backup as a whole, and its findings can span
      // several categories, so a refusal belongs to no single category.
      let rejection = (error as? ImportError) ?? .inconsistentBackupContents("\(error)")
      importLog.error("Import rejected: \(rejection.diagnosticDescription, privacy: .private)")
      return LorvexImportSummary(rejection: rejection)
    }
    // Bind `import` provenance for the whole restore. The id-preserving core
    // importers this fans out to carry no explicit initiator and inherit the
    // ambient ``SwiftLorvexCoreService/currentInitiator`` — the MCP host binds
    // `assistant`, a human surface leaves the `user` default — so this is the
    // single site that stamps a data-file restore's `ai_changelog` rows as
    // `import`, keeping a replayed backup provenance-distinct from live actions.
    return await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.importAttribution
    ) {
      var results: [LorvexImportCategoryResult] = []
      var issues: [LorvexImportIssue] = []

      func run(
        _ category: LorvexDataExportCategory,
        _ apply: () async -> (LorvexImportCategoryResult, [LorvexImportIssue])
      ) async {
        guard plan.entries.contains(where: { $0.category == category && $0.isSupported }) else {
          return
        }
        let (result, categoryIssues) = await apply()
        results.append(result)
        issues.append(contentsOf: categoryIssues)
      }

      // Lists before tasks: a restored task's `listID` must reference a list
      // that already exists. Tags before tasks: task import reuses/restores tag
      // roots by lookup key instead of minting replacement ids.
      await run(.lists) { await applyLists(payload.lists ?? [], using: core) }
      await run(.tags) { await applyTags(payload.tags ?? [], using: core) }
      await run(.tasks) {
        await applyTasks(
          payload.tasks ?? [], nativeTaskGraph: payload.nativeTaskGraph,
          permitExactNativeRestore: payload.nativeTaskGraph.map {
            BackupV1TaskProjectionConsistency.permitsExactNativeRestore(
              portableTags: payload.tags, nativeGraph: $0)
          } ?? false,
          using: core)
      }
      await run(.habits) { await applyHabits(payload.habits ?? [], using: core) }
      await run(.calendarEvents) {
        await applyCalendarBundle(
          cutovers: payload.calendarSeriesCutovers ?? [],
          events: payload.calendarEvents ?? [],
          using: core)
      }
      await run(.dailyReviews) { await applyDailyReviews(payload.dailyReviews ?? [], using: core) }
      await run(.dailyBriefings) {
        await applyDailyBriefings(payload.dailyBriefings ?? [], using: core)
      }
      await run(.taskCalendarEventLinks) {
        await applyTaskCalendarEventLinks(
          payload.taskCalendarEventLinks ?? [],
          taskTitles: Dictionary(
            (payload.tasks ?? []).map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }),
          using: core)
      }
      await run(.memory) { await applyMemory(payload.memory ?? [], using: core) }
      await run(.preferences) { await applyPreferences(payload.preferences ?? [], using: core) }

      for issue in issues {
        let record = issue.recordID ?? "whole category"
        importLog.error(
          """
          Import issue in \(issue.category.rawValue, privacy: .public): \
          \(record, privacy: .private): \(issue.detail, privacy: .private)
          """)
      }
      return LorvexImportSummary(results: results, issues: issues)
    }
  }
}
