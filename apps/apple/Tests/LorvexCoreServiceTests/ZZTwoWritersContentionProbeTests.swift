import Foundation
import GRDB
import XCTest

@testable import LorvexCore

// Persistent probe. On a Mac the app and the MCP host are two processes writing one SQLite file.
// This opens two services on one on-disk database, as the two processes do, and has them write
// at the same time: single updates, batch creates that hold the write lock longer, preferences,
// and reads. A write that has to wait for the other waits up to the store's busy timeout; none
// may fail with a busy or locked error, no write may be lost, and the file must stay intact.
//
// Run from apps/apple (the build must be current):
//   CONTENTION_RUN=1 CONTENTION_ROUNDS=60 swift test --skip-build -j 4 --filter ZZTwoWritersContentionProbe
// CONTENTION_SHARED=1 runs the same workload through one service, to tell contention from load.
// Skipped unless CONTENTION_RUN is set. Findings print as `CONTENTION` lines.

private final class Findings: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []
  func add(_ line: String) {
    lock.lock()
    lines.append(line)
    lock.unlock()
  }
  var all: [String] {
    lock.lock()
    defer { lock.unlock() }
    return lines
  }
}

final class ZZTwoWritersContentionProbeTests: XCTestCase {
  func testTwoConnectionsWritingOneDatabaseNeverFailAndLoseNothing() async throws {
    let environment = ProcessInfo.processInfo.environment
    try XCTSkipUnless(environment["CONTENTION_RUN"] != nil, "set CONTENTION_RUN=1 to run this probe")
    let rounds = Int(environment["CONTENTION_ROUNDS"] ?? "60") ?? 60

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lorvex-contention-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("db.sqlite").path

    let app = SwiftLorvexCoreService(databasePath: path)
    // CONTENTION_SHARED=1 gives both roles one service, as a baseline for the same workload.
    let host =
      environment["CONTENTION_SHARED"] != nil ? app : SwiftLorvexCoreService(databasePath: path)
    var appTasks: [String] = []
    var hostTasks: [String] = []
    for index in 0..<6 {
      appTasks.append(try await app.createTask(title: "app \(index)", notes: "").id)
      hostTasks.append(try await host.createTask(title: "host \(index)", notes: "").id)
    }

    let findings = Findings()
    let record: @Sendable (String, Int, Error) -> Void = { who, round, error in
      findings.add("\(who) round \(round): \(error)")
      print("CONTENTION \(who) round \(round): \(error)")
    }
    let appIDs = appTasks
    let hostIDs = hostTasks

    let started = Date()
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        for round in 0..<rounds {
          do {
            _ = try await app.updateTask(
              TaskUpdateDraft(id: appIDs[round % appIDs.count], title: "app edit \(round)"))
          } catch { record("app update", round, error) }
        }
      }
      group.addTask {
        for round in 0..<rounds {
          do {
            _ = try await host.updateTask(
              TaskUpdateDraft(id: hostIDs[round % hostIDs.count], notes: "host edit \(round)"))
          } catch { record("host update", round, error) }
        }
      }
      group.addTask {
        // A longer write: one transaction that creates many rows.
        for round in 0..<(rounds / 10) {
          do {
            let drafts = (0..<60).map { TaskCreateDraft(title: "batch \(round)-\($0)", notes: "x") }
            _ = try await host.batchCreateTasks(drafts)
          } catch { record("host batch", round, error) }
        }
      }
      group.addTask {
        for round in 0..<rounds {
          do {
            _ = try await app.setPreference(key: "default_list_id", value: "inbox")
            _ = try await app.loadToday()
          } catch { record("app preference/read", round, error) }
        }
      }
      group.addTask {
        for round in 0..<rounds {
          do {
            _ = try await host.getAllPreferences()
            _ = try await host.exportData(entities: ["tasks"], format: "json")
          } catch { record("host read", round, error) }
        }
      }
    }
    let seconds = Date().timeIntervalSince(started)

    // Nothing was lost: the last edit of each task is on disk, as the other connection sees it.
    for (index, id) in appTasks.enumerated() {
      let last = (0..<rounds).last { $0 % appTasks.count == index }.map { "app edit \($0)" }
      let stored = try await host.loadTask(id: id).title
      if let last, stored != last { findings.add("app task \(index): \(stored) != \(last)") }
    }
    for (index, id) in hostTasks.enumerated() {
      let last = (0..<rounds).last { $0 % hostTasks.count == index }.map { "host edit \($0)" }
      let stored = try await app.loadTask(id: id).notes
      if let last, stored != last { findings.add("host task \(index): \(stored) != \(last)") }
    }
    let integrity = try app.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
    if integrity != "ok" { findings.add("integrity_check: \(integrity ?? "nil")") }

    print("CONTENTION summary rounds=\(rounds) seconds=\(String(format: "%.1f", seconds)) findings=\(findings.all.count)")
    XCTAssertTrue(findings.all.isEmpty, findings.all.prefix(5).joined(separator: "\n"))
  }
}
