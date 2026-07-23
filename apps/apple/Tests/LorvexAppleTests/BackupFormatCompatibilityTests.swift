import CryptoKit
import Foundation
import LorvexDomain
import Testing

@testable import LorvexCore

@Suite("Public backup format compatibility")
struct BackupFormatCompatibilityTests {
  @Test("v1 resource limits are portable across every Apple platform")
  func portableV1ResourceLimits() throws {
    #expect(BackupV1Contract.maxSourceBytes == 64 * 1024 * 1024)
    #expect(LorvexImportLimits.maxSourceBytes == BackupV1Contract.maxSourceBytes)
    #expect(LorvexZipArchive.maxArchiveBytes == BackupV1Contract.maxSourceBytes)
    #expect(
      LorvexZipArchive.maxEntryUncompressedBytes
        == BackupV1Contract.maxEntryUncompressedBytes)
    #expect(
      LorvexZipArchive.maxTotalUncompressedBytes
        == BackupV1Contract.maxTotalUncompressedBytes)

    try BackupV1Contract.assertPortableOutputSize(BackupV1Contract.maxSourceBytes)
    do {
      try BackupV1Contract.assertPortableOutputSize(BackupV1Contract.maxSourceBytes + 1)
      Issue.record("An oversized v1 JSON export was accepted")
    } catch let error as LorvexDataExportError {
      guard case .outputTooLarge(let size, let limit) = error else {
        Issue.record("Unexpected v1 export error: \(error)")
        return
      }
      #expect(size == BackupV1Contract.maxSourceBytes + 1)
      #expect(limit == BackupV1Contract.maxSourceBytes)
    }
  }

  @Test("bounded v1 categories fail instead of silently truncating")
  func boundedCategoryExportRejectsTruncation() throws {
    try SwiftLorvexCoreService.validateExportRowCount(
      category: "daily_reviews", count: 100_000, limit: 100_000)
    do {
      try SwiftLorvexCoreService.validateExportRowCount(
        category: "daily_reviews", count: 100_001, limit: 100_000)
      Issue.record("An export category above its in-memory limit was accepted")
    } catch let error as LorvexDataExportError {
      guard case .categoryRowLimitExceeded(let category, let count, let limit) = error else {
        Issue.record("Unexpected category export error: \(error)")
        return
      }
      #expect(category == "daily_reviews")
      #expect(count == 100_001)
      #expect(limit == 100_000)
    }
  }

  @Test("production-shaped v1 JSON remains byte-pinned and fully decodable")
  func decodesProductionShapedV1SingleFileFixture() throws {
    let data = Data(BackupV1GoldenFixture.singleFileJSON.utf8)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    #expect(digest == BackupV1GoldenFixture.expectedSHA256)

    let decoded = try LorvexDataImporter.decode(data)
    #expect(decoded.tasks?.count == 1)
    #expect(decoded.nativeTaskGraph?.schemaVersion == BackupV1Contract.nativeTaskGraphSchemaVersion)
    #expect(decoded.nativeTaskGraph?.payloadShadows.count == 1)
    #expect(decoded.lists?.count == 1)
    #expect(decoded.tags?.count == 1)
    #expect(decoded.habits?.first?.completions.count == 1)
    #expect(decoded.habits?.first?.reminderPolicies.count == 1)
    #expect(decoded.calendarSeriesCutovers?.count == 1)
    #expect(decoded.calendarEvents?.first?.attendees?.count == 1)
    #expect(decoded.dailyReviews?.count == 1)
    #expect(decoded.currentFocus?.count == 1)
    #expect(decoded.focusSchedules?.first?.blocks.count == 2)
    #expect(decoded.taskCalendarEventLinks?.count == 1)
    #expect(decoded.memory?.count == 1)
    #expect(decoded.preferences?.count == 1)
  }

  @Test("production-shaped v1 ZIP decodes every frozen member")
  func decodesProductionShapedV1ZipFixture() throws {
    let source = try #require(
      JSONSerialization.jsonObject(with: Data(BackupV1GoldenFixture.singleFileJSON.utf8))
        as? [String: Any])
    let members: [(key: String, path: String, count: Int)] = [
      ("tasks", "tasks.json", 1),
      ("nativeTaskGraph", "native_task_graph.json", 1),
      ("lists", "lists.json", 1),
      ("tags", "tags.json", 1),
      ("habits", "habits.json", 1),
      ("calendarSeriesCutovers", "calendar_series_cutovers.json", 1),
      ("calendarEvents", "calendar_events.json", 1),
      ("dailyReviews", "daily_reviews.json", 1),
      ("currentFocus", "current_focus.json", 1),
      ("focusSchedules", "focus_schedules.json", 1),
      ("taskCalendarEventLinks", "task_calendar_event_links.json", 1),
      ("memory", "memory.json", 1),
      ("preferences", "preferences.json", 1),
    ]
    var entries: [LorvexZipArchive.Entry] = []
    var counts: [String: Int] = [:]
    for member in members {
      let value = try #require(source[member.key])
      entries.append(
        .init(
          path: member.path,
          data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])))
      counts[String(member.path.dropLast(".json".count))] = member.count
    }
    let manifest: [String: Any] = [
      "schemaVersion": BackupV1Contract.zipSchemaVersion,
      "generatedAt": "2026-07-17T12:00:00.000Z",
      "appVersion": "1.0.0",
      "fileCounts": counts,
    ]
    entries.insert(
      .init(
        path: "manifest.json",
        data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])), at: 0)

    let decoded = try LorvexDataImporter.decode(LorvexZipArchive.archive(entries: entries))
    #expect(decoded.tasks?.count == 1)
    #expect(decoded.nativeTaskGraph?.tasks.count == 1)
    #expect(decoded.calendarSeriesCutovers?.count == 1)
    #expect(decoded.preferences?.first?.key == "working_hours")
  }

  @Test("production v1 JSON and ZIP encoders stay golden and share the closed registry")
  func productionEncodersStayGolden() throws {
    let sourceData = Data(BackupV1GoldenFixture.singleFileJSON.utf8)
    let sourceObject = try #require(
      JSONSerialization.jsonObject(with: sourceData) as? [String: Any])
    let payload = try LorvexDataImporter.decode(sourceData)

    let json = try LorvexDataExporter.render(payload: payload, format: .json)
    #expect(try canonicalJSON(Data(json.utf8)) == canonicalJSON(sourceData))
    let jsonDigest = sha256(Data(json.utf8))
    #expect(
      jsonDigest == BackupV1GoldenFixture.expectedProductionJSONSHA256,
      "production JSON SHA-256: \(jsonDigest)")
    let jsonRoundTrip = try LorvexDataImporter.decode(Data(json.utf8))
    #expect(jsonRoundTrip.nativeTaskGraph?.tasks.count == 1)
    #expect(jsonRoundTrip.memory?.first?.id == "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")

    let zip = try LorvexDataExporter.renderZip(
      payload: payload, generatedAt: "2026-07-17T12:00:00.000Z", appVersion: "1.0.0")
    let zipDigest = sha256(zip)
    #expect(
      zipDigest == BackupV1GoldenFixture.expectedProductionZipSHA256,
      "production ZIP SHA-256: \(zipDigest)")
    let entries = try LorvexZipArchive.read(zip)
    #expect(Set(entries.map(\.path)) == BackupV1ZipMember.allowedPaths)
    #expect(entries.map(\.path).first == BackupV1ZipMember.manifestPath)
    for entry in entries where entry.path != BackupV1ZipMember.manifestPath {
      let member = try #require(BackupV1ZipMember(path: entry.path))
      let expected = try #require(sourceObject[member.singleFileKey])
      let expectedData = try JSONSerialization.data(
        withJSONObject: expected, options: [.sortedKeys])
      #expect(try canonicalJSON(entry.data) == canonicalJSON(expectedData))
    }
    let zipRoundTrip = try LorvexDataImporter.decode(zip)
    #expect(zipRoundTrip.tasks?.first?.checklist?.first?.id != nil)
    #expect(zipRoundTrip.nativeTaskGraph?.payloadShadows.count == 1)
  }

  @Test("public v1 rejects missing or noncanonical synced child identities")
  func v1RejectsMalformedSyncedIdentities() throws {
    let malformedMembers = [
      ("memory", "memory", #"[{"key":"context","content":"x","updatedAt":"2026-07-17T12:00:00.000Z"}]"#),
      ("memory", "memory", #"[{"id":"NOT-A-UUID","key":"context","content":"x","updatedAt":"2026-07-17T12:00:00.000Z"}]"#),
      ("tasks", "tasks", #"[{"id":"33333333-3333-4333-8333-333333333333","title":"x","priority":"P2","status":"open","checklist":[{"text":"x","completed":false}]}]"#),
      ("tasks", "tasks", #"[{"id":"33333333-3333-4333-8333-333333333333","title":"x","priority":"P2","status":"open","checklist":[{"id":"NOT-A-UUID","text":"x","completed":false}]}]"#),
      ("tasks", "tasks", #"[{"id":"33333333-3333-4333-8333-333333333333","title":"x","priority":"P2","status":"open","reminders":[{"reminderAt":"2026-07-17T12:00:00.000Z"}]}]"#),
      ("tasks", "tasks", #"[{"id":"33333333-3333-4333-8333-333333333333","title":"x","priority":"P2","status":"open","reminders":[{"id":"NOT-A-UUID","reminderAt":"2026-07-17T12:00:00.000Z"}]}]"#),
    ]
    for (category, member, rows) in malformedMembers {
      let document = #"{"formatVersion":"1","manifest":{"formatVersion":"1","schemaVersion":"1","source":{"platform":"apple"},"entityCounts":{"\#(category)":1}},"\#(member)":\#(rows)}"#
      do {
        _ = try LorvexDataImporter.decode(Data(document.utf8))
        Issue.record("A malformed public-v1 synced identity was accepted")
      } catch let error as LorvexDataImporter.ImportError {
        guard case .malformedJSON = error else {
          Issue.record("Unexpected import error: \(error)")
          continue
        }
      }
    }

    let invalidExports = [
      LorvexDataExportPayload(
        memory: [
          ExportMemoryEntry(
            key: "context", content: "x", updatedAt: "2026-07-17T12:00:00.000Z")
        ]),
      LorvexDataExportPayload(
        tasks: [
          ExportTask(
            id: "33333333-3333-4333-8333-333333333333", title: "x",
            priority: "P2", status: "open", dueDate: nil, estimatedMinutes: nil,
            checklist: [ExportChecklistItem(text: "x", completed: false)])
        ]),
      LorvexDataExportPayload(
        tasks: [
          ExportTask(
            id: "33333333-3333-4333-8333-333333333333", title: "x",
            priority: "P2", status: "open", dueDate: nil, estimatedMinutes: nil,
            reminders: [
              ExportTaskReminder(
                id: "reminder-1", reminderAt: "2026-07-17T12:00:00.000Z")
            ])
        ]),
    ]
    for payload in invalidExports {
      do {
        _ = try LorvexDataExporter.render(payload: payload, format: .json)
        Issue.record("A public-v1 export minted or omitted a synced identity")
      } catch let error as BackupV1WireError {
        guard case .invalidIdentity = error else {
          Issue.record("Unexpected wire error: \(error)")
          continue
        }
      }
    }
  }

  @Test("the maximal v1 wire shape survives codec-only JSON and ZIP round trips")
  func maximalPayloadRoundTripsEveryOptionalField() throws {
    // Exercise every optional wire field through a semantically closed payload.
    // The production-shaped golden fixture remains the decode-plan-apply oracle.
    let payload = try Self.maximalPayload()

    let json = try LorvexDataExporter.render(payload: payload, format: .json)
    let decoded = try LorvexDataImporter.decode(Data(json.utf8))
    let reencoded = try LorvexDataExporter.render(payload: decoded, format: .json)
    #expect(json == reencoded)
    try Self.assertMaximalFieldsSurvived(decoded)

    // The payload-level manifest is a single-file concern; the ZIP carries its
    // own member manifest instead, so the ZIP leg compares against a
    // manifest-less rendering of the same maximal payload.
    var zipPayload = payload
    zipPayload.manifest = nil
    let zip = try LorvexDataExporter.renderZip(
      payload: zipPayload, generatedAt: "2026-07-17T12:00:00.000Z", appVersion: "1.0.0")
    let zipDecoded = try LorvexDataImporter.decode(zip)
    let zipReencoded = try LorvexDataExporter.render(payload: zipDecoded, format: .json)
    let zipExpected = try LorvexDataExporter.render(payload: zipPayload, format: .json)
    #expect(zipReencoded == zipExpected)
    try Self.assertMaximalFieldsSurvived(zipDecoded)
  }

  @Test("v1 remains the first supported single-file backup decoder")
  func decodesCommittedV1SingleFileFixture() throws {
    #expect(LorvexDataExportPayload.firstPublicFormatVersion == "1")
    #expect(LorvexDataExportPayload.supportedFormatVersions.first == "1")
    #expect(
      LorvexDataExportPayload.supportedFormatVersions.contains(
        LorvexDataExportPayload.currentFormatVersion))

    let decoded = try LorvexDataImporter.decode(fixtureData("v1-single-file.json"))
    #expect(decoded.formatVersion == "1")
    #expect(decoded.manifest?.formatVersion == "1")
    #expect(decoded.manifest?.schemaVersion == "1")
    #expect(decoded.lists?.first?.position == 7)
    #expect(decoded.tasks?.first?.title == "Decode the v1 backup")
    #expect(decoded.tasks?.first?.recurrence?.freq == "WEEKLY")
    #expect(decoded.tasks?.first?.checklist?.first?.completed == false)
    #expect(decoded.tasks?.first?.reminders?.first?.originalTz == "America/Los_Angeles")
  }

  @Test("v1 remains the first supported ZIP backup decoder")
  func decodesCommittedV1ZipFixtureMembers() throws {
    #expect(ExportManifest.firstPublicSchemaVersion == "1")
    #expect(ExportManifest.supportedSchemaVersions.first == "1")
    #expect(ExportManifest.supportedSchemaVersions.contains(ExportManifest.currentSchemaVersion))

    let archive = try LorvexZipArchive.archive(entries: [
      .init(path: "manifest.json", data: try fixtureData("v1-zip-manifest.json")),
      .init(path: "lists.json", data: try fixtureData("v1-zip-lists.json")),
      .init(path: "tasks.json", data: try fixtureData("v1-zip-tasks.json")),
    ])
    let decoded = try LorvexDataImporter.decode(archive)
    #expect(decoded.lists?.first?.name == "Public v1 fixture")
    #expect(decoded.tasks?.first?.title == "Decode the v1 ZIP backup")
  }

  // MARK: - Maximal payload (every category, every optional populated)

  private enum MaxID {
    static let task1 = "11111111-1111-4111-8111-111111111111"
    static let task2 = "e8d38432-2697-83a1-9101-0219573ff2fc"
    static let list1 = "33333333-3333-4333-8333-333333333333"
    static let tag1 = "44444444-4444-4444-8444-444444444444"
    static let habit1 = "55555555-5555-4555-8555-555555555555"
    static let policy1 = "66666666-6666-4666-8666-666666666666"
    static let checklist1 = "77777777-7777-4777-8777-777777777777"
    static let reminder1 = "88888888-8888-4888-8888-888888888888"
    static let event1 = "99999999-9999-4999-8999-999999999999"
    static let occurrence1 = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    static let cutover1 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let memory1 = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static let series1 = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    static let tombstoned1 = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    static let ts = "2026-07-17T12:00:00.000Z"
    static let hlc = "1800000000100_0001_00000000000000aa"
    static let hlc2 = "1800000000200_0002_00000000000000bb"
  }

  private static func maximalHlc(_ raw: String) throws -> Hlc {
    try Hlc.parseCanonical(raw)
  }

  private static func maximalPayload() throws -> LorvexDataExportPayload {
    let fullRecurrence = ExportRecurrenceRule(
      from: TaskRecurrenceRule(
        freq: .yearly, interval: 2, byDay: ["MO", "WE"], byMonth: [1, 6],
        byMonthDay: [1, 15], bySetPos: [1, -1], wkst: "MO",
        until: "2027-01-01", anchor: .schedule))
    let completionRecurrence = ExportRecurrenceRule(
      from: TaskRecurrenceRule(
        freq: .daily, interval: 3, count: 10, anchor: .completion))

    let task1 = ExportTask(
      id: MaxID.task1, title: "Maximal task", notes: "Body text",
      priority: "P1", status: "completed", dueDate: MaxID.ts, plannedDate: MaxID.ts,
      availableFrom: MaxID.ts, estimatedMinutes: 45, tags: ["Deep"],
      rawInput: "raw capture", dependsOn: [MaxID.task2], listID: MaxID.list1,
      aiNotes: "assistant scratch",
      checklist: [
        ExportChecklistItem(
          id: MaxID.checklist1, position: 0, text: "Step one", completed: true,
          completedAt: MaxID.ts, createdAt: MaxID.ts, updatedAt: MaxID.ts)
      ],
      reminders: [
        ExportTaskReminder(
          id: MaxID.reminder1, reminderAt: MaxID.ts, dismissedAt: MaxID.ts,
          cancelledAt: MaxID.ts, createdAt: MaxID.ts,
          originalLocalTime: "09:00", originalTz: "America/Los_Angeles")
      ],
      recurrence: fullRecurrence, recurrenceExceptions: ["2026-07-20"],
      deferCount: 3, lastDeferReason: "low_energy", lastDeferredAt: MaxID.ts,
      completedAt: MaxID.ts, createdAt: MaxID.ts, updatedAt: MaxID.ts,
      archivedAt: MaxID.ts)
    let task2 = ExportTask(
      id: MaxID.task2, title: "Completion-anchored successor", priority: "P3",
      status: "open", dueDate: "2026-07-20T00:00:00.000Z", estimatedMinutes: nil,
      listID: MaxID.list1, recurrence: completionRecurrence,
      createdAt: MaxID.ts, updatedAt: MaxID.ts)

    let nativeGraph = NativeTaskGraphSnapshot(
        tasks: [
          NativeTaskSnapshot(
            id: MaxID.task1, title: "Maximal task", body: "Body text",
            rawInput: "raw capture", aiNotes: "assistant scratch", status: "completed",
            listID: MaxID.list1, priority: 1, dueDate: "2026-07-17",
            estimatedMinutes: 45,
            recurrence: #"{"BYDAY":["MO","WE"],"BYMONTH":[1,6],"BYMONTHDAY":[1,15],"BYSETPOS":[-1,1],"FREQ":"YEARLY","INTERVAL":2,"UNTIL":"2027-01-01","WKST":"MO"}"#,
            spawnedFrom: nil,
            spawnedFromVersion: nil,
            recurrenceGroupID: MaxID.series1,
            recurrenceInstanceKey: "\(MaxID.series1):2026-07-17",
            canonicalOccurrenceDate: "2026-07-17",
            contentVersion: try maximalHlc(MaxID.hlc),
            scheduleVersion: try maximalHlc(MaxID.hlc),
            lifecycleVersion: try maximalHlc(MaxID.hlc),
            archiveVersion: try maximalHlc(MaxID.hlc),
            recurrenceRolloverState: "authorized",
            recurrenceSuccessorID: MaxID.task2,
            version: try maximalHlc(MaxID.hlc2), createdAt: MaxID.ts,
            updatedAt: MaxID.ts, completedAt: MaxID.ts, lastDeferredAt: MaxID.ts,
            lastDeferReason: "low_energy", plannedDate: "2026-07-17",
            availableFrom: "2026-07-17", deferCount: 3, archivedAt: MaxID.ts),
          NativeTaskSnapshot(
            id: MaxID.task2, title: "Completion-anchored successor", body: nil,
            rawInput: nil, aiNotes: nil, status: "open", listID: MaxID.list1,
            priority: 3, dueDate: "2026-07-20", estimatedMinutes: nil,
            recurrence: #"{"ANCHOR":"completion","COUNT":10,"FREQ":"DAILY","INTERVAL":3}"#,
            spawnedFrom: MaxID.task1, spawnedFromVersion: try maximalHlc(MaxID.hlc),
            recurrenceGroupID: MaxID.series1,
            recurrenceInstanceKey: "\(MaxID.series1):2026-07-20",
            canonicalOccurrenceDate: "2026-07-20",
            contentVersion: try maximalHlc(MaxID.hlc),
            scheduleVersion: try maximalHlc(MaxID.hlc),
            lifecycleVersion: try maximalHlc(MaxID.hlc),
            archiveVersion: try maximalHlc(MaxID.hlc),
            recurrenceRolloverState: "none", recurrenceSuccessorID: nil,
            version: try maximalHlc(MaxID.hlc2), createdAt: MaxID.ts,
            updatedAt: MaxID.ts, completedAt: nil, lastDeferredAt: nil,
            lastDeferReason: nil, plannedDate: nil, availableFrom: nil,
            deferCount: 0, archivedAt: nil)
        ],
        recurrenceExceptions: [
          NativeTaskRecurrenceExceptionSnapshot(
            taskID: MaxID.task1, exceptionDate: "2026-07-20")
        ],
        tagEdges: [
          NativeTaskTagEdgeSnapshot(
            taskID: MaxID.task1, tagID: MaxID.tag1,
            version: try maximalHlc(MaxID.hlc), createdAt: MaxID.ts)
        ],
        dependencyEdges: [
          NativeTaskDependencyEdgeSnapshot(
            taskID: MaxID.task1, dependsOnTaskID: MaxID.task2,
            version: try maximalHlc(MaxID.hlc), createdAt: MaxID.ts)
        ],
        checklistItems: [
          NativeTaskChecklistItemSnapshot(
            id: MaxID.checklist1, taskID: MaxID.task1, position: 0,
            text: "Step one", completedAt: MaxID.ts,
            version: try maximalHlc(MaxID.hlc), createdAt: MaxID.ts,
            updatedAt: MaxID.ts)
        ],
        reminders: [
          NativeTaskReminderSnapshot(
            id: MaxID.reminder1, taskID: MaxID.task1, reminderAt: MaxID.ts,
            dismissedAt: MaxID.ts, cancelledAt: MaxID.ts,
            version: try maximalHlc(MaxID.hlc), createdAt: MaxID.ts,
            originalLocalTime: "09:00", originalTimeZone: "America/Los_Angeles")
        ],
        tombstones: [
          NativeTaskTombstoneSnapshot(
            entityType: .task, entityID: MaxID.tombstoned1,
            version: try maximalHlc(MaxID.hlc), deletedAt: MaxID.ts)
        ],
        payloadShadows: [
          NativeTaskPayloadShadowSnapshot(
            entityType: .task, entityID: MaxID.task1,
            baseVersion: try maximalHlc(MaxID.hlc2), payloadSchemaVersion: 3,
            rawPayloadJSON: #"{"future_field":true}"#,
            sourceDeviceID: "0000000000000000", updatedAt: MaxID.ts)
        ])

    return LorvexDataExportPayload(
      manifest: ExportPayloadManifest(
        formatVersion: "1", schemaVersion: "1", generatedAt: MaxID.ts,
        source: ExportSource(
          platform: "apple", appVersion: "1.2.3", deviceID: "device-fixture"),
        entityCounts: [
          "tasks": 2, "lists": 1, "tags": 1, "habits": 1,
          "calendar_events": 3, "daily_reviews": 1, "current_focus": 1,
          "focus_schedules": 1, "task_calendar_event_links": 1,
          "memory": 1, "preferences": 1,
        ]),
      tasks: [task1, task2],
      nativeTaskGraph: nativeGraph,
      lists: [
        ExportList(
          id: MaxID.list1, name: "Deep work", description: "Focused efforts",
          color: "#FF8800", icon: "tray.full", aiNotes: "list scope notes",
          archivedAt: MaxID.ts, position: 7)
      ],
      tags: [
        ExportTag(
          id: MaxID.tag1, displayName: "Deep", color: "#00FF88",
          createdAt: MaxID.ts, updatedAt: MaxID.ts)
      ],
      habits: [
        ExportHabit(
          id: MaxID.habit1, name: "Stretch", cue: "After coffee",
          icon: "figure.walk", color: "#8800FF", frequencyType: "weekly",
          weekdays: [0, 2], perPeriodTarget: 3, dayOfMonth: 15, targetCount: 2,
          milestoneTarget: 100, archived: true, position: 4,
          completions: [
            ExportHabitCompletion(
              completedDate: "2026-07-16", value: 2, note: "Felt great",
              createdAt: MaxID.ts, updatedAt: MaxID.ts)
          ],
          reminderPolicies: [
            ExportHabitReminderPolicy(
              id: MaxID.policy1, reminderTime: "08:30", enabled: true,
              createdAt: MaxID.ts, updatedAt: MaxID.ts)
          ])
      ],
      calendarSeriesCutovers: [
        ExportCalendarSeriesCutover(
          id: MaxID.cutover1, lineageRootId: MaxID.event1,
          cutoverDate: "2026-07-01", state: "active")
      ],
      calendarEvents: [
        ExportCalendarEvent(
          id: MaxID.event1, title: "Design review", startDate: "2026-07-17",
          startTime: "10:00", endDate: "2026-07-17", endTime: "11:00",
          allDay: false, location: "Room 4", notes: "Bring mockups",
          url: "https://lorvex.app/meet", color: "#123456",
          eventType: "meeting", personName: "Alex",
          attendees: [
            CalendarEventAttendee(
              email: "alex@example.com", name: "Alex", status: "accepted")
          ],
          timezone: "America/Los_Angeles",
          recurrence: ExportCalendarRecurrenceRule(
            freq: "WEEKLY", interval: 1, byDay: ["FR"], byMonth: [7],
            byMonthDay: [17], bySetPos: [2], wkst: "MO",
            until: "20271231T000000Z", count: 20),
          recurrenceGeneration: MaxID.hlc),
        ExportCalendarEvent(
          id: MaxID.occurrence1, title: "Replacement", startDate: "2026-07-24",
          startTime: "10:30", endDate: "2026-07-24", endTime: "11:30",
          allDay: false, seriesId: MaxID.event1,
          recurrenceInstanceDate: "2026-07-24", occurrenceState: "replacement",
          recurrenceGeneration: MaxID.hlc),
        ExportCalendarEvent(
          id: MaxID.cutover1, title: "Tail segment", startDate: "2026-07-01",
          startTime: "10:00", endDate: "2026-07-01", endTime: "11:00",
          allDay: false,
          recurrence: ExportCalendarRecurrenceRule(freq: "WEEKLY", byDay: ["FR"]),
          recurrenceGeneration: MaxID.hlc, seriesCutoverId: MaxID.cutover1),
      ],
      dailyReviews: [
        ExportDailyReview(
          date: "2026-07-16", summary: "Solid day", mood: 4, energyLevel: 3,
          wins: "Shipped", blockers: "None", learnings: "Ship earlier",
          timezone: "America/Los_Angeles", updatedAt: MaxID.ts,
          linkedTaskIDs: [MaxID.task1], linkedListIDs: [MaxID.list1])
      ],
      currentFocus: [
        ExportCurrentFocus(
          date: "2026-07-17", briefing: "One thing", timezone: "UTC",
          taskIDs: [MaxID.task2], createdAt: MaxID.ts, updatedAt: MaxID.ts)
      ],
      focusSchedules: [
        ExportFocusSchedule(
          date: "2026-07-17", rationale: "Deep-work morning", timezone: "UTC",
          blocks: [
            ExportFocusScheduleBlock(
              position: 0, blockType: "task", startMinutes: 540,
              endMinutes: 600, taskID: MaxID.task2,
              title: "Completion-anchored successor"),
            ExportFocusScheduleBlock(
              position: 1, blockType: "event", startMinutes: 600,
              endMinutes: 660, calendarEventID: MaxID.event1, eventSource: .canonical,
              title: "Design review"),
          ],
          createdAt: MaxID.ts, updatedAt: MaxID.ts)
      ],
      taskCalendarEventLinks: [
        ExportTaskCalendarEventLink(
          taskID: MaxID.task1, calendarEventID: MaxID.event1,
          createdAt: MaxID.ts, updatedAt: MaxID.ts)
      ],
      memory: [
        ExportMemoryEntry(
          id: MaxID.memory1, key: "context", content: "Working style",
          updatedAt: MaxID.ts)
      ],
      preferences: [
        ExportPreference(
          key: "working_hours", value: #"{"end":"17:00","start":"09:00"}"#)
      ])
  }

  private static func assertMaximalFieldsSurvived(_ decoded: LorvexDataExportPayload) throws {
    #expect(decoded.formatVersion == "1")

    let task = try #require(decoded.tasks?.first)
    #expect(task.notes == "Body text")
    #expect(task.dueDate == MaxID.ts)
    #expect(task.plannedDate == MaxID.ts)
    #expect(task.availableFrom == MaxID.ts)
    #expect(task.estimatedMinutes == 45)
    #expect(task.tags == ["Deep"])
    #expect(task.rawInput == "raw capture")
    #expect(task.dependsOn == [MaxID.task2])
    #expect(task.listID == MaxID.list1)
    #expect(task.aiNotes == "assistant scratch")
    #expect(task.recurrenceExceptions == ["2026-07-20"])
    #expect(task.deferCount == 3)
    #expect(task.lastDeferReason == "low_energy")
    #expect(task.lastDeferredAt == MaxID.ts)
    #expect(task.completedAt == MaxID.ts)
    #expect(task.createdAt == MaxID.ts)
    #expect(task.updatedAt == MaxID.ts)
    #expect(task.archivedAt == MaxID.ts)

    let checklist = try #require(task.checklist?.first)
    #expect(checklist.id == MaxID.checklist1)
    #expect(checklist.position == 0)
    #expect(checklist.completed)
    #expect(checklist.completedAt == MaxID.ts)
    #expect(checklist.createdAt == MaxID.ts)
    #expect(checklist.updatedAt == MaxID.ts)

    let reminder = try #require(task.reminders?.first)
    #expect(reminder.id == MaxID.reminder1)
    #expect(reminder.dismissedAt == MaxID.ts)
    #expect(reminder.cancelledAt == MaxID.ts)
    #expect(reminder.createdAt == MaxID.ts)
    #expect(reminder.originalLocalTime == "09:00")
    #expect(reminder.originalTz == "America/Los_Angeles")

    let rule = try #require(task.recurrence)
    #expect(rule.freq == "YEARLY")
    #expect(rule.interval == 2)
    #expect(rule.byDay == ["MO", "WE"])
    #expect(rule.byMonth == [1, 6])
    #expect(rule.byMonthDay == [1, 15])
    #expect(rule.bySetPos == [1, -1])
    #expect(rule.wkst == "MO")
    #expect(rule.until == "2027-01-01")
    #expect(rule.count == nil)
    #expect(rule.anchor == nil)
    #expect(decoded.tasks?.dropFirst().first?.recurrence?.anchor == "completion")

    let native = try #require(decoded.nativeTaskGraph)
    let nativeTask = try #require(native.tasks.first)
    #expect(nativeTask.body == "Body text")
    #expect(nativeTask.rawInput == "raw capture")
    #expect(nativeTask.aiNotes == "assistant scratch")
    #expect(nativeTask.priority == 1)
    #expect(nativeTask.dueDate == "2026-07-17")
    #expect(nativeTask.estimatedMinutes == 45)
    #expect(nativeTask.recurrence?.contains(#""FREQ":"YEARLY""#) == true)
    #expect(nativeTask.spawnedFrom == nil)
    #expect(nativeTask.spawnedFromVersion == nil)
    #expect(nativeTask.recurrenceGroupID == MaxID.series1)
    #expect(nativeTask.recurrenceInstanceKey == "\(MaxID.series1):2026-07-17")
    #expect(nativeTask.canonicalOccurrenceDate == "2026-07-17")
    #expect(nativeTask.recurrenceSuccessorID == MaxID.task2)
    #expect(nativeTask.completedAt == MaxID.ts)
    #expect(nativeTask.lastDeferredAt == MaxID.ts)
    #expect(nativeTask.lastDeferReason == "low_energy")
    #expect(nativeTask.plannedDate == "2026-07-17")
    #expect(nativeTask.availableFrom == "2026-07-17")
    #expect(nativeTask.archivedAt == MaxID.ts)
    #expect(native.recurrenceExceptions.first?.exceptionDate == "2026-07-20")
    #expect(native.tagEdges.first?.tagID == MaxID.tag1)
    #expect(native.dependencyEdges.first?.dependsOnTaskID == MaxID.task2)
    #expect(native.checklistItems.first?.completedAt == MaxID.ts)
    let nativeReminder = try #require(native.reminders.first)
    #expect(nativeReminder.dismissedAt == MaxID.ts)
    #expect(nativeReminder.cancelledAt == MaxID.ts)
    #expect(nativeReminder.originalLocalTime == "09:00")
    #expect(nativeReminder.originalTimeZone == "America/Los_Angeles")
    #expect(native.tombstones.first?.entityID == MaxID.tombstoned1)
    let shadow = try #require(native.payloadShadows.first)
    #expect(shadow.baseVersion.description == MaxID.hlc2)
    #expect(shadow.payloadSchemaVersion == 3)
    #expect(shadow.rawPayloadJSON == #"{"future_field":true}"#)
    #expect(shadow.sourceDeviceID == "0000000000000000")

    let list = try #require(decoded.lists?.first)
    #expect(list.description == "Focused efforts")
    #expect(list.color == "#FF8800")
    #expect(list.icon == "tray.full")
    #expect(list.aiNotes == "list scope notes")
    #expect(list.archivedAt == MaxID.ts)
    #expect(list.position == 7)

    let tag = try #require(decoded.tags?.first)
    #expect(tag.color == "#00FF88")
    #expect(tag.createdAt == MaxID.ts)
    #expect(tag.updatedAt == MaxID.ts)

    let habit = try #require(decoded.habits?.first)
    #expect(habit.icon == "figure.walk")
    #expect(habit.color == "#8800FF")
    #expect(habit.weekdays == [0, 2])
    #expect(habit.perPeriodTarget == 3)
    #expect(habit.dayOfMonth == 15)
    #expect(habit.milestoneTarget == 100)
    #expect(habit.archived)
    #expect(habit.position == 4)
    #expect(habit.completions.first?.note == "Felt great")
    #expect(habit.reminderPolicies.first?.id == MaxID.policy1)

    let cutover = try #require(decoded.calendarSeriesCutovers?.first)
    #expect(cutover.lineageRootId == MaxID.event1)
    #expect(cutover.state == "active")

    let event = try #require(decoded.calendarEvents?.first)
    #expect(event.location == "Room 4")
    #expect(event.notes == "Bring mockups")
    #expect(event.url == "https://lorvex.app/meet")
    #expect(event.color == "#123456")
    #expect(event.personName == "Alex")
    #expect(event.timezone == "America/Los_Angeles")
    #expect(event.recurrenceGeneration == MaxID.hlc)
    let attendee = try #require(event.attendees?.first)
    #expect(attendee.email == "alex@example.com")
    #expect(attendee.name == "Alex")
    #expect(attendee.status == "accepted")
    let eventRule = try #require(event.recurrence)
    #expect(eventRule.interval == 1)
    #expect(eventRule.byDay == ["FR"])
    #expect(eventRule.byMonth == [7])
    #expect(eventRule.byMonthDay == [17])
    #expect(eventRule.bySetPos == [2])
    #expect(eventRule.wkst == "MO")
    #expect(eventRule.until == "20271231T000000Z")
    #expect(eventRule.count == 20)

    let occurrence = try #require(
      decoded.calendarEvents?.first(where: { $0.id == MaxID.occurrence1 }))
    #expect(occurrence.seriesId == MaxID.event1)
    #expect(occurrence.recurrenceInstanceDate == "2026-07-24")
    #expect(occurrence.occurrenceState == "replacement")
    #expect(occurrence.recurrenceGeneration == MaxID.hlc)

    let segment = try #require(
      decoded.calendarEvents?.first(where: { $0.id == MaxID.cutover1 }))
    #expect(segment.seriesCutoverId == MaxID.cutover1)

    let review = try #require(decoded.dailyReviews?.first)
    #expect(review.mood == 4)
    #expect(review.energyLevel == 3)
    #expect(review.timezone == "America/Los_Angeles")
    #expect(review.updatedAt == MaxID.ts)
    #expect(review.linkedTaskIDs == [MaxID.task1])
    #expect(review.linkedListIDs == [MaxID.list1])

    let focus = try #require(decoded.currentFocus?.first)
    #expect(focus.briefing == "One thing")
    #expect(focus.timezone == "UTC")
    #expect(focus.taskIDs == [MaxID.task2])
    #expect(focus.createdAt == MaxID.ts)
    #expect(focus.updatedAt == MaxID.ts)

    let schedule = try #require(decoded.focusSchedules?.first)
    #expect(schedule.rationale == "Deep-work morning")
    #expect(schedule.timezone == "UTC")
    #expect(schedule.createdAt == MaxID.ts)
    #expect(schedule.updatedAt == MaxID.ts)
    let taskBlock = try #require(schedule.blocks.first)
    #expect(taskBlock.taskID == MaxID.task2)
    #expect(taskBlock.title == "Completion-anchored successor")
    let eventBlock = try #require(schedule.blocks.dropFirst().first)
    #expect(eventBlock.calendarEventID == MaxID.event1)
    #expect(eventBlock.eventSource == .canonical)

    let link = try #require(decoded.taskCalendarEventLinks?.first)
    #expect(link.createdAt == MaxID.ts)
    #expect(link.updatedAt == MaxID.ts)

    #expect(decoded.memory?.first?.id == MaxID.memory1)
    #expect(
      decoded.preferences?.first?.value == #"{"end":"17:00","start":"09:00"}"#)
  }

  private func fixtureData(_ name: String) throws -> Data {
    let appleRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try Data(
      contentsOf:
        appleRoot
        .appendingPathComponent("Tests/Fixtures/BackupFormat", isDirectory: true)
        .appendingPathComponent(name, isDirectory: false))
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func canonicalJSON(_ data: Data) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys])
  }
}
