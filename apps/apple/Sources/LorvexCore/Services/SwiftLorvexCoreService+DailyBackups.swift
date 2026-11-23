import Foundation
import LorvexDomain
import LorvexRuntime

/// The daily backups a device keeps of its own data (``LorvexDailyBackups``).
/// The main app writes them; the MCP helper and Settings read them. A core
/// without an on-disk store (a preview or in-memory core) has none.
public protocol LorvexDailyBackupServicing: Sendable {
  /// Writes the backup for the logical `day` when this device keeps backups,
  /// none exists for `day`, and the store holds data, then removes the older
  /// backups the keep rule no longer holds. While backups are off, a pass
  /// removes any backup still on disk instead.
  ///
  /// The backup is the full export ZIP, read in one transaction and written to
  /// an unfinished file first. It is renamed into place only while the storage
  /// cutover lock is held shared and the storage generation still matches the
  /// one read before the export, so a backup prepared before an erase never
  /// appears after it. The preference is read again after publishing, and a
  /// backup that raced a switch to off is removed with the rest, so turning
  /// backups off leaves none behind.
  func writeDailyBackupIfDue(day: String, appVersion: String?, now: Date) async throws
    -> LorvexDailyBackupOutcome

  /// This device's backups, newest first.
  func dailyBackups() throws -> [LorvexDailyBackup]

  /// Whether this device keeps daily backups: the `daily_backups` preference,
  /// on unless it is `false`.
  func dailyBackupsEnabled() async throws -> Bool

  /// Turns daily backups on or off on this device. Turning them off deletes
  /// every backup already kept.
  func setDailyBackupsEnabled(_ enabled: Bool) async throws

  /// The data the backup taken on `day` holds.
  func dailyBackupPayload(day: String) throws -> LorvexDataExportPayload
}

extension SwiftLorvexCoreService: LorvexDailyBackupServicing {
  public func writeDailyBackupIfDue(day: String, appVersion: String?, now: Date) async throws
    -> LorvexDailyBackupOutcome
  {
    guard let databasePath = try onDiskDatabasePath() else { return .unavailable }
    let directory = LorvexDailyBackups.directory(forDatabasePath: databasePath)
    LorvexDailyBackups.removeUnfinishedWrites(in: directory)
    guard try await dailyBackupsEnabled() else {
      // Backups a pass left behind while the switch was turned off, or that
      // a failed delete kept, go now.
      try? FileManager.default.removeItem(at: directory)
      return .disabled
    }
    let target = directory.appendingPathComponent(
      LorvexDailyBackups.fileName(forDay: day), isDirectory: false)
    if FileManager.default.fileExists(atPath: target.path) { return .alreadyPresent }

    let generation = ManagedStorageGeneration.read(forDatabase: databasePath)
    let snapshot = try await loadSnapshotForDataExport(entities: [], includeNativeTaskGraph: true)
    guard Self.holdsDataWorthKeeping(snapshot.payload) else { return .emptyStore }
    let archive = try LorvexDataExporter.renderZip(
      payload: snapshot.payload,
      generatedAt: LorvexDateFormatters.iso8601.string(from: now),
      appVersion: appVersion)

    // The file is written before the lock is taken, so the lock is held only
    // for the generation check and a rename.
    try Self.prepareBackupDirectory(directory)
    let partial = directory.appendingPathComponent(
      LorvexDailyBackups.unfinishedFileName(forDay: day), isDirectory: false)
    try archive.write(to: partial)
    defer { try? FileManager.default.removeItem(at: partial) }
    Self.beforeDailyBackupPublishForTesting?()

    // The cutover lock is a `flock` in the App Group container, which a process
    // must not hold when iOS suspends it (`0xdead10cc`). Like every store
    // operation, the publish registers before checking for suspension, so a
    // suspension either waits for it or refuses it.
    DatabaseSuspension.operationWillBegin()
    defer { DatabaseSuspension.operationDidEnd() }
    if DatabaseSuspension.isSuspended { throw DatabaseSuspension.suspendedError }
    let published = try ManagedStorageGeneration.withSharedCutoverLock(
      forDatabase: databasePath
    ) { () throws -> Bool in
      guard ManagedStorageGeneration.read(forDatabase: databasePath) == generation else {
        return false
      }
      guard rename(partial.path, target.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      return true
    }
    guard published else {
      // An erase landed after the export. The folder this pass created after
      // it holds nothing once the unfinished file is gone.
      try? FileManager.default.removeItem(at: partial)
      if (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
        try? FileManager.default.removeItem(at: directory)
      }
      return .superseded
    }
    LorvexDailyBackups.prune(in: directory, today: day)
    guard try await dailyBackupsEnabled() else {
      try? FileManager.default.removeItem(at: directory)
      return .disabled
    }
    return .written(
      LorvexDailyBackup(day: day, url: target, byteCount: archive.count, takenAt: now))
  }

  public func dailyBackups() throws -> [LorvexDailyBackup] {
    guard let databasePath = try onDiskDatabasePath() else { return [] }
    return LorvexDailyBackups.list(
      in: LorvexDailyBackups.directory(forDatabasePath: databasePath))
  }

  public func dailyBackupsEnabled() async throws -> Bool {
    try await getPreference(key: PreferenceKeys.prefDailyBackups) != "false"
  }

  public func setDailyBackupsEnabled(_ enabled: Bool) async throws {
    _ = try await setPreference(
      key: PreferenceKeys.prefDailyBackups, value: enabled ? "true" : "false")
    guard !enabled, let databasePath = try onDiskDatabasePath() else { return }
    do {
      try FileManager.default.removeItem(
        at: LorvexDailyBackups.directory(forDatabasePath: databasePath))
    } catch CocoaError.fileNoSuchFile {
      // No backups were kept, or an erase removed them first.
    }
  }

  public func dailyBackupPayload(day: String) throws -> LorvexDataExportPayload {
    guard let backup = try dailyBackups().first(where: { $0.day == day }) else {
      throw LorvexCoreError.validation(
        field: "day", message: "This device has no daily backup from \(day).")
    }
    return try LorvexDataImporter.decode(Data(contentsOf: backup.url))
  }

  /// Test seam between a daily backup's export and its publish, where a test
  /// erases the store to prove the prepared backup is discarded. It is never
  /// bound in production.
  @TaskLocal static var beforeDailyBackupPublishForTesting: (@Sendable () -> Void)?

  /// The path of the opened database file, or `nil` for an in-memory store.
  private func onDiskDatabasePath() throws -> String? {
    let path = try store().writer.path
    guard !path.isEmpty, path != ":memory:", FileManager.default.fileExists(atPath: path)
    else { return nil }
    return path
  }

  /// A store with no tasks, habits, events, reviews, briefings, or memory has
  /// nothing a backup would bring back. Skipping it keeps an emptied store from
  /// pushing the last good backups out of the keep rule.
  static func holdsDataWorthKeeping(_ payload: LorvexDataExportPayload) -> Bool {
    !(payload.tasks ?? []).isEmpty || !(payload.habits ?? []).isEmpty
      || !(payload.calendarEvents ?? []).isEmpty || !(payload.dailyReviews ?? []).isEmpty
      || !(payload.dailyBriefings ?? []).isEmpty || !(payload.memory ?? []).isEmpty
  }

  /// Creates the backup folder and keeps it out of device backups (iCloud
  /// Backup, Time Machine): the database it copies is already there, and a
  /// second copy would only keep deleted items longer.
  private static func prepareBackupDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var excluded = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? excluded.setResourceValues(values)
  }
}

