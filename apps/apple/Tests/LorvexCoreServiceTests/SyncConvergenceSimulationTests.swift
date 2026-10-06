import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// Randomized multi-replica sync simulation.
///
/// Two or three in-memory cores play devices that never talk to each other
/// directly. Every local mutation lands in the replica's outbox; the harness
/// drains the outbox and carries the envelopes to the other replicas through a
/// transport. After a run of mixed operations the transport is drained to
/// quiescence and each replica's complete state is read back as full-resync
/// envelopes. Strong eventual consistency means those sets are identical.
///
/// Two transports exist (`LORVEX_SYNC_SIM_TRANSPORT`):
///
/// - `log` (default) models a CloudKit zone. Envelopes enter one ordered server
///   log in each device's emission order, every replica reads the log forward
///   from its own cursor in pages of random size, now and then re-reads a few
///   entries it has already applied, and (in half the seeds) a newer envelope
///   replaces the older one of the same entity, the way a record slot does.
/// - `chaos` keeps a queue per direction and delivers any subset of it in random
///   order, so even one device's own emissions arrive reordered. It finds
///   order-dependence the real transport does not exercise.
///
/// `LORVEX_SYNC_SIM_SEEDS`, `LORVEX_SYNC_SIM_STEPS`, and
/// `LORVEX_SYNC_SIM_FIRST_SEED` widen or move a run for a soak.
///
/// The default seeds pass. A soak over many more seeds can still report
/// divergence, because a few orderings are not yet convergent:
///
/// - A task hard-delete concurrent with an edit, when the task's child edges
///   reach a replica in an earlier chunk than the upsert that resurrects it.
/// - A tag delete that cascades a newer live task-tag edge before the upsert
///   that resurrects the tag.
/// - An alias-source delete that reaches a replica before its redirect
///   (reachable on the `chaos` transport only, which reorders one device's
///   emissions), and one whose redirect is parked on a winner that replica does
///   not know yet, cascade the loser's live edges away.
/// - The completions of a merged habit are not folded onto the winner's key.
final class SyncConvergenceSimulationTests: XCTestCase {

  func testReplicasConvergeAfterRandomOperationsAndDeliveryOrders() async throws {
    let environment = ProcessInfo.processInfo.environment
    let seeds = Int(environment["LORVEX_SYNC_SIM_SEEDS"] ?? "") ?? 8
    let steps = Int(environment["LORVEX_SYNC_SIM_STEPS"] ?? "") ?? 120
    let firstSeed = UInt64(environment["LORVEX_SYNC_SIM_FIRST_SEED"] ?? "") ?? 1
    let transport = Transport(rawValue: environment["LORVEX_SYNC_SIM_TRANSPORT"] ?? "") ?? .log
    var failures: [String] = []
    for offset in 0..<seeds {
      let seed = firstSeed + UInt64(offset)
      let run = try SimulationRun(seed: seed, transport: transport)
      let problems = await run.execute(steps: steps)
      if !problems.isEmpty {
        failures.append("seed \(seed): " + problems.joined(separator: "\n"))
      }
    }
    XCTAssertTrue(failures.isEmpty, "\n" + failures.joined(separator: "\n\n"))
  }
}

// MARK: - Harness

private struct SplitMix64: RandomNumberGenerator {
  var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

private final class Replica {
  let name: String
  let service: SwiftLorvexCoreService

  init(name: String) throws {
    self.name = name
    self.service = try SwiftLorvexCoreService.inMemory()
  }
}

private enum Transport: String {
  case log
  case chaos
}

private struct Channel {
  let from: Int
  let to: Int
  var queue: [SyncEnvelope] = []
}

/// An envelope on its way to a replica, with the replica that emitted it.
private struct InFlight {
  let envelope: SyncEnvelope
  let source: Int
}

private struct LogEntry {
  let sequence: Int
  let flight: InFlight
}

private final class SimulationRun {
  let seed: UInt64
  var rng: SplitMix64
  let replicas: [Replica]
  let transport: Transport
  var channels: [Channel] = []
  var serverLog: [LogEntry] = []
  var nextSequence = 1
  var cursors: [Int]
  let coalescing: Bool
  var log: [String] = []
  var trace: [String] = []
  var notes: [String] = []
  var unexpected: [String] = []
  var counter = 0

