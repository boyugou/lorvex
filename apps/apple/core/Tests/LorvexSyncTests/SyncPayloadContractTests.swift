import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Shared decoder and operation-specific matcher for the current payload
/// contract. Tests feed it final ``SyncEnvelope`` payloads after the production
/// builder/loader and outbox transform have both run.
enum SyncPayloadContractFixture {
  typealias Field = SyncPayloadFieldContract
  typealias FieldEvolution = SyncPayloadFieldEvolution
  typealias Contract = SyncPayloadContractManifest

  static func contractURL(version: UInt32) throws -> URL {
    let fileManager = FileManager.default
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let fileName = String(format: "%03u.json", version)
    while directory.path != "/" {
      let candidate =
        directory
        .appendingPathComponent("schema", isDirectory: true)
        .appendingPathComponent("sync_payload", isDirectory: true)
        .appendingPathComponent(fileName)
      if fileManager.isReadableFile(atPath: candidate.path) { return candidate }
      directory.deleteLastPathComponent()
    }
    throw NSError(
      domain: "SyncPayloadContractTests", code: 1,
      userInfo: [
        NSLocalizedDescriptionKey:
          "missing schema/sync_payload/\(fileName) for payloadSchemaVersion "
          + "\(version)"
      ])
  }

  static func currentContractURL() throws -> URL {
    try contractURL(version: LorvexVersion.payloadSchemaVersion)
  }

  static func load(version: UInt32) throws -> Contract {
    try JSONDecoder().decode(
      Contract.self, from: Data(contentsOf: try contractURL(version: version)))
  }

  static func load() throws -> Contract {
    try load(version: LorvexVersion.payloadSchemaVersion)
  }

  static func goldenFixtureURL(contract: Contract? = nil) throws -> URL {
    let contract = try contract ?? load()
    return try contractURL(version: contract.payloadSchemaVersion).deletingLastPathComponent()
      .appendingPathComponent(contract.goldenFixture)
  }

  static func goldenEnvelopes(contract: Contract? = nil) throws -> [SyncEnvelope] {
    let contract = try contract ?? load()
    let data = try Data(contentsOf: goldenFixtureURL(contract: contract))
    guard Sha256Checksum.hexDigest(data) == contract.goldenFixtureSHA256 else {
      throw NSError(
        domain: "SyncPayloadContractTests", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "golden fixture SHA does not match manifest"])
    }
    guard let raw = String(data: data, encoding: .utf8),
      case .object(let root)? = JSONValue.parse(raw),
      root["payload_schema_version"] == .int(Int64(contract.payloadSchemaVersion)),
      case .array(let entries)? = root["envelopes"]
    else {
      throw NSError(
        domain: "SyncPayloadContractTests", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "malformed golden payload fixture"])
    }
    return try entries.map { entry in
      guard case .object(let envelope) = entry,
        case .string(let entityTypeRaw)? = envelope["entity_type"],
        let entityType = EntityKind.parse(entityTypeRaw),
        case .string(let entityID)? = envelope["entity_id"],
        case .string(let operationRaw)? = envelope["operation"],
        let operation = SyncOperation(rawValue: operationRaw),
        case .string(let versionRaw)? = envelope["version"],
        case .object(let payload)? = envelope["payload"],
        case .string(let deviceID)? = envelope["device_id"]
      else {
        throw NSError(
          domain: "SyncPayloadContractTests", code: 4,
          userInfo: [NSLocalizedDescriptionKey: "malformed golden envelope"])
      }
      return SyncEnvelope(
        entityType: entityType, entityId: entityID, operation: operation,
        version: try Hlc.parseCanonical(versionRaw),
        payloadSchemaVersion: contract.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(.object(payload)), deviceId: deviceID)
    }
  }

  /// Delegate all typed matching to the production runtime validator. The
  /// fixture owns only source-tree authority/golden-file discovery.
  static func violations(
    for envelope: SyncEnvelope, contract: Contract? = nil
  ) throws -> [String] {
    SyncPayloadContractRegistry.violations(
      for: envelope, contract: try contract ?? load())
  }

  static func valueViolations(
    _ value: JSONValue, field: Field, context: String
  ) -> [String] {
    SyncPayloadContractRegistry.valueViolations(value, field: field, context: context)
  }
}

final class SyncPayloadContractTests: XCTestCase {
  private let version = "1743280000000_0001_c0dec0dec0dec0de"
  private let deviceID = "contract-probe"

