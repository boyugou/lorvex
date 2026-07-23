import XCTest

@testable import LorvexDomain

final class NamingTests: XCTestCase {
  // MARK: - Collection invariants

  func testAllEntityTypesHasCorrectCount() {
    XCTAssertEqual(EntityName.allEntityTypes.count, 16)
  }

  func testAllEdgeTypesHasCorrectCount() {
    XCTAssertEqual(EdgeName.allEdgeTypes.count, 4)
  }

  func testAllSyncableTypesIsSupersetOfEntitiesAndEdges() {
    for entity in EntityName.allEntityTypes {
      XCTAssertTrue(
        EntityKind.allSyncableTypes.contains(entity),
        "allSyncableTypes missing entity: \(entity)")
    }
    for edge in EdgeName.allEdgeTypes {
      XCTAssertTrue(
        EntityKind.allSyncableTypes.contains(edge),
        "allSyncableTypes missing edge: \(edge)")
    }
    XCTAssertEqual(
      EntityKind.allSyncableTypes.count,
      EntityName.allEntityTypes.count + EdgeName.allEdgeTypes.count,
      "allSyncableTypes should contain exactly allEntityTypes + allEdgeTypes")
  }

  func testAllSyncableTypesHasNoDuplicates() {
    var seen = Set<String>()
    for entry in EntityKind.allSyncableTypes {
      XCTAssertTrue(seen.insert(entry).inserted, "Duplicate in allSyncableTypes: \(entry)")
    }
  }

  func testTopologicalOrderContainsAllEntitiesAndEdges() {
    for entity in EntityName.allEntityTypes {
      if entity == EntityName.aiChangelog { continue }
      XCTAssertTrue(
        EntityKind.topologicalEntityOrder.contains(entity),
        "Missing entity in topological order: \(entity)")
    }
    for edge in EdgeName.allEdgeTypes {
      XCTAssertTrue(
        EntityKind.topologicalEntityOrder.contains(edge),
        "Missing edge in topological order: \(edge)")
    }
  }

  func testTopologicalOrderHasNoDuplicates() {
    var seen = Set<String>()
    for entry in EntityKind.topologicalEntityOrder {
      XCTAssertTrue(seen.insert(entry).inserted, "Duplicate in topological order: \(entry)")
    }
  }

  func testListBeforeTaskInTopologicalOrder() {
    let listPos = EntityKind.topologicalEntityOrder.firstIndex(of: EntityName.list)
    let taskPos = EntityKind.topologicalEntityOrder.firstIndex(of: EntityName.task)
    XCTAssertNotNil(listPos)
    XCTAssertNotNil(taskPos)
    XCTAssertLessThan(listPos!, taskPos!, "list must appear before task in topological order")
  }

  func testEdgesAfterAllAggregateRoots() {
    let firstEdgePos = EntityKind.topologicalEntityOrder.firstIndex(of: EdgeName.taskTag)
    let lastRootPos = EntityKind.topologicalEntityOrder.firstIndex(of: EntityName.focusSchedule)
    XCTAssertNotNil(firstEdgePos)
    XCTAssertNotNil(lastRootPos)
    XCTAssertLessThan(
      lastRootPos!, firstEdgePos!, "edges must appear after all aggregate roots")
  }

  // MARK: - CalendarAiAccessMode

  func testCalendarAccessModeParseStrictRoundtrip() {
    for v in [CalendarAiAccessMode.off, .busyOnly, .fullDetails] {
      let s = v.asString
      let parsed = CalendarAiAccessMode.parseStrict(s)
      XCTAssertEqual(parsed, v, "roundtrip failed for \(s)")
    }
  }

  func testCalendarAccessModeParseStrictRejectsUnknown() {
    XCTAssertNil(CalendarAiAccessMode.parseStrict("unknown"))
    XCTAssertNil(CalendarAiAccessMode.parseStrict(""))
  }

  func testCalendarAccessModeIncludesProvider() {
    XCTAssertFalse(CalendarAiAccessMode.off.includesProvider)
    XCTAssertTrue(CalendarAiAccessMode.busyOnly.includesProvider)
    XCTAssertTrue(CalendarAiAccessMode.fullDetails.includesProvider)
  }

  func testCalendarAccessModeIncludesDetails() {
    XCTAssertFalse(CalendarAiAccessMode.off.includesDetails)
    XCTAssertFalse(CalendarAiAccessMode.busyOnly.includesDetails)
    XCTAssertTrue(CalendarAiAccessMode.fullDetails.includesDetails)
  }

  func testCalendarAccessModeDefaultIsBusyOnly() {
    XCTAssertEqual(CalendarAiAccessMode.defaultMode, .busyOnly)
  }

  func testCalendarAccessModeDetailRankOrders() {
    XCTAssertEqual(CalendarAiAccessMode.off.detailRank, 0)
    XCTAssertEqual(CalendarAiAccessMode.busyOnly.detailRank, 1)
    XCTAssertEqual(CalendarAiAccessMode.fullDetails.detailRank, 2)
  }

  func testCalendarAccessModeReducesDetailIdentifiesDowngrades() {
    // Detail-reducing downgrades: any move to a strictly lower rank.
    XCTAssertTrue(CalendarAiAccessMode.fullDetails.reducesDetail(to: .busyOnly))
    XCTAssertTrue(CalendarAiAccessMode.fullDetails.reducesDetail(to: .off))
    XCTAssertTrue(CalendarAiAccessMode.busyOnly.reducesDetail(to: .off))
    // Upgrades and no-ops are not downgrades.
    XCTAssertFalse(CalendarAiAccessMode.busyOnly.reducesDetail(to: .fullDetails))
    XCTAssertFalse(CalendarAiAccessMode.off.reducesDetail(to: .busyOnly))
    XCTAssertFalse(CalendarAiAccessMode.fullDetails.reducesDetail(to: .fullDetails))
  }