  static let tagPool = ["work", "Work", "home", "errand", "Deep Focus", "deep focus"]
  static let memoryKeys = ["alpha", "bravo", "charlie"]
  static let words = ["amber", "birch", "cedar", "dune", "ember", "fjord", "glade"]

  init(seed: UInt64, transport: Transport) throws {
    self.seed = seed
    self.transport = transport
    var generator = SplitMix64(seed: seed)
    let count = 2 + Int(generator.next() % 2)
    self.replicas = try (0..<count).map { try Replica(name: "R\($0)") }
    self.cursors = Array(repeating: 0, count: count)
    self.coalescing = seed % 2 == 0
    self.rng = generator
    for from in 0..<count {
      for to in 0..<count where from != to {
        channels.append(Channel(from: from, to: to))
      }
    }
    let identities = replicas.map { replica in
      (try? replica.service.writeState().deviceId) ?? "unavailable"
    }
    if Set(identities).count != identities.count {
      unexpected.append("replicas share a device identity: \(identities)")
    }
    notes.append("device ids: " + identities.joined(separator: ", "))
  }

  // MARK: Randomness

  func below(_ bound: Int) -> Int { Int(rng.next() % UInt64(bound)) }

  func chance(_ percent: Int) -> Bool { below(100) < percent }

  func pick<T>(_ items: [T]) -> T? { items.isEmpty ? nil : items[below(items.count)] }

  func word() -> String { Self.words[below(Self.words.count)] }

  func day(_ offset: Int) -> Date {
    let text = "2026-06-" + String(format: "%02d", 1 + offset)
    return LorvexDateFormatters.ymdUTC.date(from: text) ?? Date(timeIntervalSince1970: 0)
  }

  func ids(_ replica: Replica, _ sql: String) -> [String] {
    (try? replica.service.read { db in try String.fetchAll(db, sql: sql) }) ?? []
  }

  // MARK: Driver

  func execute(steps: Int) async -> [String] {
    for step in 0..<steps {
      if chance(72) {
        await localOperation()
      } else {
        deliverSome(step: step)
      }
    }
    quiesce()
    return verdict()
  }

  private struct SnapshotLine {
    let entityType: String
    let entityId: String
    let operation: String
    let version: String
    let raw: String

    init?(_ raw: String) {
      let parts = raw.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
      guard parts.count == 5 else { return nil }
      self.raw = raw
      entityType = String(parts[0])
      entityId = String(parts[1])
      operation = String(parts[2])
      version = String(parts[3])
    }

    var key: String { entityType + "|" + entityId }
  }

