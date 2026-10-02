import Foundation

/// One line of ``ImportSummaryView``: its words, from LorvexCore's catalog,
/// and how the line is set.
///
/// ``lines(for:maxVisibleIssueLines:)`` builds the whole summary. A refused
/// backup is one warning headline with the reason. Otherwise the headline
/// counts the records imported and already present (a warning when nothing
/// was imported but something went wrong), one line per category follows,
/// and then the records that did not come back whole, as bulleted items in
/// two groups: those not imported ("Tasks: “Buy milk”"; a category alone when
/// the whole category failed or the record has no name), and tasks restored
/// without some details, one item per task listing every detail it lacks
/// ("“Buy milk”: reminders and repeat rule"). Repeated items are shown once.
/// The items stop at `maxVisibleIssueLines`, and a last line counts the rest.
public struct ImportSummaryLine: Identifiable, Equatable, Sendable {
  public enum Style: Equatable, Sendable {
    /// The opening line, with a symbol.
    case headline(systemImage: String)
    /// The heading over a group of records with problems.
    case heading
    /// A record with a problem, set after a bullet.
    case item
    /// Any other line.
    case detail
  }

  public enum Tone: Equatable, Sendable {
    /// The headline of an import that brought records back.
    case success
    /// What needs attention: a refusal, a headline when nothing came back,
    /// and the headings over records with problems.
    case warning
    /// The records with problems themselves, which people read closely.
    case primary
    /// Counts and the closing count of hidden lines.
    case secondary
  }

  /// The line's position in the summary.
  public let id: Int
  public let text: String
  public let style: Style
  public let tone: Tone

  public init(id: Int, text: String, style: Style, tone: Tone) {
    self.id = id
    self.text = text
    self.style = style
    self.tone = tone
  }

  public static func lines(
    for summary: LorvexImportSummary, maxVisibleIssueLines: Int
  ) -> [ImportSummaryLine] {
    var lines: [(text: String, style: Style, tone: Tone)] = []
    if let rejection = summary.rejection {
      lines.append(
        (rejection.localizedDescription, .headline(systemImage: "exclamationmark.triangle"), .warning))
      return numbered(lines)
    }

    let nothingImported = summary.totalImported == 0 && !summary.issues.isEmpty
    lines.append(
      (
        importedText(summary.totalImported, skipped: summary.totalSkipped),
        .headline(systemImage: nothingImported ? "exclamationmark.triangle" : "checkmark.circle"),
        nothingImported ? .warning : .success
      ))
    for result in summary.results {
      lines.append((categoryResultText(result), .detail, .secondary))
    }

    var remaining = max(maxVisibleIssueLines, 0)
    var hidden = 0
    for (heading, group) in [
      (notImportedHeading, notImportedLines(summary.issues)),
      (restoredWithoutHeading, restoredWithoutLines(summary.issues)),
    ] where !group.isEmpty {
      let shown = group.prefix(remaining)
      hidden += group.count - shown.count
      remaining -= shown.count
      guard !shown.isEmpty else { continue }
      lines.append((heading, .heading, .warning))
      lines.append(contentsOf: shown.map { ($0, .item, .primary) })
    }
    if hidden > 0 {
      lines.append((moreIssuesText(hidden), .detail, .secondary))
    }
    return numbered(lines)
  }

  private static func numbered(
    _ lines: [(text: String, style: Style, tone: Tone)]
  ) -> [ImportSummaryLine] {
    lines.enumerated().map { index, line in
      ImportSummaryLine(id: index, text: line.text, style: line.style, tone: line.tone)
    }
  }

  // MARK: - Issue groups

  /// One item per record not imported, in import order, each shown once.
  private static func notImportedLines(_ issues: [LorvexImportIssue]) -> [String] {
    var lines: [String] = []
    for issue in issues where issue.outcome == .notImported {
      let category = issue.category.localizedDisplayName
      let line: String
      switch issue.record {
      case .wholeCategory, .named(_, nil):
        line = category
      case .named(_, let name?):
        line = issueLine(category, quoted(name))
      case .day(let day):
        line = issueLine(category, dayText(day))
      }
      if !lines.contains(line) { lines.append(line) }
    }
    return lines
  }

