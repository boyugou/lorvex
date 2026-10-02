import SwiftUI

/// The summary the Mac and iPhone import screens show once an import has run,
/// built from ``ImportSummaryLine/lines(for:maxVisibleIssueLines:)``: a
/// headline with a symbol, then caption lines for each category and for the
/// records that did not come back whole. Every word comes from LorvexCore's
/// catalog, so both apps word a summary alike.
public struct ImportSummaryView: View {
  /// How many lines of records with problems the summary lists before a last
  /// line counts the rest; a damaged file can produce thousands.
  public static let maxVisibleIssueLines = 5

  private let lines: [ImportSummaryLine]

  public init(_ summary: LorvexImportSummary) {
    lines = ImportSummaryLine.lines(for: summary, maxVisibleIssueLines: Self.maxVisibleIssueLines)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(lines) { line in
        switch line.style {
        case .headline(let systemImage):
          Label(line.text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(Self.style(line.tone))
        case .heading:
          Text(line.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Self.style(line.tone))
            .padding(.top, 4)
        case .item:
          // The bullet stands apart so a wrapped name hangs under its first line.
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: "•")
            Text(line.text)
          }
          .font(.caption2)
          .foregroundStyle(Self.style(line.tone))
        case .detail:
          Text(line.text)
            .font(.caption2)
            .foregroundStyle(Self.style(line.tone))
        }
      }
    }
  }

  private static func style(_ tone: ImportSummaryLine.Tone) -> AnyShapeStyle {
    switch tone {
    case .success: AnyShapeStyle(LorvexDesign.Palette.success)
    case .warning: AnyShapeStyle(LorvexDesign.Palette.warning)
    case .primary: AnyShapeStyle(.primary)
    case .secondary: AnyShapeStyle(.secondary)
    }
  }
}
