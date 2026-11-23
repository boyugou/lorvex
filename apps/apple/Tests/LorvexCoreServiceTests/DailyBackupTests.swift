import Foundation
import LorvexDomain
import LorvexRuntime
import XCTest

@testable import LorvexCore

/// The daily backups a device keeps: the keep rule, the writer's outcomes on
/// an on-disk store, turning backups off, and an erase that lands while a
/// backup is being prepared.
final class DailyBackupTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lorvex-daily-backup-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  // MARK: - Keep rule

  func testKeepsTheNewestSevenAndTheEarliestOfEachOfFourWeeksBefore() {
    // Thirty consecutive days, Saturday 2026-10-31 to Sunday 2026-11-29.
    // 2026-11-23 is a Monday; weeks run Monday to Sunday.
    let days = (0..<30).compactMap { LorvexDateFormatters.ymdUTCAddingDays("2026-10-31", days: $0) }
    XCTAssertEqual(days.count, 30)
    XCTAssertEqual(
      LorvexDailyBackups.daysToKeep(days),
      [
        // The newest seven.
        "2026-11-23", "2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27", "2026-11-28",
        "2026-11-29",
        // The earliest present day of each of the four weeks before them.
        "2026-11-16", "2026-11-09", "2026-11-02", "2026-10-31",
      ])
  }

  /// Pruning day after day keeps exactly what the rule keeps over every day
  /// ever written, so no pass removes a backup a later pass would have kept,
  /// whether the app runs every day or skips days.
  func testPruningDayByDayNeverRemovesWhatALaterPassKeeps() {
    for stride in [1, 2, 3] {
      var kept: [String] = []
      var everWritten: [String] = []
      for offset in Swift.stride(from: 0, to: 120, by: stride) {
        guard let day = LorvexDateFormatters.ymdUTCAddingDays("2026-08-01", days: offset) else {
          return XCTFail("day arithmetic")
        }
        everWritten.append(day)
        kept = Array(LorvexDailyBackups.daysToKeep(kept + [day]))
        XCTAssertEqual(
          Set(kept), LorvexDailyBackups.daysToKeep(everWritten), "stride \(stride), \(day)")
      }
    }
  }

  func testOnlyBackupFileNamesCount() {
    XCTAssertEqual(LorvexDailyBackups.fileName(forDay: "2026-11-23"), "lorvex-backup-2026-11-23.zip")
    XCTAssertEqual(LorvexDailyBackups.day(fromFileName: "lorvex-backup-2026-11-23.zip"), "2026-11-23")
    XCTAssertNil(LorvexDailyBackups.day(fromFileName: "lorvex-backup-2026-02-30.zip"))
    XCTAssertNil(LorvexDailyBackups.day(fromFileName: "lorvex-export.zip"))
    XCTAssertNil(LorvexDailyBackups.day(fromFileName: "lorvex-backup-2026-11-23.zip.tmp"))
    XCTAssertEqual(LorvexDailyBackups.daysToKeep(["not a day", "2026-11-23"]), ["2026-11-23"])
  }

  // MARK: - Writer

  func testEmptyStoreWritesNothingAndATaskMakesTheFirstBackup() async throws {
    let core = try makeCore()
    let empty = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: "1.0.0", now: Date())
    XCTAssertEqual(empty, .emptyStore)
    XCTAssertEqual(try core.dailyBackups(), [])

    _ = try await core.createTask(title: "Keep me", notes: "a note")
    let first = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: "1.0.0", now: Date())
    guard case .written(let backup) = first else { return XCTFail("\(first)") }
    XCTAssertEqual(backup.url.lastPathComponent, "lorvex-backup-2026-11-23.zip")
    XCTAssertEqual(try core.dailyBackups().map(\.day), ["2026-11-23"])
    XCTAssertGreaterThan(try core.dailyBackups().first?.byteCount ?? 0, 0)

    let payload = try core.dailyBackupPayload(day: "2026-11-23")
    XCTAssertEqual(payload.tasks?.map(\.title), ["Keep me"])
    XCTAssertNotNil(payload.nativeTaskGraph, "a backup is the complete ZIP export")

    let again = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: "1.0.0", now: Date())
    XCTAssertEqual(again, .alreadyPresent)

    let folder = LorvexDailyBackups.directory(forDatabasePath: databasePath)
    XCTAssertEqual(
      try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
  }

  func testAWrittenBackupPrunesOlderOnesByTheKeepRule() async throws {
    let core = try makeCore()
    _ = try await core.createTask(title: "Keep me", notes: "")
    guard case .written(let seed) = try await core.writeDailyBackupIfDue(
      day: "2026-10-01", appVersion: nil, now: Date())
    else { return XCTFail("seed backup") }
    let folder = seed.url.deletingLastPathComponent()
    let following = (1..<60).compactMap {
      LorvexDateFormatters.ymdUTCAddingDays("2026-10-01", days: $0)
    }
    for day in following {
      try FileManager.default.copyItem(
        at: seed.url,
        to: folder.appendingPathComponent(LorvexDailyBackups.fileName(forDay: day)))
    }
    _ = try await core.writeDailyBackupIfDue(day: "2026-12-01", appVersion: nil, now: Date())
    let present = Set(try core.dailyBackups().map(\.day))
    XCTAssertEqual(present, LorvexDailyBackups.daysToKeep(["2026-10-01"] + following + ["2026-12-01"]))
    XCTAssertEqual(present.count, 11)
    XCTAssertTrue(present.contains("2026-12-01"))
  }

  func testTurningBackupsOffDeletesThemAndStopsNewOnes() async throws {
    let core = try makeCore()
    _ = try await core.createTask(title: "Keep me", notes: "")
    _ = try await core.writeDailyBackupIfDue(day: "2026-11-22", appVersion: nil, now: Date())
    XCTAssertEqual(try core.dailyBackups().count, 1)
    let enabledByDefault = try await core.dailyBackupsEnabled()
    XCTAssertTrue(enabledByDefault)

    try await core.setDailyBackupsEnabled(false)
    XCTAssertEqual(try core.dailyBackups(), [])
    let off = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: nil, now: Date())
    XCTAssertEqual(off, .disabled)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: LorvexDailyBackups.directory(forDatabasePath: databasePath).path))

    try await core.setDailyBackupsEnabled(true)
    let on = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: nil, now: Date())
    guard case .written = on else { return XCTFail("\(on)") }
  }

  func testEraseRemovesTheBackups() async throws {
    let core = try makeCore()
    _ = try await core.createTask(title: "Keep me", notes: "")
    _ = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: nil, now: Date())
    let folder = LorvexDailyBackups.directory(forDatabasePath: databasePath)
    XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

    core.closeStoreForCutover()
    try SwiftLorvexCoreService.resetManagedStorage(at: URL(fileURLWithPath: databasePath))
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
  }

  /// An erase that lands after the export and before the publish bumps the
  /// storage generation; the prepared backup is discarded, so the erased data
  /// never reappears as a backup.
  func testABackupPreparedBeforeAnEraseIsDiscarded() async throws {
    let core = try makeCore()
    _ = try await core.createTask(title: "Erase me", notes: "")
    let path = databasePath
    let outcome = try await SwiftLorvexCoreService.$beforeDailyBackupPublishForTesting.withValue({
      core.closeStoreForCutover()
      _ = try? SwiftLorvexCoreService.resetManagedStorage(at: URL(fileURLWithPath: path))
    }) {
      try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: nil, now: Date())
    }
    XCTAssertEqual(outcome, .superseded)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: LorvexDailyBackups.directory(forDatabasePath: path).path))
  }

  /// A backup left on disk while the switch is off (a failed delete, or a
  /// pass that raced the switch) is removed by the next pass.
  func testAPassWhileOffRemovesBackupsLeftBehind() async throws {
    let core = try makeCore()
    _ = try await core.createTask(title: "Keep me", notes: "")
    _ = try await core.writeDailyBackupIfDue(day: "2026-11-22", appVersion: nil, now: Date())
    _ = try await core.setPreference(key: PreferenceKeys.prefDailyBackups, value: "false")
    XCTAssertEqual(try core.dailyBackups().count, 1, "the preference alone deletes nothing")

    let outcome = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: nil, now: Date())
    XCTAssertEqual(outcome, .disabled)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: LorvexDailyBackups.directory(forDatabasePath: databasePath).path))
  }

  /// A file a pass left unfinished goes at the next pass; a backup dated more
  /// than two days after today (a clock set ahead) goes when today's is
  /// written, and one dated a day ahead stays.
  func testUnfinishedAndFarFutureFilesAreRemoved() async throws {
    let core = try makeCore()
    _ = try await core.createTask(title: "Keep me", notes: "")
    guard case .written(let seed) = try await core.writeDailyBackupIfDue(
      day: "2026-11-20", appVersion: nil, now: Date())
    else { return XCTFail("seed backup") }
    XCTAssertNotNil(seed.takenAt)
    XCTAssertNotNil(try core.dailyBackups().first?.takenAt)
    let folder = seed.url.deletingLastPathComponent()
    let unfinished = folder.appendingPathComponent(
      LorvexDailyBackups.unfinishedFileName(forDay: "2026-11-21"))
    try Data("partial".utf8).write(to: unfinished)
    for day in ["2026-11-24", "2027-01-01"] {
      try FileManager.default.copyItem(
        at: seed.url, to: folder.appendingPathComponent(LorvexDailyBackups.fileName(forDay: day)))
    }

    _ = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: nil, now: Date())
    XCTAssertFalse(FileManager.default.fileExists(atPath: unfinished.path))
    XCTAssertEqual(try core.dailyBackups().map(\.day), ["2026-11-24", "2026-11-23", "2026-11-20"])
  }

  func testAnInMemoryCoreKeepsNoBackups() async throws {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.createTask(title: "Preview", notes: "")
    let outcome = try await core.writeDailyBackupIfDue(day: "2026-11-23", appVersion: nil, now: Date())
    XCTAssertEqual(outcome, .unavailable)
    XCTAssertEqual(try core.dailyBackups(), [])
  }

  func testAFailedPassWaitsBeforeTheNextAndIsLogged() async throws {
    let scheduler = LorvexDailyBackupScheduler()
    let core = try makeCore()
    _ = try await core.createTask(title: "Keep me", notes: "")
    let start = Date()
    let written = await scheduler.runIfDue(core: core, day: "2026-11-23", appVersion: nil, now: start)
    guard case .written = written else { return XCTFail("\(String(describing: written))") }

    // A file where the backup folder belongs makes the next publish throw.
    let folder = LorvexDailyBackups.directory(forDatabasePath: databasePath)
    try FileManager.default.removeItem(at: folder)
    try Data().write(to: folder)
    let failed = await scheduler.runIfDue(core: core, day: "2026-11-24", appVersion: nil, now: start)
    XCTAssertNil(failed)
    let soon = await scheduler.runIfDue(
      core: core, day: "2026-11-24", appVersion: nil, now: start.addingTimeInterval(60))
    XCTAssertNil(soon, "no second attempt inside the retry interval")

    let asked = await scheduler.runIfDue(
      core: core, day: "2026-11-24", appVersion: nil, now: start.addingTimeInterval(60),
      ignoringBackoff: true)
    XCTAssertNil(asked, "a pass the person asks for runs at once; this one still fails")
    let logs = try await core.loadRecentLogs(
      limit: 50, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: false)
    XCTAssertEqual(
      logs.entries.filter { $0.origin == "daily_backup" }.count, 2,
      "the first failure and the asked-for one; the pass held back by the wait logs nothing")

    // The asked-for failure starts the wait again.
    try FileManager.default.removeItem(at: folder)
    let later = await scheduler.runIfDue(
      core: core, day: "2026-11-24", appVersion: nil,
      now: start.addingTimeInterval(60 + LorvexDailyBackupScheduler.retryInterval + 1))
    guard case .written = later else { return XCTFail("\(String(describing: later))") }
  }

  // MARK: - Fixture

  private var databasePath: String { directory.appendingPathComponent("lorvex.sqlite").path }

  private func makeCore() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    return SwiftLorvexCoreService(
      databasePath: databasePath, schemaSQL: try String(contentsOf: schemaURL, encoding: .utf8))
  }
}
