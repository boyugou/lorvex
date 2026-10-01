import LorvexCore
import SwiftUI

// MARK: - Diagnostics presentational components (rows, status level, panels)

struct SettingsDiagnosticsRow: Identifiable {
  let id: String
  let title: String
  let value: String
  let detail: String?
  let systemImage: String
  var level: SettingsStatusLevel
}

struct SettingsDiagnosticsPanel: View {
  let rows: [SettingsDiagnosticsRow]
  let accessibilityIdentifier: String

  var body: some View {
    // Native grouped-Form rows — the Section header names the group and the
    // Form draws the row separators, so no bespoke card or inner title.
    ForEach(rows) { row in
      SettingsDiagnosticsRowView(row: row)
    }
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

struct SettingsDiagnosticsRowView: View {
  let row: SettingsDiagnosticsRow

  var body: some View {
    LabeledContent {
      VStack(alignment: .trailing, spacing: LorvexDesign.Spacing.xxs) {
        Text(row.value)
          .foregroundStyle(valueColor)
          .multilineTextAlignment(.trailing)
          .lineLimit(2)
        if let detail = row.detail, !detail.isEmpty {
          Text(detail)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    } label: {
      // The status color marks the icon only, so a row name never reads as a
      // link.
      Label {
        Text(row.title)
      } icon: {
        Image(systemName: row.systemImage)
          .foregroundStyle(row.level == .neutral ? AnyShapeStyle(.primary) : AnyShapeStyle(row.level.color))
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("settings.diagnostics.row.\(row.id)")
  }

  /// A value that needs attention (a warning or an error) takes its status
  /// color; a healthy or neutral value reads as plain text.
  private var valueColor: Color {
    switch row.level {
    case .warning, .error: row.level.color
    case .neutral, .success: .primary
    }
  }
}
