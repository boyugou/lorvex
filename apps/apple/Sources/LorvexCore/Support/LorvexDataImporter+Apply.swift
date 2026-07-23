import Foundation

extension LorvexDataImporter {
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
  /// are written. Per-record failures are collected in the returned summary.
  public static func apply(
    plan: LorvexImportPlan,
    payload: LorvexDataExportPayload,
    using core: any LorvexCoreServicing
  ) async -> LorvexImportSummary {
    do {
      try BackupV1PayloadPreflight.validate(payload)
    } catch {
      // Semantic preflight validates the artifact as a whole and can report a
      // relationship spanning multiple categories. The summary model requires
      // a category, so anchor the artifact-level failure to the first supported
      // category the user actually confirmed instead of falsely labelling every
      // failure as a native-task-graph or calendar-cutover error.
      let category =
        plan.entries.first(where: { $0.isSupported })?.category
        ?? self.plan(for: payload).entries.first(where: { $0.isSupported })?.category
        ?? .tasks
      return LorvexImportSummary(
        results: [
          LorvexImportCategoryResult(category: category, imported: 0, skipped: 0)
        ],
        errors: [
          LorvexImportError(
            category: category,
            recordRef: "backup",
            message: error.localizedDescription)
        ])
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
      var errors: [LorvexImportError] = []

      func run(
        _ category: LorvexDataExportCategory,
        _ apply: () async -> (LorvexImportCategoryResult, [LorvexImportError])
      ) async {
        guard plan.entries.contains(where: { $0.category == category && $0.isSupported }) else {
          return
        }
        let (result, recordErrors) = await apply()
        results.append(result)
        errors.append(contentsOf: recordErrors)
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
      await run(.currentFocus) { await applyCurrentFocus(payload.currentFocus ?? [], using: core) }
      await run(.focusSchedules) {
        await applyFocusSchedules(payload.focusSchedules ?? [], using: core)
      }
      await run(.taskCalendarEventLinks) {
        await applyTaskCalendarEventLinks(payload.taskCalendarEventLinks ?? [], using: core)
      }
      await run(.memory) { await applyMemory(payload.memory ?? [], using: core) }
      await run(.preferences) { await applyPreferences(payload.preferences ?? [], using: core) }

      return LorvexImportSummary(results: results, errors: errors)
    }
  }
}