  /// One item per restored record that lacks details, in import order, naming
  /// every detail it lacks in ``LorvexImportIssue/Part`` order.
  private static func restoredWithoutLines(_ issues: [LorvexImportIssue]) -> [String] {
    var order: [LorvexImportIssue] = []
    var parts: [Int: Set<LorvexImportIssue.Part>] = [:]
    for issue in issues {
      guard case .restoredWithout(let part) = issue.outcome else { continue }
      let index =
        order.firstIndex { $0.category == issue.category && $0.record == issue.record }
        ?? {
          order.append(issue)
          return order.count - 1
        }()
      parts[index, default: []].insert(part)
    }
    return order.enumerated().map { index, issue in
      let label: String
      switch issue.record {
      case .named(_, let name?): label = quoted(name)
      case .day(let day): label = dayText(day)
      case .wholeCategory, .named(_, nil): label = issue.category.localizedDisplayName
      }
      let lacking = LorvexImportIssue.Part.allCases.filter { parts[index]?.contains($0) == true }
      return issueLine(label, lacking.map(\.localizedName).formatted(
        .list(type: .and).locale(LorvexClockFormat.displayLocale)))
    }
  }

  private static func dayText(_ day: String) -> String {
    guard let date = LorvexDateFormatters.ymdUTC.date(from: day) else { return day }
    return LorvexDateFormatters.string(date, dateStyle: .medium, timeZone: .gmt)
  }

  // MARK: - Words

  private static func importedText(_ imported: Int, skipped: Int) -> String {
    let summary = String(
      localized: "data_import.summary.imported_count",
      defaultValue: "\(imported) imported records",
      table: "Localizable", bundle: CoreL10n.bundle)
    guard skipped > 0 else { return summary }
    return String(
      localized: "data_import.summary.imported_with_skipped",
      defaultValue: "\(summary), \(skipped) already present",
      table: "Localizable", bundle: CoreL10n.bundle)
  }

  private static func categoryResultText(_ result: LorvexImportCategoryResult) -> String {
    let imported = result.imported
    var counts = String(
      localized: "data_import.summary.category_imported_count",
      defaultValue: "\(imported) imported",
      table: "Localizable", bundle: CoreL10n.bundle)
    if result.skipped > 0 {
      let skipped = result.skipped
      counts = String(
        localized: "data_import.summary.category_imported_with_skipped",
        defaultValue: "\(counts), \(skipped) skipped",
        table: "Localizable", bundle: CoreL10n.bundle)
    }
    let category = result.category.localizedDisplayName
    return String(
      localized: "data_import.summary.category_line",
      defaultValue: "\(category): \(counts)",
      table: "Localizable", bundle: CoreL10n.bundle)
  }

  private static var notImportedHeading: String {
    String(
      localized: "data_import.summary.not_imported_heading", defaultValue: "Not imported:",
      table: "Localizable", bundle: CoreL10n.bundle)
  }

  private static var restoredWithoutHeading: String {
    String(
      localized: "data_import.summary.restored_without_heading",
      defaultValue: "Restored without these details:",
      table: "Localizable", bundle: CoreL10n.bundle)
  }

  private static func issueLine(_ label: String, _ value: String) -> String {
    String(
      localized: "data_import.summary.issue_line", defaultValue: "\(label): \(value)",
      table: "Localizable", bundle: CoreL10n.bundle)
  }

  private static func quoted(_ name: String) -> String {
    String(
      localized: "data_import.summary.quoted_name", defaultValue: "“\(name)”",
      table: "Localizable", bundle: CoreL10n.bundle)
  }

  private static func moreIssuesText(_ count: Int) -> String {
    String(
      localized: "data_import.summary.more_issues_count", defaultValue: "and \(count) more…",
      table: "Localizable", bundle: CoreL10n.bundle)
  }
}

extension LorvexImportIssue.Part {
  /// The detail's name in the import summary's list of what a restored task
  /// lacks ("reminders", "repeat rule").
  public var localizedName: String {
    switch self {
    case .plannedTime:
      String(localized: "data_import.issue.part.planned_time", defaultValue: "planned time", table: "Localizable", bundle: CoreL10n.bundle)
    case .list:
      String(localized: "data_import.issue.part.list", defaultValue: "list", table: "Localizable", bundle: CoreL10n.bundle)
    case .checklist:
      String(localized: "data_import.issue.part.checklist", defaultValue: "checklist", table: "Localizable", bundle: CoreL10n.bundle)
    case .reminders:
      String(localized: "data_import.issue.part.reminders", defaultValue: "reminders", table: "Localizable", bundle: CoreL10n.bundle)
    case .recurrence:
      String(localized: "data_import.issue.part.recurrence", defaultValue: "repeat rule", table: "Localizable", bundle: CoreL10n.bundle)
    case .dependencies:
      String(localized: "data_import.issue.part.dependencies", defaultValue: "dependencies", table: "Localizable", bundle: CoreL10n.bundle)
    case .status:
      String(localized: "data_import.issue.part.status", defaultValue: "status", table: "Localizable", bundle: CoreL10n.bundle)
    case .history:
      String(localized: "data_import.issue.part.history", defaultValue: "history", table: "Localizable", bundle: CoreL10n.bundle)
    }
  }
}
