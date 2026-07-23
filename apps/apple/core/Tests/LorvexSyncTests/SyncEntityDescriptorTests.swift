import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Structural guards on ``SyncEntityDescriptor`` — the single per-entity
/// declaration from which the outbound generic reader, inbound LWW upsert, and
/// payload-shadow owned keys take distinct role-based projections.
///
/// These lock the descriptor to the SQLite schema so a column add/remove that is
/// not mirrored into the descriptor fails HERE, in addition to
/// `SyncFieldRoundTripProbeTests` (outbound → inbound value round-trip) and
/// `PayloadShadowTests.testPayloadShadowSchemaParity` (owned keys ↔ schema).
final class SyncEntityDescriptorTests: XCTestCase {

  /// Entities whose OUTBOUND payload is built by the generic reader
  /// (`readGenericEntityPayloadSnapshot`), which sources its column list from the
  /// descriptor. For these the descriptor's outbound columns MUST equal the
  /// table's non-device-local columns minus explicitly declared derived-local
  /// storage, or the shipped payload would silently gain or drop a field.
  ///
  /// DERIVED from the registry — every descriptor whose `outbound` seam is
  /// `.genericReader` — rather than hand-maintained, so a newly-migrated
  /// generic-reader entity is picked up automatically and cannot fall out of sync
  /// with the descriptors themselves.
  ///
  /// `preference` is intentionally excluded by the seam: its outbound uses the
  /// dedicated JSON-in-TEXT loader (`PayloadLoaders.loadPreferenceSyncPayload`),
  /// selected before the generic reader, so its `outbound` seam is `.customBuilder`
  /// and its plain columns are never consulted outbound.
  private var genericOutboundEntities: [EntityKind] {
    SyncEntityDescriptor.registry.values
      .filter { $0.outbound == .genericReader }
      .map(\.entity)
  }

  private func pragmaColumns(_ db: Database, _ table: String) throws -> [String] {
    try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('\(table)') ORDER BY cid")
      .filter { !StorageSchema.isDeviceLocalColumn(table: table, column: $0) }
  }

  /// Per-descriptor role invariants that hold without a DB: projections contain
  /// no duplicates; outbound/synthetic keys are wire-owned; derived-local columns
  /// are inbound-only but shadow-consumed; and inbound columns end with `version`.
  func testEveryDescriptorIsInternallyConsistent() {
    XCTAssertFalse(SyncEntityDescriptor.registry.isEmpty, "no descriptors registered")
    for (kind, descriptor) in SyncEntityDescriptor.registry {
      XCTAssertEqual(descriptor.entity, kind, "registry key must match descriptor.entity")

      let wire = descriptor.wireKeys
      let shadowConsumed = descriptor.shadowConsumedKeys
      XCTAssertEqual(
        Set(wire).count, wire.count, "\(kind.asString): wire keys contain a duplicate")
      XCTAssertEqual(
        Set(shadowConsumed).count, shadowConsumed.count,
        "\(kind.asString): shadow-consumed keys contain a duplicate")

      let plain = descriptor.plainColumns
      XCTAssertEqual(
        Set(plain).count, plain.count, "\(kind.asString): plain columns contain a duplicate")
      let outbound = descriptor.outboundColumns
      let synthetic = descriptor.syntheticKeys
      let derived = descriptor.derivedLocalColumns
      XCTAssertEqual(Set(outbound).count, outbound.count)
      XCTAssertEqual(Set(synthetic).count, synthetic.count)
      XCTAssertEqual(Set(derived).count, derived.count)
      for column in outbound + synthetic {
        XCTAssertTrue(
          wire.contains(column),
          "\(kind.asString): emitted field \(column) is not a wire key")
      }
      for column in derived {
        XCTAssertTrue(plain.contains(column), "\(kind.asString): derived column must be inbound")
        XCTAssertFalse(wire.contains(column), "\(kind.asString): derived column leaked into wire")
        XCTAssertTrue(
          shadowConsumed.contains(column),
          "\(kind.asString): derived column must be stripped from future payload shadows")
      }
      XCTAssertEqual(Set(plain), Set(outbound + derived))
      XCTAssertEqual(Set(wire), Set(outbound + synthetic))
      XCTAssertEqual(Set(shadowConsumed), Set(wire + derived))
      XCTAssertEqual(
        plain.last, "version",
        "\(kind.asString): plain columns must end with `version` (LwwUpsertSpec invariant)")

      XCTAssertEqual(
        shadowConsumed, PayloadShadow.ownedKeysForEntity(kind.asString),
        "\(kind.asString): ownedKeysForEntity must derive from the descriptor")
    }
  }