  func testCalendarAccessModeAsStrValues() {
    XCTAssertEqual(CalendarAiAccessMode.off.asString, "off")
    XCTAssertEqual(CalendarAiAccessMode.busyOnly.asString, "busy_only")
    XCTAssertEqual(CalendarAiAccessMode.fullDetails.asString, "full_details")
  }

  func testCalendarAccessModeSerdeRoundtrip() throws {
    let mode = CalendarAiAccessMode.busyOnly
    let data = try JSONEncoder().encode(mode)
    let decoded = try JSONDecoder().decode(CalendarAiAccessMode.self, from: data)
    XCTAssertEqual(decoded, mode)
  }

  // MARK: - EntityKind

  func testEntityKindRoundTripsEverySyncableString() {
    for raw in EntityKind.allSyncableTypes {
      switch EntityKind.tryParse(raw) {
      case .success(let kind):
        XCTAssertEqual(kind.asString, raw, "EntityKind.asString must match input")
        XCTAssertTrue(kind.isSyncableKind, "\(raw) should be syncable")
      case .failure(let err):
        XCTFail("missing EntityKind for \(raw): \(err)")
      }
    }
  }

  func testEntityKindTryParseRoundTripsEveryKnownEntityString() {
    for raw in EntityName.allEntityTypes + EdgeName.allEdgeTypes {
      switch EntityKind.tryParse(raw) {
      case .success(let kind):
        XCTAssertEqual(kind.asString, raw)
      case .failure(let err):
        XCTFail("missing EntityKind for \(raw): \(err)")
      }
    }
  }

  func testEntityKindRoundTripsLocalOnlyStrings() {
    for raw in [EntityName.deviceState, EntityName.importSession] {
      let kind = EntityKind.parse(raw)
      XCTAssertNotNil(kind)
      XCTAssertEqual(kind?.asString, raw)
      XCTAssertEqual(kind?.isSyncableKind, false, "\(raw) must not be marked syncable")
    }
  }

  func testEntityKindParseRejectsUnknown() {
    XCTAssertNil(EntityKind.parse("definitely-not-an-entity"))
    XCTAssertNil(EntityKind.parse(""))
  }

  func testEntityKindIsEdgeMatchesEdgeSet() {
    for raw in EdgeName.allEdgeTypes {
      let kind = EntityKind.parse(raw)
      XCTAssertEqual(kind?.isEdge, true, "\(raw) should be classified as edge")
    }
    for raw in EntityName.allEntityTypes {
      let kind = EntityKind.parse(raw)
      XCTAssertEqual(kind?.isEdge, false, "\(raw) must not be classified as edge")
    }
  }

  func testEntityKindTablePkCoversSimplePkSyncableTypes() {
    let simplePk: [EntityKind] = [
      .task, .list, .habit, .tag, .calendarEvent, .preference, .memory,
      .dailyReview, .currentFocus, .focusSchedule,
      .taskReminder, .taskChecklistItem, .habitReminderPolicy,
    ]
    for kind in simplePk {
      XCTAssertNotNil(kind.tablePk, "\(kind) should have a simple-PK table mapping")
    }
    let noSimplePk: [EntityKind] = [
      .aiChangelog, .entityRedirect, .taskTag, .taskDependency, .taskCalendarEventLink,
      .habitCompletion,
      .deviceState, .importSession,
    ]
    for kind in noSimplePk {
      XCTAssertNil(kind.tablePk, "\(kind) must not resolve to a simple-PK table")
    }
  }

  func testEntityKindTableNameCoversEveryPersistentKind() {
    let cases: [(EntityKind, String)] = [
      (.task, "tasks"), (.list, "lists"), (.habit, "habits"), (.tag, "tags"),
      (.calendarEvent, "calendar_events"),
      (.preference, "preferences"), (.memory, "memories"),
      (.dailyReview, "daily_reviews"), (.currentFocus, "current_focus"),
      (.focusSchedule, "focus_schedule"),
      (.taskReminder, "task_reminders"), (.taskChecklistItem, "task_checklist_items"),
      (.habitReminderPolicy, "habit_reminder_policies"),
      (.taskTag, "task_tags"), (.taskDependency, "task_dependencies"),
      (.taskCalendarEventLink, "task_calendar_event_links"),
      (.habitCompletion, "habit_completions"),
      (.aiChangelog, "ai_changelog"),
      (.entityRedirect, "sync_entity_redirects"),
      (.deviceState, "device_state"),
    ]
    for (kind, expected) in cases {
      XCTAssertEqual(kind.tableName, expected, "EntityKind.tableName mismatch for \(kind)")
    }
    XCTAssertNil(EntityKind.importSession.tableName)
  }

  func testEntityKindSerdeUsesCanonicalString() throws {
    let json = try JSONEncoder().encode(EntityKind.calendarEvent)
    XCTAssertEqual(String(data: json, encoding: .utf8), "\"calendar_event\"")
    let parsed = try JSONDecoder().decode(
      EntityKind.self, from: Data("\"task_checklist_item\"".utf8))
    XCTAssertEqual(parsed, .taskChecklistItem)
  }

  func testEntityKindFromStrSurfacesUnknownError() {
    XCTAssertThrowsError(try EntityKind(parsing: "bogus")) { error in
      guard let err = error as? UnknownEntityKind else {
        return XCTFail("expected UnknownEntityKind, got \(error)")
      }
      XCTAssertEqual(err.value, "bogus")
      XCTAssertTrue(err.description.contains("unknown entity kind"))
    }
  }
}