  func verdict() -> [String] {
    var problems = unexpected
    var snapshots: [[SnapshotLine]] = []
    for index in replicas.indices {
      do {
        snapshots.append(try snapshot(index).sorted().compactMap(SnapshotLine.init))
      } catch {
        problems.append("snapshot \(replicas[index].name) failed: \(error)")
        snapshots.append([])
      }
    }
    var tracedEntities: [String] = []
    for index in snapshots.indices.dropFirst() {
      let a = replicas[0].name
      let b = replicas[index].name
      let live0 = Set(snapshots[0].filter { $0.operation == "upsert" }.map(\.raw))
      let liveN = Set(snapshots[index].filter { $0.operation == "upsert" }.map(\.raw))
      if live0 != liveN {
        let onlyA = live0.subtracting(liveN).sorted()
        let onlyB = liveN.subtracting(live0).sorted()
        problems.append(
          "LIVE state of \(a) and \(b) diverges:\n"
            + onlyA.prefix(6).map { "  only \(a): \($0)" }.joined(separator: "\n") + "\n"
            + onlyB.prefix(6).map { "  only \(b): \($0)" }.joined(separator: "\n"))
        for raw in (onlyA.prefix(2) + onlyB.prefix(2)) {
          if let line = SnapshotLine(raw) {
            tracedEntities.append(contentsOf: line.entityId.split(separator: ":").map(String.init))
          }
        }
      }
      let dead0 = Dictionary(
        snapshots[0].filter { $0.operation == "delete" }.map { ($0.key, $0.version) },
        uniquingKeysWith: { first, _ in first })
      let deadN = Dictionary(
        snapshots[index].filter { $0.operation == "delete" }.map { ($0.key, $0.version) },
        uniquingKeysWith: { first, _ in first })
      let mismatched = dead0.keys.filter { deadN[$0] != nil && deadN[$0] != dead0[$0] }
      if !mismatched.isEmpty {
        notes.append(
          "\(a)/\(b): \(mismatched.count) tombstones carry different death versions ("
            + Dictionary(grouping: mismatched, by: { String($0.split(separator: "|")[0]) })
            .map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ") + ")")
      }
      let onlyOneSide = Set(dead0.keys).symmetricDifference(Set(deadN.keys))
      if !onlyOneSide.isEmpty {
        notes.append(
          "\(a)/\(b): \(onlyOneSide.count) tombstones held by one side only ("
            + Dictionary(grouping: onlyOneSide, by: { String($0.split(separator: "|")[0]) })
            .map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ") + ")")
      }
    }
    for replica in replicas {
      let pending =
        (try? replica.service.read { db in
          try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_pending_inbox") ?? 0
        }) ?? -1
      if pending != 0 {
        problems.append("\(replica.name) still holds \(pending) pending inbound entries")
      }
      let violations =
        (try? replica.service.read { db in
          try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
        }) ?? -1
      if violations != 0 {
        problems.append("\(replica.name) has \(violations) foreign-key violations")
      }
    }
    if !problems.isEmpty {
      var seen = Set<String>()
      for entity in tracedEntities where seen.insert(entity).inserted && seen.count <= 5 {
        problems.append(
          "trace of \(entity):\n"
            + trace.filter { $0.contains(entity) }.suffix(40).map { "  " + $0 }
            .joined(separator: "\n") + "\n" + localFacts(about: entity))
      }
      problems.append(
        "transport=\(transport.rawValue) coalescing=\(coalescing) replicas=\(replicas.count)\n"
          + notes.joined(separator: "\n") + "\nlast operations:\n"
          + log.suffix(25).joined(separator: "\n"))
    }
    return problems
  }

  // MARK: Transport

  /// Keeps only the newest envelope per entity in a queue, the way a record slot
  /// does. Returns `false` when the queue already holds an equal or newer one.
  static func supersede(_ envelope: SyncEnvelope, in queue: inout [SyncEnvelope]) -> Bool {
    guard
      let existing = queue.firstIndex(where: {
        $0.entityType == envelope.entityType && $0.entityId == envelope.entityId
      })
    else { return true }
    if queue[existing].version < envelope.version { queue[existing] = envelope }
    return false
  }

  /// Hands envelopes a replica emitted to the transport.
  func publish(_ envelopes: [SyncEnvelope], from index: Int) {
    switch transport {
    case .chaos:
      for channel in channels.indices where channels[channel].from == index {
        for envelope in envelopes {
          if coalescing, !Self.supersede(envelope, in: &channels[channel].queue) { continue }
          channels[channel].queue.append(envelope)
        }
      }
    case .log:
      for envelope in envelopes {
        if coalescing,
          let existing = serverLog.firstIndex(where: {
            $0.flight.envelope.entityType == envelope.entityType
              && $0.flight.envelope.entityId == envelope.entityId
          })
        {
          if serverLog[existing].flight.envelope.version >= envelope.version { continue }
          serverLog.remove(at: existing)
        }
        serverLog.append(
          LogEntry(sequence: nextSequence, flight: InFlight(envelope: envelope, source: index)))
        nextSequence += 1
      }
    }
  }