  /// Every descriptor in ``SyncEntityDescriptor/all`` must survive into the
  /// registry. The registry builder `precondition`s on a duplicate entity, but a
  /// duplicate that slipped a `precondition`-disabled build would silently shrink
  /// the map (dictionary insert of a repeated key overwrites); this count equality
  /// catches that regression regardless of build configuration.
  func testRegistryContainsEveryDescriptor() {
    XCTAssertEqual(
      SyncEntityDescriptor.all.count, SyncEntityDescriptor.registry.count,
      "registry count must equal all.count — a duplicate entity would shrink the registry")
  }

  /// The generic-outbound entities' storage fields must classify every real
  /// non-device-local column as either transmitted or derived locally.
  func testGenericOutboundDescriptorsMatchSchemaColumns() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.read { db in
      for kind in genericOutboundEntities {
        let descriptor = try XCTUnwrap(
          SyncEntityDescriptor.descriptor(for: kind), "\(kind.asString) has no descriptor")
        let table = try XCTUnwrap(kind.tablePk?.table, "\(kind.asString) has no tablePk")
        let schema = Set(try pragmaColumns(db, table))
        XCTAssertEqual(Set(descriptor.plainColumns), schema)
        XCTAssertEqual(
          Set(descriptor.outboundColumns), schema.subtracting(descriptor.derivedLocalColumns),
          "\(kind.asString): generic outbound columns must equal schema minus derived-local columns")
      }
    }
  }

  /// Every descriptor's plain columns must be real columns of its table, so a
  /// typo'd or renamed column in any descriptor (generic-outbound or not, edges
  /// included) fails here rather than at inbound bind time. Edges carry a
  /// composite PK, so their table is resolved via `tableName` (`tablePk` is nil).
  func testEveryDescriptorPlainColumnExistsInItsTable() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.read { db in
      for (kind, descriptor) in SyncEntityDescriptor.registry {
        let table = try XCTUnwrap(kind.tableName, "\(kind.asString) has no table")
        let schema = Set(
          try String.fetchAll(
            db, sql: "SELECT name FROM pragma_table_info('\(table)') ORDER BY cid"))
        for column in descriptor.plainColumns {
          XCTAssertTrue(
            schema.contains(column),
            "\(kind.asString): plain column \(column) is not a real column of \(table)")
        }
      }
    }
  }

  func testLookupKeysAreDerivedLocalStorageNotWireFields() {
    for kind in [EntityKind.habit, .tag] {
      let descriptor = SyncEntityDescriptor.require(kind)
      XCTAssertEqual(descriptor.derivedLocalColumns, ["lookup_key"])
      XCTAssertTrue(descriptor.plainColumns.contains("lookup_key"))
      XCTAssertFalse(descriptor.outboundColumns.contains("lookup_key"))
      XCTAssertFalse(descriptor.wireKeys.contains("lookup_key"))
      XCTAssertTrue(descriptor.shadowConsumedKeys.contains("lookup_key"))
    }
  }

  func testDerivedLookupKeysAreStrippedInsteadOfPreservedInPayloadShadow() throws {
    for kind in [EntityKind.habit, .tag] {
      let trimmed = try XCTUnwrap(
        PayloadShadow.stripKnownKeysForShadow(
          entityType: kind.asString,
          rawPayloadJSON: #"{"future_field":"keep","lookup_key":"never-reemit"}"#))
      guard case .object(let object)? = JSONValue.parse(trimmed) else {
        return XCTFail("trimmed shadow must be an object")
      }
      XCTAssertEqual(object["future_field"], .string("keep"))
      XCTAssertNil(object["lookup_key"])
    }
  }
}
