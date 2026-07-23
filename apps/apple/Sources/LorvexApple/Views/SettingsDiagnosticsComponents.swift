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
      VStack(alignment: .trailing, spacing: 2) {
        Text(row.value)
          .foregroundStyle(row.level == .error ? .red : .primary)
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
      Label(row.title, systemImage: row.systemImage)
        .foregroundStyle(row.level == .neutral ? AnyShapeStyle(.primary) : AnyShapeStyle(row.level.color))
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("settings.diagnostics.row.\(row.id)")
  }
}

struct SettingsDiagnosticsGuidePanel: View {
  let guide: GuideSnapshot

  var body: some View {
    Group {
      Label {
        VStack(alignment: .leading, spacing: 3) {
          Text(guide.topic.isEmpty
            ? String(localized: "settings.diagnostics.guide", defaultValue: "Guide", table: "Localizable", bundle: LorvexL10n.bundle)
            : guide.topic)
            .font(LorvexDesign.Typography.primaryEmphasis)
          Text(guide.summary)
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      } icon: {
        Image(systemName: "sparkles")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(Color.accentColor)
      }

      if !guide.suggestedActions.isEmpty {
        ForEach(guide.suggestedActions, id: \.self) { action in
          Label(action, systemImage: "checkmark.circle")
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .accessibilityIdentifier("settings.diagnostics.guidePanel")
  }
}