  private func uuid(_ n: Int) -> String {
    "\(String(format: "%08x", n))-0000-7000-8000-000000000000"
  }

  private func replacingPayload(
    _ envelope: SyncEnvelope, mutate: (inout [String: JSONValue]) -> Void
  ) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(envelope.payload) else {
      throw NSError(
        domain: "SyncPayloadContractTests", code: 10,
        userInfo: [NSLocalizedDescriptionKey: "golden payload is not an object"])
    }
    mutate(&object)
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: envelope.operation, version: envelope.version,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: envelope.deviceId)
  }

  private func replacingSchemaVersion(
    _ envelope: SyncEnvelope, _ payloadSchemaVersion: UInt32
  ) -> SyncEnvelope {
    SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: envelope.operation, version: envelope.version,
      payloadSchemaVersion: payloadSchemaVersion, payload: envelope.payload,
      deviceId: envelope.deviceId)
  }

  func testEveryNumberedProductionManifestLoadsFromTheBundle() throws {
    for version in UInt32(1)...LorvexVersion.payloadSchemaVersion {
      let authority = try SyncPayloadContractFixture.load(version: version)
      let bundled = try SyncPayloadContractRegistry.contract(version: version)
      XCTAssertEqual(bundled.contractFormat, authority.contractFormat)
      XCTAssertEqual(bundled.payloadSchemaVersion, authority.payloadSchemaVersion)
      XCTAssertEqual(Set(bundled.entities.keys), Set(authority.entities.keys))
      XCTAssertEqual(bundled.goldenFixtureSHA256, authority.goldenFixtureSHA256)
    }
  }

  func testNumberedGoldenFixtureIsIndependentCompleteAndTyped() throws {
    let contract = try SyncPayloadContractFixture.load()
    let envelopes = try SyncPayloadContractFixture.goldenEnvelopes(contract: contract)
    XCTAssertEqual(envelopes.count, contract.entities.count)
    XCTAssertEqual(
      envelopes.map { $0.entityType.asString },
      envelopes.map { $0.entityType.asString }.sorted(),
      "golden envelopes must remain canonically ordered")
    XCTAssertEqual(
      Set(envelopes.map { $0.entityType.asString }), Set(contract.entities.keys),
      "golden fixture must contain exactly one populated upsert for every entity")

    for envelope in envelopes {
      XCTAssertEqual(envelope.operation, .upsert)
      XCTAssertEqual(
        try SyncPayloadContractFixture.violations(for: envelope, contract: contract), [],
        "typed golden contract mismatch for \(envelope.entityType.asString)")
      guard case .object(let payload)? = JSONValue.parse(envelope.payload) else {
        return XCTFail("golden payload must be an object")
      }
      XCTAssertEqual(
        payload["version"], .string(envelope.version.description),
        "upsert payload.version must equal the enclosing envelope HLC")
    }
  }

  func testTypedMatcherRejectsSameVersionSemanticDrift() throws {
    let envelopes = try SyncPayloadContractFixture.goldenEnvelopes()
    let byType = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.entityType, $0) })

    let nullability = try replacingPayload(try XCTUnwrap(byType[.task])) {
      $0["title"] = .null
    }
    XCTAssertFalse(try SyncPayloadContractFixture.violations(for: nullability).isEmpty)

    let enumDrift = try replacingPayload(try XCTUnwrap(byType[.task])) {
      $0["status"] = .string("future_status")
    }
    XCTAssertFalse(try SyncPayloadContractFixture.violations(for: enumDrift).isEmpty)

    let rangeDrift = try replacingPayload(try XCTUnwrap(byType[.task])) {
      $0["priority"] = .int(9)
    }
    XCTAssertFalse(try SyncPayloadContractFixture.violations(for: rangeDrift).isEmpty)

    let unitDrift = try replacingPayload(try XCTUnwrap(byType[.focusSchedule])) {
      guard case .array(var blocks)? = $0["blocks"], case .object(var first) = blocks[0] else {
        return
      }
      first["start_minutes"] = .string("09:00")
      blocks[0] = .object(first)
      $0["blocks"] = .array(blocks)
    }
    XCTAssertFalse(try SyncPayloadContractFixture.violations(for: unitDrift).isEmpty)

    let nestedObjectDrift = try replacingPayload(try XCTUnwrap(byType[.focusSchedule])) {
      guard case .array(var blocks)? = $0["blocks"], case .object(var first) = blocks[0] else {
        return
      }
      first["unreleased_field"] = .bool(true)
      blocks[0] = .object(first)
      $0["blocks"] = .array(blocks)
    }
    XCTAssertFalse(try SyncPayloadContractFixture.violations(for: nestedObjectDrift).isEmpty)

    let arrayItemDrift = try replacingPayload(try XCTUnwrap(byType[.calendarEvent])) {
      $0["attendees"] = .array([.string("not-an-attendee-object")])
    }
    XCTAssertFalse(try SyncPayloadContractFixture.violations(for: arrayItemDrift).isEmpty)

    let envelopeVersionDrift = try replacingPayload(try XCTUnwrap(byType[.task])) {
      $0["version"] = .string("1760000000000_0002_0123456789abcdef")
    }
    XCTAssertTrue(
      try SyncPayloadContractFixture.violations(for: envelopeVersionDrift)
        .contains { $0.contains("payload.version must equal envelope version") })
  }

  func testFutureFloorAllowsOnlyUnknownTopLevelFields() throws {
    let envelopes = try SyncPayloadContractFixture.goldenEnvelopes()
    let byType = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.entityType, $0) })
    let futureVersion = LorvexVersion.payloadSchemaVersion + 1

    let additive = replacingSchemaVersion(
      try replacingPayload(try XCTUnwrap(byType[.task])) {
        $0["future_optional_note"] = .string("preserve")
      },
      futureVersion)
    XCTAssertEqual(try SyncPayloadContractRegistry.violations(for: additive), [])

    let enumMutation = replacingSchemaVersion(
      try replacingPayload(try XCTUnwrap(byType[.task])) {
        $0["status"] = .string("future_status")
      },
      futureVersion)
    XCTAssertTrue(
      try SyncPayloadContractRegistry.violations(for: enumMutation)
        .contains { $0.contains("outside enum") })

    let nestedMutation = replacingSchemaVersion(
      try replacingPayload(try XCTUnwrap(byType[.focusSchedule])) {
        guard case .array(var blocks)? = $0["blocks"],
          case .object(var first) = blocks.first
        else { return }
        first["future_nested_key"] = .string("not shadowable")
        blocks[0] = .object(first)
        $0["blocks"] = .array(blocks)
      },
      futureVersion)
    XCTAssertTrue(
      try SyncPayloadContractRegistry.violations(for: nestedMutation)
        .contains { $0.contains("future_nested_key") })

    let reservedMutation = replacingSchemaVersion(
      try replacingPayload(try XCTUnwrap(byType[.habit])) {
        $0["lookup_key"] = .string("reserved")
      },
      futureVersion)
    XCTAssertTrue(
      try SyncPayloadContractRegistry.violations(for: reservedMutation)
        .contains { $0.contains("permanently reserved") })
  }

  func testProductionValidatorRejectsPayloadIdentityDrift() throws {
    let envelopes = try SyncPayloadContractFixture.goldenEnvelopes()
    let byType = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.entityType, $0) })

    let simple = try replacingPayload(try XCTUnwrap(byType[.task])) {
      $0["id"] = .string(uuid(801))
    }
    XCTAssertTrue(
      try SyncPayloadContractRegistry.violations(for: simple)
        .contains { $0.contains("payload.id must equal") })

    let natural = try replacingPayload(try XCTUnwrap(byType[.dailyReview])) {
      $0["date"] = .string("2026-07-16")
    }
    XCTAssertTrue(
      try SyncPayloadContractRegistry.violations(for: natural)
        .contains { $0.contains("payload.date must equal") })

    let composite = try replacingPayload(try XCTUnwrap(byType[.taskTag])) {
      $0["task_id"] = .string(uuid(802))
    }
    XCTAssertTrue(
      try SyncPayloadContractRegistry.violations(for: composite)
        .contains { $0.contains("payload.task_id must equal") })

    let redirect = try replacingPayload(try XCTUnwrap(byType[.entityRedirect])) {
      $0["source_id"] = .string(uuid(803))
    }
    XCTAssertTrue(
      try SyncPayloadContractRegistry.violations(for: redirect)
        .contains { $0.contains("source identity digest") })
  }

  func testMalformedFutureKnownFieldRejectsBeforeWholeSchemaHold() throws {
    let task = try XCTUnwrap(
      SyncPayloadContractFixture.goldenEnvelopes().first { $0.entityType == .task })
    let malformed = replacingSchemaVersion(
      try replacingPayload(task) { $0["status"] = .string("future_status") },
      LorvexVersion.payloadSchemaVersion + 2)
    let store = try SyncTestSupport.freshStore()
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())

    try store.writer.write { db in
      XCTAssertThrowsError(
        try Apply.applyEnvelope(db, registry: registry, envelope: malformed)
      ) { error in
        guard case ApplyError.invalidPayload(let detail) = error else {
          return XCTFail("expected invalidPayload before schema hold, got \(error)")
        }
        XCTAssertTrue(detail.contains("outside enum"))
      }
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_pending_inbox"), 0)
    }
  }

  func testFinalOutboxBoundaryRejectsIdentityDrift() throws {
    let task = try XCTUnwrap(
      SyncPayloadContractFixture.goldenEnvelopes().first { $0.entityType == .task })
    let malformed = try replacingPayload(task) { $0["id"] = .string(uuid(804)) }
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      XCTAssertThrowsError(try Outbox.enqueueCoalesced(db, malformed)) { error in
        guard case Outbox.OutboxError.invalidPayloadContract(let detail) = error else {
          return XCTFail("expected invalidPayloadContract, got \(error)")
        }
        XCTAssertTrue(detail.contains("payload.id must equal"))
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testNumberedGoldenUpsertsAreAcceptedByRealInboundAppliers() throws {
    for version in UInt32(1)...LorvexVersion.payloadSchemaVersion {
      let contract = try SyncPayloadContractFixture.load(version: version)
      let envelopes = try SyncPayloadContractFixture.goldenEnvelopes(contract: contract)
      let grouped = Dictionary(grouping: envelopes, by: { $0.entityType.asString })
      XCTAssertTrue(grouped.values.allSatisfy { $0.count == 1 })
      let store = try SyncTestSupport.freshStore()
      let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())

      try store.writer.write { db in
        _ = try AuditRetentionFrontier.activateAccount(
          db, accountIdentifier: "golden-contract-account", zoneName: "LorvexZone-golden")

        let orderedTypes = EntityKind.topologicalEntityOrder.filter {
          contract.entities[$0] != nil
        }
        XCTAssertEqual(
          Set(orderedTypes).union([EntityName.aiChangelog]), Set(contract.entities.keys),
          "every entity in payload contract v\(version) must have an apply order")
        for entityType in orderedTypes {
          if entityType == EdgeName.taskDependency {
            // Use two dedicated active endpoints. The golden task intentionally
            // exercises cancelled + archived fields, and a live dependency on
            // that row would now be accepted only as a derived delete repair
            // rather than proving the edge's ordinary upsert path.
            for taskID in [uuid(202), uuid(203)] {
              try db.execute(
                sql: """
                  INSERT INTO tasks
                    (id, list_id, title, status, version, created_at, updated_at)
                  VALUES (?, ?, 'Golden dependency endpoint', 'open', ?, ?, ?)
                  """,
                arguments: [
                  taskID, uuid(1), "0000000000000_0000_0000000000000000",
                  "2026-07-15T12:34:56.000Z", "2026-07-15T12:34:56.000Z",
                ])
            }
          }
          let envelope = try XCTUnwrap(grouped[entityType]?.first)
          let result = try Apply.applyEnvelope(
            db, registry: registry, envelope: envelope)
          if envelope.entityType == .currentFocus || envelope.entityType == .focusSchedule {
            // The golden task deliberately exercises the cancelled + archived
            // fields, while both golden day roots deliberately reference that
            // same identity. The payload remains valid wire input, but the
            // absorbing task-state invariant must normalize the root to a
            // typed Delete repair instead of materializing an invalid reference.
            guard case .repairRequired(
              .propagateTaskRollover(let targets, let additionalFloor)) = result
            else {
              return XCTFail(
                "expected day-root reference repair for payload contract v\(version) "
                  + "\(entityType) envelope, got \(result)")
            }
            XCTAssertEqual(additionalFloor, envelope.version)
            XCTAssertEqual(
              targets,
              [
                .relatedEntity(
                  entityType: envelope.entityType, entityId: envelope.entityId,
                  operation: .delete, knownVersionFloor: envelope.version)
              ])
          } else {
            XCTAssertEqual(
              result, .applied,
              "real inbound applier rejected payload contract v\(version) \(entityType) envelope")
          }
        }

        let audit = try XCTUnwrap(grouped[EntityName.aiChangelog]?.first)
        XCTAssertEqual(
          try Apply.applyEnvelope(db, registry: registry, envelope: audit), .applied,
          "real inbound audit applier rejected payload contract v\(version) envelope")
      }
    }
  }

  func testCurrentManifestMatchesKnownWireOwnershipAndOperationInvariants() throws {
    let contract = try SyncPayloadContractFixture.load()
    XCTAssertEqual(contract.contractFormat, 3)
    XCTAssertEqual(contract.payloadSchemaVersion, LorvexVersion.payloadSchemaVersion)

    let syncableTypes = EntityKind.allSyncableTypes
    XCTAssertEqual(Set(syncableTypes).count, syncableTypes.count)
    XCTAssertEqual(Set(contract.entities.keys), Set(syncableTypes))

    for entityType in syncableTypes {
      let entity = try XCTUnwrap(contract.entities[entityType])
      let upsert = entity.operations.upsert
      XCTAssertEqual(upsert.requiredKeys, upsert.requiredKeys.sorted())
      XCTAssertEqual(upsert.optionalKeys, upsert.optionalKeys.sorted())
      XCTAssertTrue(Set(upsert.requiredKeys).isDisjoint(with: upsert.optionalKeys))
      XCTAssertTrue(upsert.requiredKeys.contains("version"))

      let canonicalWireKeys = Set(upsert.requiredKeys).union(upsert.optionalKeys)
      XCTAssertTrue(canonicalWireKeys.isSubset(of: entity.fields.keys))
      XCTAssertEqual(
        canonicalWireKeys, Set(PayloadShadow.wireKeysForEntity(entityType)),
        "\(entityType): manifest must equal the runtime's known upsert wire keys")
      XCTAssertEqual(
        Set(entity.syntheticKeys), Set(PayloadShadow.syntheticWireKeysForEntity(entityType)),
        "\(entityType): manifest synthetic keys must equal the runtime projection")
      let runtimeReserved = Set(PayloadShadow.ownedKeysForEntity(entityType))
        .subtracting(PayloadShadow.wireKeysForEntity(entityType))
      XCTAssertEqual(
        Set(contract.shadowReservedKeys[entityType] ?? []), runtimeReserved,
        "\(entityType): manifest must freeze every non-wire key older shadows strip")
      XCTAssertTrue(Set(entity.syntheticKeys).isSubset(of: canonicalWireKeys))

      let shapes = entity.operations.delete.shapes
      XCTAssertEqual(
        shapes.isEmpty,
        entityType == EntityName.aiChangelog || entityType == EntityName.entityRedirect,
        "only append-only audit and absorbing redirect contracts may omit a delete shape")
      XCTAssertEqual(shapes.map(\.name), shapes.map(\.name).sorted())
      XCTAssertEqual(Set(shapes.map(\.name)).count, shapes.count)
      for shape in shapes {
        XCTAssertTrue(shape.requiredKeys.contains("version"))
        XCTAssertTrue(Set(shape.requiredKeys).isDisjoint(with: shape.optionalKeys))
        if let marker = shape.markerKey { XCTAssertTrue(shape.requiredKeys.contains(marker)) }
        if shape.name == "tombstone" {
          XCTAssertNil(shape.markerKey)
          XCTAssertEqual(Set(shape.requiredKeys), ["version"])
          XCTAssertEqual(Set(shape.optionalKeys), canonicalWireKeys.subtracting(["version"]))
        }
        XCTAssertTrue(
          Set(shape.requiredKeys).union(shape.optionalKeys).isSubset(of: entity.fields.keys))
      }
      let usedKeys = shapes.reduce(canonicalWireKeys) {
        $0.union($1.requiredKeys).union($1.optionalKeys)
      }
      XCTAssertEqual(usedKeys, Set(entity.fields.keys))
    }

    XCTAssertEqual(contract.entities[EntityName.task]?.fields["estimated_minutes"]?.unit, "minutes")
    let blockFields = contract.entities[EntityName.focusSchedule]?.fields["blocks"]?
      .items?.properties
    XCTAssertEqual(blockFields?["start_minutes"]?.unit, "minute-of-day")
    XCTAssertEqual(blockFields?["end_minutes"]?.unit, "minute-of-day")
  }

  func testAiChangelogProductionUpsertFunnelMatchesManifest() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let id = uuid(901)
      let row = ChangelogWrite.ChangelogRow(
        id: id, timestamp: "2026-07-14T12:00:00.000Z", operation: "update",
        entityType: "task", entityId: nil, entityIds: [],
        summary: "Contract probe", initiatedBy: "assistant", mcpTool: nil,
        sourceDeviceId: deviceID, beforeJson: nil, afterJson: nil,
        retentionEpoch: 7)
      try ChangelogWrite.writeChangelogRow(db, row)
      let payload = try ChangelogWrite.buildChangelogSyncPayload(row)
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: EntityName.aiChangelog, entityId: id, payload: payload,
        context: OutboxWriteContext(version: version, deviceId: deviceID))
      let envelope = try XCTUnwrap(Outbox.getPending(db).first?.envelope)
      XCTAssertEqual(envelope.entityType, .aiChangelog)
      XCTAssertEqual(try SyncPayloadContractFixture.violations(for: envelope), [])
      guard case .object(let object)? = JSONValue.parse(envelope.payload) else {
        return XCTFail("final ai_changelog payload must be an object")
      }
      XCTAssertEqual(object["retention_epoch"], .int(7))
      XCTAssertNil(object["retention_account_identifier"])
      XCTAssertNil(object["cloud_presence_possible"])
    }
  }

  func testProductionDeleteFunnelMatchesEachExactOperationShape() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      var index = 1
      for rawType in EntityKind.allSyncableTypes
      where rawType != EntityName.aiChangelog && rawType != EntityName.entityRedirect
        && rawType != EntityName.calendarSeriesCutover
      {
        let kind = try XCTUnwrap(EntityKind.parse(rawType))
        let entityID: String
        switch kind {
        case .preference: entityID = PreferenceKeys.prefWorkingHours
        case .dailyReview, .currentFocus, .focusSchedule: entityID = "2026-07-14"
        case .taskTag, .taskDependency, .taskCalendarEventLink:
          entityID = "\(uuid(1000 + index)):\(uuid(2000 + index))"
        case .habitCompletion:
          entityID = "\(uuid(1000 + index)):2026-07-14"
        default: entityID = uuid(1000 + index)
        }
        try OutboxEnqueue.enqueuePayloadDelete(
          db, entityType: rawType, entityId: entityID, payload: .object([:]),
          context: OutboxWriteContext(version: version, deviceId: deviceID))
        index += 1
      }

      XCTAssertThrowsError(
        try OutboxEnqueue.enqueuePayloadDelete(
          db, entityType: EntityName.aiChangelog, entityId: uuid(3000),
          payload: .object([:]),
          context: OutboxWriteContext(version: version, deviceId: deviceID))
      ) { error in
        guard case EnqueueError.unsupportedOperation(let entityType, let operation) = error else {
          return XCTFail("expected unsupportedOperation, got \(error)")
        }
        XCTAssertEqual(entityType, EntityName.aiChangelog)
        XCTAssertEqual(operation, "delete")
      }

      XCTAssertThrowsError(
        try OutboxEnqueue.enqueuePayloadDelete(
          db, entityType: EntityName.entityRedirect,
          entityId: String(repeating: "a", count: 64), payload: .object([:]),
          context: OutboxWriteContext(version: version, deviceId: deviceID)))

      XCTAssertThrowsError(
        try OutboxEnqueue.enqueuePayloadDelete(
          db, entityType: EntityName.calendarSeriesCutover,
          entityId: uuid(3001), payload: .object([:]),
          context: OutboxWriteContext(version: version, deviceId: deviceID))
      ) { error in
        guard case EnqueueError.unsupportedOperation(let entityType, let operation) = error else {
          return XCTFail("expected unsupportedOperation, got \(error)")
        }
        XCTAssertEqual(entityType, EntityName.calendarSeriesCutover)
        XCTAssertEqual(operation, "delete")
      }

      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, EntityKind.allSyncableTypes.count - 3)
      for item in pending {
        XCTAssertEqual(
          try SyncPayloadContractFixture.violations(for: item.envelope), [],
          "final delete contract mismatch for \(item.envelope.entityType.asString): "
            + item.envelope.payload)
      }
    }
  }

  func testAiChangelogContractRejectsEveryDeletePayload() throws {
    let payloads = [
      #"{}"#,
      #"{"retention_prune":true,"version":"1743280000000_0001_c0dec0dec0dec0de"}"#,
      #"{"reset_all_data":true,"retention_prune":true,"version":"1743280000000_0001_c0dec0dec0dec0de"}"#,
    ]
    for (offset, payload) in payloads.enumerated() {
      let envelope = SyncEnvelope(
        entityType: .aiChangelog, entityId: uuid(4000 + offset), operation: .delete,
        version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: deviceID)
      XCTAssertFalse(try SyncPayloadContractFixture.violations(for: envelope).isEmpty)
    }
  }
}