/// Runs ``LorvexDailyBackupServicing/writeDailyBackupIfDue(day:appVersion:now:)``
/// for the main app: one pass at a time, and after a failed pass none for
/// ``retryInterval``, so a store that cannot be exported is not exported again
/// on every refresh. A failure goes to the diagnostics log under
/// `daily_backup`. A pass refused because the app is being suspended
/// (``DatabaseSuspension``) is not a failure: the next refresh tries again. A
/// pass that finds today's backup present costs a preference read and two file
/// checks. A pass the person asked for (turning backups on) passes
/// `ignoringBackoff`.
public actor LorvexDailyBackupScheduler {
  public static let shared = LorvexDailyBackupScheduler()
  public static let retryInterval: TimeInterval = 30 * 60

  private var isRunning = false
  private var failedAt: Date?

  public init() {}

  @discardableResult
  public func runIfDue(
    core: any LorvexCoreServicing, day: String, appVersion: String?, now: Date = Date(),
    ignoringBackoff: Bool = false
  ) async -> LorvexDailyBackupOutcome? {
    guard let backups = core as? any LorvexDailyBackupServicing, !isRunning else { return nil }
    if !ignoringBackoff, let failedAt, now.timeIntervalSince(failedAt) < Self.retryInterval {
      return nil
    }
    isRunning = true
    defer { isRunning = false }
    do {
      let outcome = try await backups.writeDailyBackupIfDue(
        day: day, appVersion: appVersion, now: now)
      failedAt = nil
      return outcome
    } catch {
      if DatabaseSuspension.isSuspended { return nil }
      failedAt = now
      try? await core.appendDiagnosticLog(
        source: "daily_backup", level: "warn",
        message: "The daily backup for \(day) could not be written.",
        details: String(describing: error))
      return nil
    }
  }
}