  /// Drains a replica's outbox into the transport. Returns how many envelopes
  /// left the replica.
  @discardableResult
  func harvest(_ index: Int) -> Int {
    let replica = replicas[index]
    var drained: [SyncEnvelope] = []
    do {
      for _ in 0..<200 {
        let page = try replica.service.pendingOutbound()
        if page.isEmpty { break }
        drained += page.map(\.envelope)
        for pending in page { trace.append("\(replica.name) emits \(summary(pending.envelope))") }
        try replica.service.markOutboundSynced(outboxIds: page.map(\.outboxId))
      }
    } catch {
      unexpected.append("harvest \(replica.name) failed: \(error)")
    }
    publish(drained, from: index)
    return drained.count
  }

  func apply(_ batch: [InFlight], to index: Int) {
    var remaining = batch[...]
    while !remaining.isEmpty {
      let size = min(remaining.count, 1 + below(8))
      let chunk = Array(remaining.prefix(size))
      remaining = remaining.dropFirst(size)
      do {
        let report = try replicas[index].service.applyInbound(chunk.map(\.envelope), undecodable: 0)
        for flight in chunk {
          trace.append(
            "\(replicas[index].name) applies \(summary(flight.envelope)) from "
              + "\(replicas[flight.source].name) [chunk applied=\(report.applied)"
              + " skipped=\(report.skipped) deferred=\(report.deferred)"
              + " remapped=\(report.remapped) drained=\(report.drainReplayed)]")
        }
        if report.undecodable != 0 {
          unexpected.append("\(replicas[index].name) reported undecodable envelopes")
        }
      } catch {
        unexpected.append("applyInbound to \(replicas[index].name) failed: \(error)")
      }
    }
  }

  /// A random replica reads a page of the server log forward from its cursor
  /// (`log`), or a random slice of one channel is delivered in random order, with
  /// some envelopes left in flight to arrive again (`chaos`).
  func deliverSome(step: Int) {
    for index in replicas.indices where chance(60) { harvest(index) }
    switch transport {
    case .log:
      guard let index = pick(Array(replicas.indices)) else { return }
      if chance(10) { cursors[index] = max(0, cursors[index] - (1 + below(12))) }
      let batch = Array(unread(by: index).prefix(1 + below(40)))
      guard let last = batch.last else { return }
      cursors[index] = last.sequence
      log.append("step \(step): \(replicas[index].name) reads \(batch.count) from the log")
      apply(batch.map(\.flight), to: index)
    case .chaos:
      guard let channel = pick(Array(channels.indices)) else { return }
      let available = channels[channel].queue.count
      guard available > 0 else { return }
      let take = 1 + below(available)
      var batch: [SyncEnvelope] = []
      for _ in 0..<take {
        batch.append(channels[channel].queue.remove(at: below(channels[channel].queue.count)))
      }
      for envelope in batch where chance(10) { channels[channel].queue.append(envelope) }
      log.append(
        "step \(step): deliver \(batch.count) \(replicas[channels[channel].from].name)>"
          + "\(replicas[channels[channel].to].name)")
      apply(
        batch.map { InFlight(envelope: $0, source: channels[channel].from) },
        to: channels[channel].to)
    }
  }

  /// The log entries a replica has not read yet, oldest first, without its own.
  func unread(by index: Int) -> [LogEntry] {
    serverLog.filter { $0.sequence > cursors[index] && $0.flight.source != index }
  }

