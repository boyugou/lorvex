import Foundation

/// One daily backup on this device: the full data export (the same ZIP that
/// Settings › Export writes) taken on a logical day, kept in the managed
/// storage's `DailyBackups` folder beside the database.
public struct LorvexDailyBackup: Sendable, Equatable, Identifiable {
  /// The logical day the backup was taken on, `yyyy-MM-dd`.
  public let day: String
  public let url: URL
  public let byteCount: Int
  /// When the file was written, from its modification date.
  public let takenAt: Date?

  public var id: String { day }

  public init(day: String, url: URL, byteCount: Int, takenAt: Date? = nil) {
    self.day = day
    self.url = url
    self.byteCount = byteCount
    self.takenAt = takenAt
  }
}

/// What one pass of the daily backup writer did.
public enum LorvexDailyBackupOutcome: Sendable, Equatable {
  /// Today's backup was written; older backups beyond the keep rule were removed.
  case written(LorvexDailyBackup)
  /// A backup for today already exists.
  case alreadyPresent
  /// The person turned daily backups off on this device.
  case disabled
  /// The store holds nothing worth keeping, so no backup was written and no
  /// older one was displaced.
  case emptyStore
  /// The store was erased while the backup was being prepared; nothing was kept.
  case superseded
  /// The core has no on-disk managed store (a preview or in-memory core).
  case unavailable
}

/// Naming, listing, and the keep rule of the daily backups. Stateless; the
/// writer is ``LorvexDailyBackupServicing``.
///
/// The keep rule holds the 7 newest backups (one per day the app ran) and,
/// of the older ones, the earliest backup of each of the 4 most recent weeks
/// that have one. Weeks run Monday to Sunday and are counted from a fixed
/// Monday, so a week's earliest backup never changes once its days have
/// passed, and pruning never removes a backup that a later pass would keep.
/// A backup dated more than ``futureToleranceDays`` after the day being
/// written comes from a clock that was set ahead; pruning removes it, so it
/// cannot stay the newest backup for good.
public enum LorvexDailyBackups {
  public static let directoryName = "DailyBackups"
  public static let keptDays = 7
  public static let keptWeeks = 4
  /// How far after today a backup's day may be before pruning treats it as
  /// written under a wrong clock. Two days covers crossing the date line.
  public static let futureToleranceDays = 2

  private static let fileNamePrefix = "lorvex-backup-"
  private static let fileNameSuffix = ".zip"
  private static let unfinishedPrefix = ".lorvex-backup-"
  private static let unfinishedSuffix = ".zip.partial"

  /// The folder that holds the backups of the store at `databasePath`.
  public static func directory(forDatabasePath databasePath: String) -> URL {
    URL(fileURLWithPath: databasePath).deletingLastPathComponent()
      .appendingPathComponent(directoryName, isDirectory: true)
  }

  /// `lorvex-backup-2026-11-23.zip` for the day `2026-11-23`.
  public static func fileName(forDay day: String) -> String {
    fileNamePrefix + day + fileNameSuffix
  }

  /// The file a backup for `day` is written to before it is renamed into
  /// place. The leading dot keeps it out of ``list(in:)`` and Finder.
  static func unfinishedFileName(forDay day: String) -> String {
    unfinishedPrefix + day + unfinishedSuffix
  }

  /// Removes the unfinished files a pass left when the process ended before
  /// renaming or removing them.
  static func removeUnfinishedWrites(in directory: URL) {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    for name in names where name.hasPrefix(unfinishedPrefix) && name.hasSuffix(unfinishedSuffix) {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
  }

  /// The day a backup file name stands for, or `nil` for any other file.
  static func day(fromFileName name: String) -> String? {
    guard name.hasPrefix(fileNamePrefix), name.hasSuffix(fileNameSuffix) else { return nil }
    let day = String(name.dropFirst(fileNamePrefix.count).dropLast(fileNameSuffix.count))
    return dayOrdinal(day) == nil ? nil : day
  }

  /// The backups in `directory`, newest first. A missing folder holds none.
  public static func list(in directory: URL) -> [LorvexDailyBackup] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.compactMap { name -> LorvexDailyBackup? in
      guard let day = day(fromFileName: name) else { return nil }
      let url = directory.appendingPathComponent(name, isDirectory: false)
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
      return LorvexDailyBackup(
        day: day, url: url, byteCount: (attributes?[.size] as? NSNumber)?.intValue ?? 0,
        takenAt: attributes?[.modificationDate] as? Date)
    }
    .sorted { $0.day > $1.day }
  }

  /// The days to keep among `days`, by the keep rule in the type's summary.
  static func daysToKeep(
    _ days: [String], keptDays: Int = keptDays, keptWeeks: Int = keptWeeks
  ) -> Set<String> {
    let dated = Set(days).compactMap { day in dayOrdinal(day).map { (day, $0) } }
      .sorted { $0.1 > $1.1 }
    var keep = Set(dated.prefix(keptDays).map(\.0))
    var earliestInWeek: [Int: (day: String, ordinal: Int)] = [:]
    for (day, ordinal) in dated.dropFirst(keptDays) {
      let week = Int((Double(ordinal) / 7).rounded(.down))
      if let current = earliestInWeek[week], current.ordinal <= ordinal { continue }
      earliestInWeek[week] = (day, ordinal)
    }
    for week in earliestInWeek.keys.sorted(by: >).prefix(keptWeeks) {
      if let day = earliestInWeek[week]?.day { keep.insert(day) }
    }
    return keep
  }

  /// Removes every backup in `directory` the keep rule does not hold, and
  /// every backup dated more than ``futureToleranceDays`` after `today`.
  static func prune(in directory: URL, today: String) {
    let backups = list(in: directory)
    let horizon = dayOrdinal(today).map { $0 + futureToleranceDays }
    let current = backups.filter { backup in
      guard let horizon, let ordinal = dayOrdinal(backup.day), ordinal > horizon else {
        return true
      }
      try? FileManager.default.removeItem(at: backup.url)
      return false
    }
    let keep = daysToKeep(current.map(\.day))
    for backup in current where !keep.contains(backup.day) {
      try? FileManager.default.removeItem(at: backup.url)
    }
  }

  /// Days since 2001-01-01, a Monday, for a `yyyy-MM-dd` day.
  static func dayOrdinal(_ day: String) -> Int? {
    guard day.count == 10, let date = LorvexDateFormatters.ymdUTC.date(from: day),
      LorvexDateFormatters.ymdUTC.string(from: date) == day
    else { return nil }
    return Int((date.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
  }
}
