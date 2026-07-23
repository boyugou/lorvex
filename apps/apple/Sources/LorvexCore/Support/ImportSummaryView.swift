import SwiftUI

/// Localized copy provider for ``ImportSummaryView``.
///
/// `LorvexCore` intentionally has no string catalog because this view is shared
/// by the macOS app and the mobile framework. Each host can inject strings from
/// its own bundle while previews/tests can keep the English source defaults.
public struct ImportSummaryTextProvider: Sendable {
  public var categoryName: @Sendable (LorvexDataExportCategory) -> String
  public var importedRecordSummary: @Sendable (_ imported: Int, _ skipped: Int) -> String
  public var categoryResultSummary: @Sendable (_ imported: Int, _ skipped: Int) -> String
  public var errorSummary: @Sendable (_ count: Int) -> String
  public var hiddenErrorsSummary: @Sendable (_ count: Int) -> String

  public init(
    categoryName: @escaping @Sendable (LorvexDataExportCategory) -> String = { $0.displayLabel },
    importedRecordSummary: @escaping @Sendable (_ imported: Int, _ skipped: Int) -> String = {
      imported,
      skipped in
      "Imported \(imported) record\(imported == 1 ? "" : "s")"
        + (skipped > 0 ? ", \(skipped) already present" : "")
    },
    categoryResultSummary: @escaping @Sendable (_ imported: Int, _ skipped: Int) -> String = {
      imported,
      skipped in
      "\(imported) imported" + (skipped > 0 ? ", \(skipped) skipped" : "")
    },
    errorSummary: @escaping @Sendable (_ count: Int) -> String = { count in
      "\(count) record\(count == 1 ? "" : "s") skipped due to errors:"
    },
    hiddenErrorsSummary: @escaping @Sendable (_ count: Int) -> String = { count in
      "and \(count) more…"
    }
  ) {
    self.categoryName = categoryName
    self.importedRecordSummary = importedRecordSummary
    self.categoryResultSummary = categoryResultSummary
    self.errorSummary = errorSummary
    self.hiddenErrorsSummary = hiddenErrorsSummary
  }

  public static let english = ImportSummaryTextProvider()
}

/// Shared post-import summary for the macOS and iOS data-import surfaces: a
/// headline count of imported / already-present records, a per-category
/// imported / skipped breakdown, and — when records failed — a capped list of
/// per-record error detail.
///
/// A malformed file can produce thousands of per-record errors; rendering all of
/// them floods the section with a wall of text. The error detail is therefore
/// capped at ``maxVisibleErrors`` lines, with a trailing "and N more…" when the
/// list is longer.
public struct ImportSummaryView: View {
  /// Maximum number of per-record error lines shown before collapsing the
  /// remainder into an "and N more…" line.
  public static let maxVisibleErrors = 5

  private let summary: LorvexImportSummary
  private let text: ImportSummaryTextProvider

  public init(_ summary: LorvexImportSummary, text: ImportSummaryTextProvider = .english) {
    self.summary = summary
    self.text = text
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(
        text.importedRecordSummary(summary.totalImported, summary.totalSkipped),
        systemImage: "checkmark.circle"
      )
      .font(.caption)
      .foregroundStyle(.green)

      ForEach(summary.results) { result in
        Text(
          "\(text.categoryName(result.category)): \(text.categoryResultSummary(result.imported, result.skipped))"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      if !summary.errors.isEmpty {
        Text(text.errorSummary(summary.errors.count))
        .font(.caption2)
        .foregroundStyle(.orange)

        ForEach(Array(summary.errors.prefix(Self.maxVisibleErrors).enumerated()), id: \.offset) {
          _, error in
          Text("• \(text.categoryName(error.category)) \(error.recordRef): \(error.message)")
            .font(.caption2)
            .foregroundStyle(.orange)
        }

        if summary.errors.count > Self.maxVisibleErrors {
          Text(text.hiddenErrorsSummary(summary.errors.count - Self.maxVisibleErrors))
            .font(.caption2)
            .foregroundStyle(.orange)
        }
      }
    }
  }
}