  func quiesce() {
    for round in 0..<60 {
      var moved = 0
      for index in replicas.indices { moved += harvest(index) }
      switch transport {
      case .log:
        for index in replicas.indices.shuffled(using: &rng) {
          let batch = unread(by: index)
          cursors[index] = serverLog.last?.sequence ?? cursors[index]
          if batch.isEmpty { continue }
          moved += batch.count
          apply(batch.map(\.flight), to: index)
        }
      case .chaos:
        for channel in channels.indices.shuffled(using: &rng) {
          let batch = channels[channel].queue.shuffled(using: &rng)
          channels[channel].queue.removeAll()
          if batch.isEmpty { continue }
          moved += batch.count
          apply(
            batch.map { InFlight(envelope: $0, source: channels[channel].from) },
            to: channels[channel].to)
        }
      }
      if moved == 0 { return }
      if round == 59 { unexpected.append("replicas did not quiesce within 60 rounds") }
    }
  }

  /// Each replica's tombstone, conflict-log, edge, tag, and redirect rows that
  /// mention one entity id.
  func localFacts(about entity: String) -> String {
    let queries: [(String, String)] = [
      (
        "tombstone",
        "SELECT entity_type || ' ' || entity_id || ' ' || version FROM sync_tombstones WHERE instr(entity_id, ?1) > 0"
      ),
      (
        "conflict",
        "SELECT resolution_type || ' ' || entity_id || ' winner=' || winner_version || ' loser=' || loser_version FROM sync_conflict_log WHERE instr(entity_id, ?1) > 0 ORDER BY id"
      ),
      (
        "edge",
        "SELECT task_id || ':' || tag_id || ' ' || version FROM task_tags WHERE task_id = ?1 OR tag_id = ?1"
      ),
      (
        "tag", "SELECT id || ' ' || display_name || ' ' || lookup_key || ' ' || version FROM tags WHERE id = ?1"
      ),
      (
        "redirect",
        "SELECT source_type || ' ' || source_id || '>' || target_id || ' ' || version FROM sync_entity_redirects WHERE source_id = ?1 OR target_id = ?1"
      ),
    ]
    var lines: [String] = []
    for replica in replicas {
      var parts: [String] = []
      for (label, sql) in queries {
        let rows: [String] =
          (try? replica.service.read { db in
            try String.fetchAll(db, sql: sql, arguments: [entity])
          }) ?? ["unreadable"]
        for row in rows { parts.append("\(label) \(row)") }
      }
      lines.append("  \(replica.name): " + (parts.isEmpty ? "-" : parts.joined(separator: "; ")))
    }
    return lines.joined(separator: "\n")
  }

  func summary(_ e: SyncEnvelope) -> String {
    "\(e.entityType)|\(e.entityId)|\(e.operation)|\(e.version)"
  }

  func snapshot(_ index: Int) throws -> Set<String> {
    let service = replicas[index].service
    _ = try service.enqueueFullResyncBackfill()
    var lines = Set<String>()
    for _ in 0..<400 {
      let page = try service.pendingOutbound()
      if page.isEmpty { break }
      for pending in page {
        let e = pending.envelope
        lines.insert("\(e.entityType)|\(e.entityId)|\(e.operation)|\(e.version)|\(e.payload)")
      }
      try service.markOutboundSynced(outboxIds: page.map(\.outboxId))
    }
    return lines
  }

  // MARK: Operations

  func record(_ replica: Replica, _ text: String) {
    log.append("\(replica.name): \(text)")
  }

  func attempt(_ replica: Replica, _ description: String, _ body: () async throws -> Void) async {
    do {
      try await body()
      record(replica, description)
    } catch let error as LorvexCoreError {
      switch error {
      case .taskNotFound, .emptyTitle, .notFound, .validation, .conflict:
        record(replica, description + " (rejected)")
      case .unsupportedOperation(let message) where message.hasPrefix("Cannot "):
        record(replica, description + " (rejected)")
      default:
        unexpected.append("\(replica.name) \(description): \(type(of: error)) \(error)")
      }
    } catch {
      let text = "\(error)"
      if text.contains("endpoint missing, archived, or cancelled")
        || text.contains("Circular dependency detected")
        || "\(type(of: error))".hasSuffix("LifecycleError")
      {
        record(replica, description + " (rejected)")
      } else {
        unexpected.append("\(replica.name) \(description): \(type(of: error)) \(error)")
      }
    }
  }

