import Foundation
import LorvexDomain
import LorvexStore
import Testing

@testable import LorvexCore

@Suite("Public backup restore safety")
struct BackupRestoreSafetyTests {
  private static let listID = "11111111-1111-4111-8111-111111111111"
  private static let tagID = "22222222-2222-4222-8222-222222222222"
  private static let taskID = "33333333-3333-4333-8333-333333333333"
  private static let omittedTaskID = "44444444-4444-4444-8444-444444444444"

  @Test("production-shaped v1 fixture restores into a fresh current store")
  func restoresProductionShapedV1Fixture() async throws {
    let data = Data(BackupV1GoldenFixture.singleFileJSON.utf8)
    let (plan, decoded) = try LorvexDataImporter.plan(from: data)
    let service = try Self.makeFreshService()

    let summary = await LorvexDataImporter.apply(
      plan: plan, decoded: decoded, using: service)

    #expect(summary.errors.isEmpty, "Golden restore errors: \(summary.errors)")
    #expect(try await service.loadTask(id: Self.taskID).title == "Decode every v1 shape")
    #expect(try await service.loadLists().lists.contains { $0.id == Self.listID })
    #expect(
      try await service.loadHabits(date: "2026-07-17").habits.contains {
        $0.id == "77777777-7777-4777-8777-777777777777"
      })
  }

  @Test("public v1 JSON has a closed top-level inventory and exact partial counts")
  func singleFileJSONEnforcesInventoryAndCounts() throws {
    let validPartial = #"""
      {
        "formatVersion":"1",
        "manifest":{
          "formatVersion":"1","schemaVersion":"1",
          "source":{"platform":"apple"},"entityCounts":{"lists":1}
        },
        "lists":[{
          "id":"11111111-1111-4111-8111-111111111111",
          "name":"Only list","position":0
        }]
      }
      """#
    let decoded = try LorvexDataImporter.decode(Data(validPartial.utf8))
    #expect(decoded.lists?.count == 1)
    #expect(decoded.tasks == nil)

    #expect(throws: LorvexDataImporter.ImportError.unexpectedJSONMember("habit")) {
      _ = try LorvexDataImporter.decode(Data(Self.unknownMemberDocument.utf8))
    }
    #expect(
      throws: LorvexDataImporter.ImportError.manifestCountMismatch(
        "habits holds 0 records but the manifest declares 2")
    ) {
      _ = try LorvexDataImporter.decode(Data(Self.wrongCountDocument.utf8))
    }
    #expect(
      throws: LorvexDataImporter.ImportError.manifestCountMismatch(
        "manifest lists habits not present in the file")
    ) {
      _ = try LorvexDataImporter.decode(Data(Self.missingCategoryDocument.utf8))
    }
    #expect(throws: LorvexDataImporter.ImportError.missingPayloadManifest) {
      _ = try LorvexDataImporter.decode(
        Data(#"{"formatVersion":"1","lists":[]}"#.utf8))
    }
    #expect(
      throws: LorvexDataImporter.ImportError.malformedJSON(
        "top-level tasks must be an array rather than null")
    ) {
      _ = try LorvexDataImporter.decode(Data(Self.nullCategoryDocument.utf8))
    }
    #expect(
      throws: LorvexDataImporter.ImportError.manifestCountMismatch(
        "nativeTaskGraph is present without its tasks category")
    ) {
      _ = try LorvexDataImporter.decode(Data(Self.orphanedNativeGraphDocument.utf8))
    }
  }

  @Test("public v1 JSON and ZIP reject duplicate aggregate identities")
  func publicV1ContainersRejectDuplicateIdentities() throws {
    let duplicateLists = #"""
      [{
        "id":"11111111-1111-4111-8111-111111111111",
        "name":"First","position":0
      },{
        "id":"11111111-1111-4111-8111-111111111111",
        "name":"Second","position":1
      }]
      """#
    let expected = LorvexDataImporter.ImportError.inconsistentBackupContents(
      "duplicate list id '11111111-1111-4111-8111-111111111111'")

    let json = #"""
      {
        "formatVersion":"1",
        "manifest":{
          "formatVersion":"1","schemaVersion":"1",
          "source":{"platform":"apple"},"entityCounts":{"lists":2}
        },
        "lists":\#(duplicateLists)
      }
      """#
    #expect(throws: expected) {
      _ = try LorvexDataImporter.decode(Data(json.utf8))
    }

    let zip = try LorvexZipArchive.archive(entries: [
      .init(
        path: "manifest.json",
        data: Data(#"{"schemaVersion":"1","fileCounts":{"lists":2}}"#.utf8)),
      .init(path: "lists.json", data: Data(duplicateLists.utf8)),
    ])
    #expect(throws: expected) {
      _ = try LorvexDataImporter.decode(zip)
    }
  }

  @Test("public v1 JSON and ZIP reject schedule references outside an included full category")
  func publicV1ContainersRejectDanglingScheduleReferences() throws {
    let tasks = #"""
      [{
        "id":"33333333-3333-4333-8333-333333333333",
        "title":"Included task","priority":"P2","status":"open"
      }]
      """#
    let schedules = #"""
      [{
        "date":"2026-07-21",
        "blocks":[{
          "position":0,"blockType":"task","startMinutes":540,"endMinutes":600,
          "taskID":"44444444-4444-4444-8444-444444444444"
        }]
      }]
      """#
    let expected = LorvexDataImporter.ImportError.inconsistentBackupContents(
      "focus-schedule 2026-07-21 references omitted task \(Self.omittedTaskID)")

    let json = #"""
      {
        "formatVersion":"1",
        "manifest":{
          "formatVersion":"1","schemaVersion":"1",
          "source":{"platform":"apple"},
          "entityCounts":{"tasks":1,"focus_schedules":1}
        },
        "tasks":\#(tasks),
        "focusSchedules":\#(schedules)
      }
      """#
    #expect(throws: expected) {
      _ = try LorvexDataImporter.decode(Data(json.utf8))
    }

    let zip = try LorvexZipArchive.archive(entries: [
      .init(
        path: "manifest.json",
        data: Data(
          #"{"schemaVersion":"1","fileCounts":{"tasks":1,"focus_schedules":1}}"#.utf8)),
      .init(path: "tasks.json", data: Data(tasks.utf8)),
      .init(path: "focus_schedules.json", data: Data(schedules.utf8)),
    ])
    #expect(throws: expected) {
      _ = try LorvexDataImporter.decode(zip)
    }
  }

  @Test("public v1 rejects day-plan roots that reference an archived task")
  func publicV1RejectsArchivedTaskDayPlanReferences() throws {
    let archivedTask = ExportTask(
      id: Self.taskID, title: "In Trash", priority: "P2", status: "open",
      dueDate: nil, estimatedMinutes: nil,
      archivedAt: "2026-07-20T12:00:00.000Z")

    let currentFocusPayload = LorvexDataExportPayload(
      tasks: [archivedTask],
      currentFocus: [
        ExportCurrentFocus(date: "2026-07-21", taskIDs: [Self.taskID])
      ])
    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "current-focus 2026-07-21 references archived task \(Self.taskID)")
    ) {
      _ = try LorvexDataExporter.render(payload: currentFocusPayload, format: .json)
    }

    let schedulePayload = LorvexDataExportPayload(
      tasks: [archivedTask],
      focusSchedules: [
        ExportFocusSchedule(
          date: "2026-07-21",
          blocks: [
            ExportFocusScheduleBlock(
              position: 0, blockType: "task", startMinutes: 540, endMinutes: 600,
              taskID: Self.taskID)
          ])
      ])
    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "focus-schedule 2026-07-21 references archived task \(Self.taskID)")
    ) {
      _ = try LorvexDataExporter.render(payload: schedulePayload, format: .json)
    }
  }

  @Test("public v1 rejects daily-review links outside included full categories")
  func publicV1RejectsDanglingDailyReviewLinks() throws {
    let baseManifest = #"""
      "formatVersion":"1","schemaVersion":"1",
      "source":{"platform":"apple"},
      "entityCounts":{"tasks":1,"lists":1,"daily_reviews":1}
      """#
    let tasks = #"""
      [{
        "id":"33333333-3333-4333-8333-333333333333",
        "title":"Included task","priority":"P2","status":"open"
      }]
      """#
    let lists = #"""
      [{
        "id":"11111111-1111-4111-8111-111111111111",
        "name":"Included list","position":0
      }]
      """#

    func document(linkedTaskID: String, linkedListID: String) -> String {
      #"""
      {
        "formatVersion":"1",
        "manifest":{\#(baseManifest)},
        "tasks":\#(tasks),
        "lists":\#(lists),
        "dailyReviews":[{
          "date":"2026-07-21","summary":"Review","mood":4,"energyLevel":3,
          "wins":"","blockers":"","learnings":"",
          "linkedTaskIDs":["\#(linkedTaskID)"],
          "linkedListIDs":["\#(linkedListID)"]
        }]
      }
      """#
    }

    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "daily-review 2026-07-21 task link references omitted identity \(Self.omittedTaskID)")
    ) {
      _ = try LorvexDataImporter.decode(
        Data(
          document(linkedTaskID: Self.omittedTaskID, linkedListID: Self.listID).utf8))
    }

    let omittedListID = "55555555-5555-4555-8555-555555555555"
    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "daily-review 2026-07-21 list link references omitted identity \(omittedListID)")
    ) {
      _ = try LorvexDataImporter.decode(
        Data(document(linkedTaskID: Self.taskID, linkedListID: omittedListID).utf8))
    }
  }

  @Test("public v1 rejects occurrence decisions whose master is omitted")
  func publicV1RejectsDanglingOccurrenceDecision() throws {
    let decisionID = "66666666-6666-4666-8666-666666666666"
    let omittedMasterID = "77777777-7777-4777-8777-777777777777"
    let payload = LorvexDataExportPayload(
      calendarEvents: [
        ExportCalendarEvent(
          id: decisionID,
          title: "Detached occurrence",
          startDate: "2026-07-21",
          startTime: "09:00",
          endDate: "2026-07-21",
          endTime: "10:00",
          allDay: false,
          seriesId: omittedMasterID,
          recurrenceInstanceDate: "2026-07-21",
          occurrenceState: "replacement",
          recurrenceGeneration: "1784653200000_0000_1111111111111111")
      ])

    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "calendar occurrence \(decisionID) references omitted series \(omittedMasterID)")
    ) {
      _ = try LorvexDataExporter.render(payload: payload, format: .json)
    }
  }

  @Test("public v1 rejects default-list preference outside included lists")
  func publicV1RejectsDanglingDefaultListPreference() throws {
    let omittedListID = "55555555-5555-4555-8555-555555555555"
    let payload = LorvexDataExportPayload(
      lists: [
        ExportList(id: Self.listID, name: "Included list")
      ],
      preferences: [
        ExportPreference(key: PreferenceKeys.prefDefaultListId, value: "\"\(omittedListID)\"")
      ])

    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "default_list_id preference references omitted list \(omittedListID)")
    ) {
      _ = try LorvexDataExporter.render(payload: payload, format: .json)
    }
  }

  @Test("public v1 validates every importable ordinary preference value")
  func publicV1RejectsMalformedOrdinaryPreferences() throws {
    let invalidValues: [(key: String, value: String)] = [
      (PreferenceKeys.prefWorkingHours, #"{"start":9}"#),
      (PreferenceKeys.prefTimezone, #""Etc/GMT+8""#),
      (PreferenceKeys.prefDefaultListId, "true"),
      (PreferenceKeys.prefSetupCompleted, #""true""#),
      (PreferenceKeys.prefSetupSummary, "false"),
      (PreferenceKeys.prefSetupState, "[]"),
      (PreferenceKeys.prefRecordRawInput, "0"),
      ("unknown_preference", #""value""#),
    ]

    for invalid in invalidValues {
      let payload = LorvexDataExportPayload(
        preferences: [ExportPreference(key: invalid.key, value: invalid.value)])
      #expect(throws: LorvexDataImporter.ImportError.self) {
        _ = try LorvexDataExporter.render(payload: payload, format: .json)
      }
    }

    let invalidJSON = LorvexDataExportPayload(
      preferences: [
        ExportPreference(key: PreferenceKeys.prefWorkingHours, value: "not-json")
      ])
    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "preference 'working_hours' value is not valid stored JSON")
    ) {
      _ = try LorvexDataExporter.render(payload: invalidJSON, format: .json)
    }

    let expected = LorvexDataImporter.ImportError.inconsistentBackupContents(
      "preference 'working_hours' value is not valid stored JSON")
    let singleFile = #"""
      {
        "formatVersion":"1",
        "manifest":{
          "formatVersion":"1","schemaVersion":"1",
          "source":{"platform":"apple"},"entityCounts":{"preferences":1}
        },
        "preferences":[{"key":"working_hours","value":"not-json"}]
      }
      """#
    #expect(throws: expected) {
      _ = try LorvexDataImporter.decode(Data(singleFile.utf8))
    }

    let zip = try LorvexZipArchive.archive(entries: [
      .init(
        path: "manifest.json",
        data: Data(#"{"schemaVersion":"1","fileCounts":{"preferences":1}}"#.utf8)),
      .init(
        path: "preferences.json",
        data: Data(#"[{"key":"working_hours","value":"not-json"}]"#.utf8)),
    ])
    #expect(throws: expected) {
      _ = try LorvexDataImporter.decode(zip)
    }
  }

  @Test("preference preflight preserves local and control-plane import exclusions")
  func preferencePreflightPreservesImportExclusions() async throws {
    let core = try makeInMemoryCore()
    let payload = LorvexDataExportPayload(
      preferences: [
        ExportPreference(key: PreferenceKeys.prefLanguage, value: "not-json"),
        ExportPreference(key: PreferenceKeys.prefTheme, value: "not-json"),
        ExportPreference(
          key: PreferenceKeys.prefNotificationShowTaskNotes, value: "not-json"),
        ExportPreference(
          key: PreferenceKeys.prefAiChangelogRetentionPolicy, value: "not-json"),
        ExportPreference(
          key: PreferenceKeys.prefWorkingHours,
          value: #"{"start":"09:00","end":"17:00"}"#),
      ])

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: core)

    #expect(summary.errors.isEmpty)
    #expect(
      summary.results == [
        LorvexImportCategoryResult(category: .preferences, imported: 1, skipped: 4)
      ])
    #expect(
      try await core.getPreference(key: PreferenceKeys.prefWorkingHours)
        == #"{"end":"17:00","start":"09:00"}"#)
    #expect(try await core.getPreference(key: PreferenceKeys.prefLanguage) == nil)
    #expect(try await core.getPreference(key: PreferenceKeys.prefTheme) == nil)
    #expect(
      try await core.getPreference(key: PreferenceKeys.prefNotificationShowTaskNotes) == nil)
  }

  @Test("malformed preference aborts programmatic apply before any category writes")
  func malformedPreferenceCausesZeroWriteProgrammaticApply() async throws {
    let core = try makeInMemoryCore()
    let listID = "55555555-5555-4555-8555-555555555555"
    let payload = LorvexDataExportPayload(
      lists: [ExportList(id: listID, name: "Must not import")],
      preferences: [
        ExportPreference(
          key: PreferenceKeys.prefWorkingHours, value: #"{"start":"18:00","end":"09:00"}"#)
      ])

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: core)

    #expect(
      summary.results == [
        LorvexImportCategoryResult(category: .lists, imported: 0, skipped: 0)
      ])
    #expect(summary.errors.count == 1)
    #expect(summary.errors.first?.category == .lists)
    #expect(summary.errors.first?.recordRef == "backup")
    #expect(summary.errors.first?.message.contains("working_hours.end must be after") == true)
    #expect(try await core.loadLists().lists.contains { $0.id == listID } == false)
    #expect(try await core.getPreference(key: PreferenceKeys.prefWorkingHours) == nil)
  }

  @Test("public v1 rejects natural-key collisions that cannot coexist in one store")
  func publicV1RejectsNaturalKeyCollisions() throws {
    let firstHabitID = "55555555-5555-4555-8555-555555555555"
    let secondHabitID = "66666666-6666-4666-8666-666666666666"
    let duplicateHabits = LorvexDataExportPayload(
      habits: [
        ExportHabit(
          id: firstHabitID, name: "Deep Work", cue: "", frequencyType: "daily",
          targetCount: 1),
        ExportHabit(
          id: secondHabitID, name: "  deep   work  ", cue: "", frequencyType: "daily",
          targetCount: 1),
      ])
    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "duplicate active habit lookup key 'deep work'")
    ) {
      _ = try LorvexDataExporter.render(payload: duplicateHabits, format: .json)
    }

    let timestamp = "2026-07-21T12:00:00.000Z"
    let duplicateReminderTimes = LorvexDataExportPayload(
      habits: [
        ExportHabit(
          id: firstHabitID, name: "Deep Work", cue: "", frequencyType: "daily",
          targetCount: 1,
          reminderPolicies: [
            ExportHabitReminderPolicy(
              id: "77777777-7777-4777-8777-777777777777",
              reminderTime: "09:00", enabled: true,
              createdAt: timestamp, updatedAt: timestamp),
            ExportHabitReminderPolicy(
              id: "88888888-8888-4888-8888-888888888888",
              reminderTime: "09:00", enabled: true,
              createdAt: timestamp, updatedAt: timestamp),
          ])
      ])
    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "duplicate habit \(firstHabitID) reminder time '09:00'")
    ) {
      _ = try LorvexDataExporter.render(payload: duplicateReminderTimes, format: .json)
    }
  }

  @Test("programmatic apply reports whole-backup preflight failures honestly")
  func programmaticApplyReportsWholeBackupPreflightFailure() async throws {
    let payload = LorvexDataExportPayload(
      habits: [
        ExportHabit(
          id: "55555555-5555-4555-8555-555555555555", name: "Deep Work",
          cue: "", frequencyType: "daily", targetCount: 1),
        ExportHabit(
          id: "66666666-6666-4666-8666-666666666666", name: " deep  work ",
          cue: "", frequencyType: "daily", targetCount: 1),
      ])
    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload,
      using: try makeInMemoryCore())

    #expect(
      summary.results == [
        LorvexImportCategoryResult(category: .habits, imported: 0, skipped: 0)
      ])
    #expect(summary.errors.count == 1)
    #expect(summary.errors.first?.category == .habits)
    #expect(summary.errors.first?.recordRef == "backup")
    #expect(
      summary.errors.first?.message.contains("duplicate active habit lookup key") == true)
  }

  @Test("public v1 rejects calendar segment topology before preview")
  func publicV1RejectsCalendarSegmentTopologyBeforePreview() throws {
    let boundaryID = "88888888-8888-4888-8888-888888888888"
    let lineageRootID = "99999999-9999-4999-8999-999999999999"
    let missingSegment = LorvexDataExportPayload(
      calendarSeriesCutovers: [
        ExportCalendarSeriesCutover(
          id: boundaryID, lineageRootId: lineageRootID,
          cutoverDate: "2026-07-21", state: "active")
      ],
      calendarEvents: [])
    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "active calendar boundary \(boundaryID) has no segment event")
    ) {
      _ = try LorvexDataExporter.render(payload: missingSegment, format: .json)
    }

    let orphanedSegment = LorvexDataExportPayload(
      calendarEvents: [
        ExportCalendarEvent(
          id: boundaryID, title: "Segment", startDate: "2026-07-21",
          startTime: "09:00", endDate: "2026-07-21", endTime: "10:00",
          allDay: false, seriesCutoverId: boundaryID)
      ])
    #expect(
      throws: LorvexDataImporter.ImportError.inconsistentBackupContents(
        "calendar segment \(boundaryID) references omitted boundary \(boundaryID)")
    ) {
      _ = try LorvexDataExporter.render(payload: orphanedSegment, format: .json)
    }
  }

  @Test("public v1 ZIP and producer enforce aggregate parent members")
  func zipAndProducerEnforceParentMemberRelationships() throws {
    let emptyGraph = NativeTaskGraphSnapshot(
      tasks: [], recurrenceExceptions: [], tagEdges: [], dependencyEdges: [],
      checklistItems: [], reminders: [])
    let orphanedGraphPayload = LorvexDataExportPayload(nativeTaskGraph: emptyGraph)
    let missingTasks = LorvexDataImporter.ImportError.manifestCountMismatch(
      "nativeTaskGraph is present without its tasks category")

    #expect(throws: missingTasks) {
      _ = try LorvexDataExporter.render(payload: orphanedGraphPayload, format: .json)
    }
    #expect(throws: missingTasks) {
      _ = try LorvexDataExporter.renderZip(
        payload: orphanedGraphPayload, generatedAt: nil, appVersion: nil)
    }

    let orphanedGraphArchive = try LorvexZipArchive.archive(entries: [
      .init(
        path: "manifest.json",
        data: Data(
          #"{"schemaVersion":"1","fileCounts":{"native_task_graph":1}}"#.utf8)),
      .init(
        path: "native_task_graph.json",
        data: Data(
          #"{"schemaVersion":"1","tasks":[],"recurrenceExceptions":[],"tagEdges":[],"dependencyEdges":[],"checklistItems":[],"reminders":[],"tombstones":[],"payloadShadows":[]}"#
            .utf8)),
    ])
    #expect(throws: missingTasks) {
      _ = try LorvexDataImporter.decode(orphanedGraphArchive)
    }

    let missingEvents = LorvexDataImporter.ImportError.manifestCountMismatch(
      "calendarSeriesCutovers is present without its calendar_events category")
    let orphanedCutoverPayload = LorvexDataExportPayload(
      calendarSeriesCutovers: [
        ExportCalendarSeriesCutover(
          id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
          lineageRootId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
          cutoverDate: "2026-07-17", state: "deleted")
      ])
    #expect(throws: missingEvents) {
      _ = try LorvexDataExporter.render(payload: orphanedCutoverPayload, format: .json)
    }
    #expect(throws: missingEvents) {
      _ = try LorvexDataExporter.renderZip(
        payload: orphanedCutoverPayload, generatedAt: nil, appVersion: nil)
    }

    let orphanedCutoverArchive = try LorvexZipArchive.archive(entries: [
      .init(
        path: "manifest.json",
        data: Data(
          #"{"schemaVersion":"1","fileCounts":{"calendar_series_cutovers":1}}"#.utf8)),
      .init(
        path: "calendar_series_cutovers.json",
        data: Data(
          #"[{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","lineageRootId":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","cutoverDate":"2026-07-17","state":"deleted"}]"#
            .utf8)),
    ])
    #expect(throws: missingEvents) {
      _ = try LorvexDataImporter.decode(orphanedCutoverArchive)
    }
  }

  @Test("public v1 native graph uses retained version-1 restore semantics")
  func v1NativeGraphUsesVersionedRestoreAdapter() throws {
    let graph = try Self.goldenNativeGraph()
    let plan = try Self.prepareVersion1(graph)

    #expect(plan.sourceSchemaVersion == BackupV1Contract.nativeTaskGraphSchemaVersion)
    #expect(plan.validation.taskIDs == [Self.taskID])
  }

  @Test("native graph v1 rejects vocabulary and budgets introduced after v1")
  func v2SemanticsArePinned() throws {
    var futureStatus = try Self.goldenNativeGraph()
    futureStatus.tasks[0].status = "future_status"
    #expect(
      throws: NativeTaskGraphValidationError.invalidValue(
        field: "task.status", reason: "task \(Self.taskID) uses future_status")
    ) {
      _ = try Self.prepareVersion1(futureStatus)
    }

    var futureRecurrence = try Self.goldenNativeGraph()
    futureRecurrence.tasks[0].recurrence =
      #"{"FREQ":"WEEKLY","INTERVAL":1,"NEW_RULE":true}"#
    #expect(
      throws: NativeTaskGraphValidationError.invalidValue(
        field: "task.recurrence",
        reason: "task \(Self.taskID) uses graph-v1-unknown key NEW_RULE")
    ) {
      _ = try Self.prepareVersion1(futureRecurrence)
    }

    var futureShadow = try Self.goldenNativeGraph()
    futureShadow.payloadShadows[0].payloadSchemaVersion = 102
    #expect(
      throws: NativeTaskGraphValidationError.invalidValue(
        field: "payloadShadow.payloadSchemaVersion",
        reason: "task:\(Self.taskID) is outside the accepted sync range")
    ) {
      _ = try Self.prepareVersion1(futureShadow)
    }
  }

  private static func goldenNativeGraph() throws -> NativeTaskGraphSnapshot {
    let payload = try LorvexDataImporter.decode(
      Data(BackupV1GoldenFixture.singleFileJSON.utf8))
    return try #require(payload.nativeTaskGraph)
  }

  private static func prepareVersion1(
    _ graph: NativeTaskGraphSnapshot
  ) throws -> NativeTaskGraphRestorePlan {
    try NativeTaskGraphRestoreAdapter.prepareVersion1(
      graph, knownListIDs: [listID], knownTagIDs: [tagID])
  }

  private static func makeFreshService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(
      store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private static let unknownMemberDocument = #"""
    {
      "formatVersion":"1",
      "manifest":{
        "formatVersion":"1","schemaVersion":"1",
        "source":{"platform":"apple"},"entityCounts":{"habits":1}
      },
      "habit":[]
    }
    """#

  private static let wrongCountDocument = #"""
    {
      "formatVersion":"1",
      "manifest":{
        "formatVersion":"1","schemaVersion":"1",
        "source":{"platform":"apple"},"entityCounts":{"habits":2}
      },
      "habits":[]
    }
    """#

  private static let missingCategoryDocument = #"""
    {
      "formatVersion":"1",
      "manifest":{
        "formatVersion":"1","schemaVersion":"1",
        "source":{"platform":"apple"},"entityCounts":{"habits":1}
      }
    }
    """#

  private static let nullCategoryDocument = #"""
    {
      "formatVersion":"1",
      "manifest":{
        "formatVersion":"1","schemaVersion":"1",
        "source":{"platform":"apple"},"entityCounts":{}
      },
      "tasks":null
    }
    """#

  private static let orphanedNativeGraphDocument = #"""
    {
      "formatVersion":"1",
      "manifest":{
        "formatVersion":"1","schemaVersion":"1",
        "source":{"platform":"apple"},"entityCounts":{}
      },
      "nativeTaskGraph":{
        "schemaVersion":"1","tasks":[],"recurrenceExceptions":[],
        "tagEdges":[],"dependencyEdges":[],"checklistItems":[],
        "reminders":[],"tombstones":[],"payloadShadows":[]
      }
    }
    """#
}
