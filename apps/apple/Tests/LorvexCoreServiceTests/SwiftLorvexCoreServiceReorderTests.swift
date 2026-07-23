import GRDB
import LorvexStore
import XCTest

@testable import LorvexCore

/// UI-3: the manual order of lists and habits is a synced `position` column set
/// through `reorderLists` / `reorderHabits`. The catalog reads order by it, and
/// each row that actually moves has its `version` bumped + an envelope enqueued,
/// so the order converges across devices like any other last-writer-wins field.
///
/// A reorder is a full-permutation operation: `orderedIDs` must be exactly the
/// active (non-archived) set. The whole permutation is validated and applied in
/// one `withWrite` transaction, so the resulting positions are dense
/// (`0…n-1`, no collisions/gaps) and a rejected reorder — or any throw inside
/// the transaction — leaves the stored order byte-identical.
final class SwiftLorvexCoreServiceReorderTests: XCTestCase {

  /// Deterministic HLC time source: every mint gets a fresh, strictly
  /// increasing physical millisecond, so version-bump assertions are
  /// independent of wall-clock resolution and machine load.
  private final class MonotonicTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var ms: UInt64 = 1_800_000_000_000
    func next() -> UInt64 {
      lock.lock()
      defer { lock.unlock() }
      ms += 1
      return ms
    }
  }

  private func withDeterministicHlcClock<T>(
    _ body: () async throws -> T
  ) async rethrows -> T {
    let clock = MonotonicTestClock()
    return try await SwiftLorvexCoreService.$hlcPhysicalNowMsForTesting.withValue(
      { clock.next() }, operation: body)
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func todayYmd() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
  }

  private func outboxCount(_ service: SwiftLorvexCoreService) throws -> Int64 {
    try service.read { db in try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? 0 }
  }

  private func version(_ service: SwiftLorvexCoreService, table: String, id: String) throws
    -> String?
  {
    try service.read { db in
      try String.fetchOne(db, sql: "SELECT version FROM \(table) WHERE id = ?", arguments: [id])
    }
  }

  /// Every row's stored `position`, keyed by id — used to assert a rejected
  /// reorder mutated nothing.
  private func positions(_ service: SwiftLorvexCoreService, table: String) throws -> [String: Int64]
  {
    try service.read { db in
      var map: [String: Int64] = [:]
      for row in try Row.fetchAll(db, sql: "SELECT id, position FROM \(table)") {
        map[row["id"]] = row["position"]
      }
      return map
    }
  }

  // MARK: - Lists

  /// A full reversal of the entire active catalog persists exactly, and the
  /// stored positions come out dense (`0…n-1`) — no collision, no gap.
  func testReorderListsFullReversalPersistsDensely() async throws {
    let service = try makeService()
    _ = try await service.createList(name: "Alpha", description: nil)
    _ = try await service.createList(name: "Beta", description: nil)
    _ = try await service.createList(name: "Gamma", description: nil)

    // The active set includes the seeded `inbox` list; the whole set must be
    // permuted, so build the desired order from the full current order.
    let current = try await service.loadLists().lists.map(\.id)
    let desired = Array(current.reversed())

    let snapshot = try await service.reorderLists(orderedIDs: desired)
    XCTAssertEqual(
      snapshot.lists.map(\.id), desired, "the reorder return surfaces the whole set reversed")

    let reloaded = try await service.loadLists().lists.map(\.id)
    XCTAssertEqual(reloaded, desired, "a fresh loadLists returns the reversed order")

    // Positions are dense 0..n-1 in catalog order — no duplicate or gapped keys.
    let byId = try positions(service, table: "lists")
    let orderedPositions = desired.map { byId[$0] }
    XCTAssertEqual(
      orderedPositions, (0..<Int64(desired.count)).map { Optional($0) },
      "stored positions are a dense 0..n-1 sequence in the new order")
  }

  /// Only the rows whose position actually changes are re-stamped: reordering a
  /// densified catalog so two rows swap and the rest hold leaves the unmoved
  /// rows' `version` untouched, and enqueues only the movers.
  func testReorderListsBumpsOnlyMovedRows() async throws {
    try await withDeterministicHlcClock {
      let service = try self.makeService()
      let a = try await service.createList(name: "Alpha", description: nil)
      let b = try await service.createList(name: "Beta", description: nil)
      let c = try await service.createList(name: "Gamma", description: nil)

      // Densify to [inbox, a, b, c] (positions 0,1,2,3).
      let densified = try await service.loadLists().lists.map(\.id)
      _ = try await service.reorderLists(orderedIDs: densified)

      let inboxID = densified[0]
      let inboxBefore = try self.version(service, table: "lists", id: inboxID)
      let aBefore = try self.version(service, table: "lists", id: a.id)
      let bBefore = try self.version(service, table: "lists", id: b.id)
      let cBefore = try self.version(service, table: "lists", id: c.id)

      // Swap only b and c; inbox and a keep their positions.
      _ = try await service.reorderLists(orderedIDs: [inboxID, a.id, c.id, b.id])

      XCTAssertEqual(
        try self.version(service, table: "lists", id: inboxID), inboxBefore,
        "inbox stays untouched")
      XCTAssertEqual(
        try self.version(service, table: "lists", id: a.id), aBefore,
        "the unmoved list stays untouched")
      XCTAssertNotEqual(
        try self.version(service, table: "lists", id: b.id), bBefore,
        "a moved list's version bumps")
      XCTAssertNotEqual(
        try self.version(service, table: "lists", id: c.id), cBefore,
        "a moved list's version bumps")

      let order = try await service.loadLists().lists.map(\.id)
      XCTAssertEqual(order, [inboxID, a.id, c.id, b.id], "the catalog now shows c before b")
    }
  }

  func testReorderListsToSameOrderIsANoOp() async throws {
    let service = try makeService()
    _ = try await service.createList(name: "Alpha", description: nil)
    _ = try await service.createList(name: "Beta", description: nil)

    // First reorder densifies positions; a second reorder to the same order must
    // enqueue nothing.
    let order = try await service.loadLists().lists.map(\.id)
    _ = try await service.reorderLists(orderedIDs: order)
    let outboxBefore = try outboxCount(service)
    _ = try await service.reorderLists(orderedIDs: order)
    XCTAssertEqual(try outboxCount(service), outboxBefore, "an unchanged reorder enqueues nothing")
  }

  /// A non-permutation input (missing id, unknown id, or a duplicate) is
  /// rejected, and — because the throw unwinds the whole `withWrite`
  /// transaction — leaves every position, version, and the outbox untouched.
  func testReorderListsRejectsNonPermutationAndLeavesOrderUnchanged() async throws {
    let service = try makeService()
    _ = try await service.createList(name: "Alpha", description: nil)
    _ = try await service.createList(name: "Beta", description: nil)

    // Densify first so there is a concrete dense ordering to protect.
    let order = try await service.loadLists().lists.map(\.id)
    _ = try await service.reorderLists(orderedIDs: order)

    let positionsBefore = try positions(service, table: "lists")
    let versionsBefore = try order.map { try version(service, table: "lists", id: $0) }
    let outboxBefore = try outboxCount(service)

    func expectRejected(_ ids: [String], _ why: String) async throws {
      do {
        _ = try await service.reorderLists(orderedIDs: ids)
        XCTFail("expected reorderLists to reject: \(why)")
      } catch {
        XCTAssertTrue(
          error is LorvexCoreError, "reorder rejection surfaces a LorvexCoreError (\(why))")
      }
      XCTAssertEqual(
        try positions(service, table: "lists"), positionsBefore,
        "positions unchanged after a rejected reorder (\(why))")
      XCTAssertEqual(
        try order.map { try version(service, table: "lists", id: $0) }, versionsBefore,
        "versions unchanged after a rejected reorder (\(why))")
      XCTAssertEqual(
        try outboxCount(service), outboxBefore,
        "outbox unchanged after a rejected reorder (\(why))")
    }

    try await expectRejected(Array(order.dropLast()), "missing an in-scope id")
    try await expectRejected(order + ["ghost-list-id"], "an unknown id not in the set")
    try await expectRejected(order + [order[0]], "a duplicated id")

    // Order still reads exactly as it did before the rejected attempts.
    let reloaded = try await service.loadLists().lists.map(\.id)
    XCTAssertEqual(reloaded, order, "the catalog order is exactly what it was before rejection")
  }

  // MARK: - Habits

  func testReorderHabitsPersistsAndOrdersCatalog() async throws {
    let service = try makeService()
    let today = todayYmd()
    let a = try await service.createHabit(name: "Alpha", cue: nil, targetCount: 1)
    let b = try await service.createHabit(name: "Beta", cue: nil, targetCount: 1)
    let c = try await service.createHabit(name: "Gamma", cue: nil, targetCount: 1)

    let desired = [c.id, a.id, b.id]
    let snapshot = try await service.reorderHabits(orderedIDs: desired, date: today)
    XCTAssertEqual(snapshot.habits.map(\.id), desired, "the reorder return is in the new order")

    let reloaded = try await service.loadHabits(date: today).habits.map(\.id)
    XCTAssertEqual(reloaded, desired, "a fresh loadHabits returns them in stored position order")

    // Positions are dense 0..n-1 in the new order.
    let byId = try positions(service, table: "habits")
    XCTAssertEqual(
      desired.map { byId[$0] }, (0..<Int64(desired.count)).map { Optional($0) },
      "stored habit positions are dense 0..n-1")
  }

  func testReorderHabitsBumpsMovedRowVersion() async throws {
    let service = try makeService()
    let today = todayYmd()
    let a = try await service.createHabit(name: "Alpha", cue: nil, targetCount: 1)
    let b = try await service.createHabit(name: "Beta", cue: nil, targetCount: 1)

    let aBefore = try version(service, table: "habits", id: a.id)
    let bBefore = try version(service, table: "habits", id: b.id)

    _ = try await service.reorderHabits(orderedIDs: [b.id, a.id], date: today)

    XCTAssertNotEqual(
      try version(service, table: "habits", id: a.id), aBefore, "the moved habit's version bumps")
    XCTAssertEqual(
      try version(service, table: "habits", id: b.id), bBefore,
      "the habit that stayed at position 0 is untouched")

    let order = try await service.loadHabits(date: today).habits.map(\.id)
    XCTAssertEqual(order, [b.id, a.id], "the board now shows b before a")
  }

  func testReorderHabitsRejectsNonPermutationAndLeavesOrderUnchanged() async throws {
    let service = try makeService()
    let today = todayYmd()
    let a = try await service.createHabit(name: "Alpha", cue: nil, targetCount: 1)
    let b = try await service.createHabit(name: "Beta", cue: nil, targetCount: 1)
    let c = try await service.createHabit(name: "Gamma", cue: nil, targetCount: 1)

    let order = [a.id, b.id, c.id]
    _ = try await service.reorderHabits(orderedIDs: order, date: today)

    let positionsBefore = try positions(service, table: "habits")
    let outboxBefore = try outboxCount(service)

    func expectRejected(_ ids: [String], _ why: String) async throws {
      do {
        _ = try await service.reorderHabits(orderedIDs: ids, date: today)
        XCTFail("expected reorderHabits to reject: \(why)")
      } catch {
        XCTAssertTrue(
          error is LorvexCoreError, "reorder rejection surfaces a LorvexCoreError (\(why))")
      }
      XCTAssertEqual(
        try positions(service, table: "habits"), positionsBefore,
        "habit positions unchanged after a rejected reorder (\(why))")
      XCTAssertEqual(
        try outboxCount(service), outboxBefore,
        "outbox unchanged after a rejected reorder (\(why))")
    }

    try await expectRejected([a.id, b.id], "missing an in-scope id")
    try await expectRejected(order + ["ghost-habit-id"], "an unknown id not in the set")
    try await expectRejected(order + [b.id], "a duplicated id")

    let reloaded = try await service.loadHabits(date: today).habits.map(\.id)
    XCTAssertEqual(reloaded, order, "the board order is exactly what it was before rejection")
  }
}