  func localOperation() async {
    let replica = replicas[below(replicas.count)]
    switch below(100) {
    case 0..<14: await createTask(replica)
    case 14..<30: await updateTask(replica)
    case 30..<40: await lifecycle(replica)
    case 40..<46: await moveTask(replica)
    case 46..<50: await trash(replica)
    case 50..<56: await checklist(replica)
    case 56..<62: await listOperation(replica)
    case 62..<70: await tagOperation(replica)
    case 70..<78: await memoryOperation(replica)
    default: await habitOperation(replica)
    }
  }

  func taskIDs(_ replica: Replica, where clause: String = "1") -> [String] {
    ids(replica, "SELECT id FROM tasks WHERE \(clause) ORDER BY title, id")
  }

  func createTask(_ replica: Replica) async {
    counter += 1
    let title = "t\(counter) \(word())"
    let lists = ids(replica, "SELECT id FROM lists WHERE archived_at IS NULL ORDER BY name, id")
    var draft = TaskCreateDraft(
      title: title, notes: chance(40) ? "note \(counter)" : "", listID: pick(lists))
    draft.priority = [.p1, .p2, .p3][below(3)]
    if chance(40) { draft.dueDate = day(below(20)) }
    if chance(30) { draft.estimatedMinutes = 5 * (1 + below(24)) }
    if chance(40) { draft.tags = randomTags() }
    await attempt(replica, "create \(title)") { _ = try await replica.service.createTask(draft) }
  }

  func randomTags() -> [String] {
    var tags: [String] = []
    for _ in 0..<(1 + below(2)) { tags.append(Self.tagPool[below(Self.tagPool.count)]) }
    return tags
  }

  func updateTask(_ replica: Replica) async {
    let tasks = taskIDs(replica)
    guard let id = pick(tasks) else { return }
    var draft = TaskUpdateDraft(id: id)
    var parts: [String] = []
    if chance(30) { counter += 1; draft.title = "u\(counter) \(word())"; parts.append("title") }
    if chance(25) { draft.notes = chance(20) ? "" : "edit \(word())"; parts.append("notes") }
    if chance(25) { draft.priority = [.p1, .p2, .p3][below(3)]; parts.append("priority") }
    if chance(25) {
      draft.dueDate = chance(25) ? .clear : .set(day(below(20)))
      parts.append("due")
    }
    if chance(20) {
      draft.estimatedMinutes = chance(25) ? .clear : .set(5 * (1 + below(24)))
      parts.append("estimate")
    }
    if chance(15) {
      draft.plannedDate = chance(25) ? .clear : .set(day(below(20)))
      parts.append("planned")
    }
    if chance(25) { draft.tags = chance(20) ? [] : randomTags(); parts.append("tags") }
    if chance(12) {
      draft.dependsOn = Array(taskIDs(replica).filter { $0 != id }.shuffled(using: &rng).prefix(2))
      parts.append("dependsOn")
    }
    if parts.isEmpty { return }
    await attempt(replica, "update \(id.prefix(8)) \(parts.joined(separator: ","))") {
      _ = try await replica.service.updateTask(draft)
    }
  }

