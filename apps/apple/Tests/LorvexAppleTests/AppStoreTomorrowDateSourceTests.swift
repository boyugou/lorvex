import Foundation
import Testing

@Suite("Tomorrow date source")
struct TomorrowDateSourceTests {
  @Test("defer actions share the AppStore tomorrowDate helper")
  func deferActionsShareTomorrowDateHelper() throws {
    let storesRoot = packageRoot().appending(path: "Sources/LorvexApple/Stores")
    let dateFormatting = try source(
      storesRoot.appending(path: "AppStoreDateFormatting.swift"))
    #expect(dateFormatting.contains("func tomorrowDate() throws -> Date"))
    #expect(dateFormatting.contains("forLogicalDay: logicalTodayDateString"))
    // The day-choice defer presets (tomorrow / in N days / next week) all flow
    // through this single offset helper rather than duplicating the local→UTC
    // re-anchor per call site.
    #expect(dateFormatting.contains("func deferStorageDate(daysFromNow days: Int) -> Date?"))
    // `dateString(daysFromToday:)` delegates to the Calendar-based
    // `dateString(days:from:)` so day arithmetic stays DST-safe rather than
    // stepping by fixed 86400-second intervals.
    #expect(dateFormatting.contains("dateString(days: days, from: Date())"))
    #expect(!dateFormatting.contains("addingTimeInterval(TimeInterval(days)"))

    // The four surfaces' batch defers are one shared implementation in
    // AppStoreBatchTaskActions (`deferBatch(on:)`), which lands on tomorrow via
    // the throwing `tomorrowDate()` helper; the per-surface files are forwarders.
    let batchActions = try source(storesRoot.appending(path: "AppStoreBatchTaskActions.swift"))
    #expect(
      batchActions.contains("until: tomorrowDate()"),
      "AppStoreBatchTaskActions.swift should use the shared tomorrowDate helper")
    assertNoDuplicatedTomorrowCalculation(batchActions, file: "AppStoreBatchTaskActions.swift")
    for file in [
      "AppStoreTaskWorkspaceBatchActions.swift",
      "AppStoreListTaskBatchActions.swift",
      "AppStoreFocusTaskBatchActions.swift",
    ] {
      let contents = try source(storesRoot.appending(path: file))
      #expect(
        contents.contains("deferBatch(on:"),
        "\(file) should forward to the shared deferBatch(on:)")
      assertNoDuplicatedTomorrowCalculation(contents, file: file)
    }

    // The selected-task / row defer family supports a day choice, so it routes
    // through the offset helper instead of the tomorrow-only one.
    let selectedTaskActions = try source(
      storesRoot.appending(path: "AppStoreSelectedTaskActions.swift"))
    #expect(
      selectedTaskActions.contains("deferStorageDate(daysFromNow: 1)"),
      "AppStoreSelectedTaskActions.swift should use the shared offset helper")
    assertNoDuplicatedTomorrowCalculation(
      selectedTaskActions, file: "AppStoreSelectedTaskActions.swift")
  }

  private func assertNoDuplicatedTomorrowCalculation(_ contents: String, file: String) {
    #expect(
      !contents.contains("Calendar.current.date(byAdding: .day, value: 1, to: now())"),
      "\(file) should not duplicate tomorrow-date calculation")
    #expect(
      !contents.contains("Couldn't compute tomorrow's date."),
      "\(file) should not duplicate tomorrow-date error wording")
  }

  @Test("mobile defer actions share the MobileStore tomorrowDate helper")
  func mobileDeferActionsShareTomorrowDateHelper() throws {
    let actions = try source(
      packageRoot().appending(path: "Sources/LorvexMobile/MobileStoreTaskActions.swift"))
    #expect(actions.contains("private func tomorrowDate() throws -> Date"))
    #expect(actions.contains("forLogicalDay: logicalTodayString"))
    #expect(!actions.contains("Calendar.current.date(byAdding: .day"))
    #expect(actions.contains("try await core.deferTask(id: id, until: tomorrowDate())"))
    #expect(
      actions.contains("try await core.batchDeferTasks(ids: uniqueIDs, until: tomorrowDate())"))
    #expect(!actions.contains("?? now()"))
  }

  @Test("watch defer actions share the LorvexWatchStore tomorrowDate helper")
  func watchDeferActionsShareTomorrowDateHelper() throws {
    let actions = try source(
      packageRoot().appending(path: "Sources/LorvexWatch/LorvexWatchStoreTaskActions.swift"))
    #expect(actions.contains("private func tomorrowDate() async throws -> Date"))
    #expect(actions.contains("let day = try await mutationLogicalDay()"))
    #expect(!actions.contains("Calendar.current.date(byAdding: .day"))
    #expect(actions.components(separatedBy: "let tomorrow = try await tomorrowDate()").count - 1 == 2)
    #expect(
      actions.components(
        separatedBy: "LorvexDateFormatters.ymdUTC.string(from: tomorrow)"
      ).count - 1 == 2)
    #expect(actions.contains("try await core.deferTask(id: task.id, until: tomorrow)"))
    #expect(actions.contains("try await core.deferTask(id: id, until: tomorrow)"))
    #expect(!actions.contains("?? self.now()"))
  }
}

private func source(_ url: URL) throws -> String {
  try String(contentsOf: url, encoding: .utf8)
}

private func packageRoot() -> URL {
  var url = URL(fileURLWithPath: #filePath)
  while url.lastPathComponent != "apps" {
    url.deleteLastPathComponent()
  }
  return url.appending(path: "apple")
}