  func lifecycle(_ replica: Replica) async {
    guard let id = pick(taskIDs(replica)) else { return }
    let service = replica.service
    switch below(7) {
    case 0:
      await attempt(replica, "complete \(id.prefix(8))") {
        _ = try await service.completeTaskReturningTask(id: id)
      }
    case 1:
      await attempt(replica, "reopen \(id.prefix(8))") {
        _ = try await service.reopenTaskReturningTask(id: id)
      }
    case 2:
      await attempt(replica, "cancel \(id.prefix(8))") {
        _ = try await service.cancelTaskReturningTask(id: id)
      }
    case 3:
      await attempt(replica, "start \(id.prefix(8))") {
        _ = try await service.startTaskReturningTask(id: id)
      }
    case 4:
      await attempt(replica, "pause \(id.prefix(8))") {
        _ = try await service.pauseTaskReturningTask(id: id)
      }
    case 5:
      await attempt(replica, "someday \(id.prefix(8))") {
        _ = try await service.markTaskSomeday(id: id)
      }
    default:
      let until = day(below(20))
      await attempt(replica, "defer \(id.prefix(8))") {
        _ = try await service.deferTaskReturningTask(id: id, until: until, reason: nil, note: nil)
      }
    }
  }

  func moveTask(_ replica: Replica) async {
    guard let id = pick(taskIDs(replica)),
      let list = pick(ids(replica, "SELECT id FROM lists ORDER BY name, id"))
    else { return }
    await attempt(replica, "move \(id.prefix(8)) to \(list.prefix(8))") {
      _ = try await replica.service.moveTask(id: id, toListID: list)
    }
  }

  func trash(_ replica: Replica) async {
    let service = replica.service
    switch below(3) {
    case 0:
      guard let id = pick(taskIDs(replica, where: "archived_at IS NULL")) else { return }
      await attempt(replica, "archive \(id.prefix(8))") { _ = try await service.archiveTask(id: id) }
    case 1:
      guard let id = pick(taskIDs(replica, where: "archived_at IS NOT NULL")) else { return }
      await attempt(replica, "unarchive \(id.prefix(8))") {
        _ = try await service.unarchiveTask(id: id)
      }
    default:
      guard let id = pick(taskIDs(replica)) else { return }
      await attempt(replica, "delete \(id.prefix(8))") {
        try await service.permanentlyDeleteTask(id: id)
      }
    }
  }

  func checklist(_ replica: Replica) async {
    let service = replica.service
    let items = ids(replica, "SELECT id FROM task_checklist_items ORDER BY text, id")
    switch below(3) {
    case 0:
      guard let task = pick(taskIDs(replica)) else { return }
      counter += 1
      let text = "c\(counter)"
      await attempt(replica, "checklist add \(text)") {
        _ = try await service.addTaskChecklistItem(taskID: task, text: text)
      }
    case 1:
      guard let item = pick(items) else { return }
      let completed = chance(50)
      await attempt(replica, "checklist toggle \(item.prefix(8)) \(completed)") {
        try await service.toggleTaskChecklistItem(itemID: item, completed: completed)
      }
    default:
      guard let item = pick(items) else { return }
      await attempt(replica, "checklist remove \(item.prefix(8))") {
        _ = try await service.removeTaskChecklistItem(itemID: item)
      }
    }
  }

  func listOperation(_ replica: Replica) async {
    let service = replica.service
    switch below(5) {
    case 0:
      counter += 1
      let name = "L\(counter)"
      await attempt(replica, "create list \(name)") {
        _ = try await service.createList(name: name, description: nil)
      }
    case 1:
      guard let id = pick(ids(replica, "SELECT id FROM lists ORDER BY name, id")) else { return }
      counter += 1
      let name = "L\(counter) renamed"
      await attempt(replica, "rename list \(id.prefix(8))") {
        _ = try await service.updateList(
          id: id, name: name, description: .unset, color: nil, icon: nil)
      }
    case 2:
      guard let id = pick(ids(replica, "SELECT id FROM lists WHERE archived_at IS NULL AND id != 'inbox' ORDER BY name, id"))
      else { return }
      await attempt(replica, "archive list \(id.prefix(8))") { _ = try await service.archiveList(id: id) }
    case 3:
      guard let id = pick(ids(replica, "SELECT id FROM lists WHERE archived_at IS NOT NULL ORDER BY name, id"))
      else { return }
      await attempt(replica, "unarchive list \(id.prefix(8))") {
        _ = try await service.unarchiveList(id: id)
      }
    default:
      guard let id = pick(ids(replica, "SELECT id FROM lists WHERE id != 'inbox' ORDER BY name, id"))
      else { return }
      await attempt(replica, "delete list \(id.prefix(8))") { try await service.deleteList(id: id) }
    }
  }

  func tagOperation(_ replica: Replica) async {
    let service = replica.service
    let names = ids(replica, "SELECT display_name FROM tags ORDER BY display_name, id")
    switch below(3) {
    case 0:
      guard let old = pick(names) else { return }
      let new = Self.tagPool[below(Self.tagPool.count)]
      await attempt(replica, "rename tag \(old) to \(new)") {
        try await service.renameTag(oldTag: old, newTag: new)
      }
    case 1:
      guard let source = pick(names), let target = pick(names) else { return }
      await attempt(replica, "merge tag \(source) into \(target)") {
        _ = try await service.mergeTags(source: source, target: target)
      }
    default:
      guard let name = pick(names) else { return }
      await attempt(replica, "delete tag \(name)") { _ = try await service.deleteTag(name: name) }
    }
  }

  func memoryOperation(_ replica: Replica) async {
    let service = replica.service
    switch below(4) {
    case 0, 1:
      let key = Self.memoryKeys[below(Self.memoryKeys.count)]
      counter += 1
      let content = "body \(counter)"
      await attempt(replica, "memory upsert \(key)") {
        _ = try await service.upsertMemory(key: key, content: content)
      }
    case 2:
      guard let old = pick(ids(replica, "SELECT key FROM memories ORDER BY key")) else { return }
      let new = Self.memoryKeys[below(Self.memoryKeys.count)]
      await attempt(replica, "memory rename \(old) to \(new)") {
        _ = try await service.renameMemory(oldKey: old, newKey: new, content: nil)
      }
    default:
      guard let key = pick(ids(replica, "SELECT key FROM memories ORDER BY key")) else { return }
      await attempt(replica, "memory delete \(key)") { _ = try await service.deleteMemory(key: key) }
    }
  }

  func habitOperation(_ replica: Replica) async {
    let service = replica.service
    let habits = ids(replica, "SELECT id FROM habits ORDER BY name, id")
    let date = "2026-06-" + String(format: "%02d", 1 + below(10))
    switch below(6) {
    case 0:
      counter += 1
      let name = "H\(counter)"
      await attempt(replica, "create habit \(name)") {
        _ = try await service.createHabit(name: name, cue: nil, targetCount: 1 + below(3))
      }
    case 1:
      guard let id = pick(habits) else { return }
      counter += 1
      let name = "H\(counter) renamed"
      let archived = chance(30)
      await attempt(replica, "update habit \(id.prefix(8))") {
        _ = try await service.updateHabit(
          id: id, name: name, cue: .unset, color: nil, icon: nil, targetCount: nil,
          archived: archived, cadence: nil, milestoneTarget: .unset)
      }
    case 2, 3:
      guard let id = pick(habits) else { return }
      await attempt(replica, "complete habit \(id.prefix(8)) \(date)") {
        _ = try await service.completeHabit(id: id, date: date)
      }
    case 4:
      guard let id = pick(habits) else { return }
      await attempt(replica, "uncomplete habit \(id.prefix(8)) \(date)") {
        _ = try await service.uncompleteHabit(id: id, date: date)
      }
    default:
      guard let id = pick(habits) else { return }
      await attempt(replica, "delete habit \(id.prefix(8))") {
        _ = try await service.deleteHabit(id: id)
      }
    }
  }
}
