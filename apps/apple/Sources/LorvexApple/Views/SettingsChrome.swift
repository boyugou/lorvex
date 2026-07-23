import LorvexCore
import SwiftUI

// Settings sidebar/category chrome, split from SettingsView.swift to keep that
// file under the hotspot line cap. Pure presentation + the category model.

enum SettingsCategory: String, CaseIterable, Identifiable {
  case general
  case permissions
  case calendar
  case cloudSync
  case mcpHost
  case data
  case diagnostics

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general:
      String(localized: "settings.tab.general", defaultValue: "General", table: "Localizable", bundle: LorvexL10n.bundle)
    case .permissions:
      String(localized: "settings.tab.permissions", defaultValue: "Permissions", table: "Localizable", bundle: LorvexL10n.bundle)
    case .calendar:
      String(localized: "settings.tab.calendar_reminders", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
    case .cloudSync:
      String(localized: "settings.tab.cloud_sync", defaultValue: "Cloud Sync", table: "Localizable", bundle: LorvexL10n.bundle)
    case .mcpHost:
      String(localized: "settings.tab.mcp_host", defaultValue: "Assistant", table: "Localizable", bundle: LorvexL10n.bundle)
    case .data:
      String(localized: "settings.tab.data", defaultValue: "Data", table: "Localizable", bundle: LorvexL10n.bundle)
    case .diagnostics:
      String(localized: "settings.tab.diagnostics", defaultValue: "Diagnostics", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var sidebarTitle: String {
    switch self {
    case .general:
      title
    case .permissions:
      title
    case .calendar:
      String(localized: "settings.sidebar.calendar.title", defaultValue: "Calendar", table: "Localizable", bundle: LorvexL10n.bundle)
    case .cloudSync:
      String(localized: "settings.sidebar.cloud_sync.title", defaultValue: "Cloud", table: "Localizable", bundle: LorvexL10n.bundle)
    case .mcpHost:
      String(localized: "settings.sidebar.mcp_host.title", defaultValue: "Assistant", table: "Localizable", bundle: LorvexL10n.bundle)
    case .data:
      title
    case .diagnostics:
      title
    }
  }

  var subtitle: String {
    switch self {
    case .general:
      String(
        localized: "settings.tab.general.subtitle",
        defaultValue: "Appearance, language, and working hours.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .permissions:
      String(
        localized: "settings.tab.permissions.subtitle",
        defaultValue: "System access and Dock badge behavior.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .calendar:
      String(
        localized: "settings.tab.calendar_reminders.subtitle",
        defaultValue: "Calendar import and write-back.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .cloudSync:
      String(
        localized: "settings.tab.cloud_sync.subtitle",
        defaultValue: "iCloud readiness and sync mode.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .mcpHost:
      String(
        localized: "settings.tab.mcp_host.subtitle",
        defaultValue: "AI host connection and helper diagnostics.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .data:
      String(
        localized: "settings.tab.data.subtitle",
        defaultValue: "Database, export, import, and backups.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case .diagnostics:
      String(
        localized: "settings.tab.diagnostics.subtitle",
        defaultValue: "Runtime checks, changelog, and recent logs.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    }
  }

  var sidebarSubtitle: String {
    switch self {
    case .general:
      String(localized: "settings.sidebar.general.subtitle", defaultValue: "Appearance and language", table: "Localizable", bundle: LorvexL10n.bundle)
    case .permissions:
      String(localized: "settings.sidebar.permissions.subtitle", defaultValue: "System access", table: "Localizable", bundle: LorvexL10n.bundle)
    case .calendar:
      String(localized: "settings.sidebar.calendar.subtitle", defaultValue: "Calendar integration", table: "Localizable", bundle: LorvexL10n.bundle)
    case .cloudSync:
      String(localized: "settings.sidebar.cloud_sync.subtitle", defaultValue: "iCloud status", table: "Localizable", bundle: LorvexL10n.bundle)
    case .mcpHost:
      String(localized: "settings.sidebar.mcp_host.subtitle", defaultValue: "Assistant connection", table: "Localizable", bundle: LorvexL10n.bundle)
    case .data:
      String(localized: "settings.sidebar.data.subtitle", defaultValue: "Database and backups", table: "Localizable", bundle: LorvexL10n.bundle)
    case .diagnostics:
      String(localized: "settings.sidebar.diagnostics.subtitle", defaultValue: "Health checks", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .permissions: "checkmark.shield"
    case .calendar: "calendar"
    case .cloudSync: "icloud"
    case .mcpHost: "network"
    case .data: "arrow.down.doc"
    case .diagnostics: "waveform.path.ecg"
    }
  }
}

private enum SettingsCategoryGroup: String, CaseIterable, Identifiable {
  case basics
  case connections
  case operations

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .basics: LocalizedStringResource("settings.group.basics", defaultValue: "Basics", table: "Localizable", bundle: LorvexL10n.bundle)
    case .connections: LocalizedStringResource("settings.group.connections", defaultValue: "Connections", table: "Localizable", bundle: LorvexL10n.bundle)
    case .operations: LocalizedStringResource("settings.group.operations", defaultValue: "Operations", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  var categories: [SettingsCategory] {
    switch self {
    case .basics: [.general, .permissions]
    case .connections: [.calendar, .cloudSync, .mcpHost]
    case .operations: [.data, .diagnostics]
    }
  }
}

struct SettingsSidebar: View {
  @Binding var selectedCategory: SettingsCategory

  var body: some View {
    List(selection: $selectedCategory) {
      ForEach(SettingsCategoryGroup.allCases) { group in
        Section {
          ForEach(group.categories) { category in
            SettingsSidebarRow(category: category)
              .tag(category)
              .accessibilityIdentifier("settings.sidebar.\(category.rawValue)")
          }
        } header: {
          Text(group.title)
            .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
    }
    .listStyle(.sidebar)
    .navigationSplitViewColumnWidth(
      min: SettingsLayoutMetrics.sidebarMinWidth,
      ideal: SettingsLayoutMetrics.sidebarIdealWidth,
      max: SettingsLayoutMetrics.sidebarMaxWidth
    )
    .navigationTitle(String(localized: "settings.title", defaultValue: "Settings", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("settings.sidebar")
  }
}

private struct SettingsSidebarRow: View {
  let category: SettingsCategory

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: category.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 22, alignment: .center)
      VStack(alignment: .leading, spacing: 1) {
        Text(category.sidebarTitle)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(category.sidebarSubtitle)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
  }
}

struct SettingsDetailPage<Content: View>: View {
  let category: SettingsCategory
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      SettingsDetailHeader(category: category)
      Divider()
      Form {
        content
      }
      .formStyle(.grouped)
      .accessibilityIdentifier("settings.detail.content")
    }
    .background(.background)
    .navigationSplitViewColumnWidth(
      min: SettingsLayoutMetrics.detailMinWidth,
      ideal: SettingsLayoutMetrics.detailIdealWidth,
      max: SettingsLayoutMetrics.detailMaxWidth
    )
    .accessibilityIdentifier("settings.detail.page")
  }
}

private struct SettingsDetailHeader: View {
  let category: SettingsCategory

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      Image(systemName: category.systemImage)
        .font(LorvexDesign.Typography.primaryText.weight(.semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 22, alignment: .center)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(category.title)
          .font(LorvexDesign.Typography.sectionHeader)
        Text(category.subtitle)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(.horizontal, SettingsLayoutMetrics.detailHorizontalPadding)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.bar)
    .accessibilityIdentifier("settings.detail.header")
  }
}

/// The shared "Advanced" disclosure header used by the Storage, Cloud Sync, and
/// Assistant settings panes to fold troubleshooting detail out of the default
/// view. A plain `Button` rather than `DisclosureGroup`: the native disclosure
/// triangle drops its first click inside a freshly laid-out grouped Form (the
/// Settings detail is an NSTableView-backed Form in a `NavigationSplitView`), so
/// a collapsed section needed a dead first tap until the pane was re-shown; a
/// plain button hit-tests on the first click. Each pane supplies its own
/// `accessibilityIdentifier` (`settings.<region>.advancedToggle`).
struct SettingsAdvancedDisclosureButton: View {
  @Binding var isExpanded: Bool
  let accessibilityIdentifier: String

  var body: some View {
    Button {
      lorvexAnimated(.snappy(duration: 0.2)) { isExpanded.toggle() }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Text(LocalizedStringResource("settings.advanced", defaultValue: "Advanced", table: "Localizable", bundle: LorvexL10n.bundle))
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.tertiary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(accessibilityIdentifier)
    .accessibilityAddTraits(.isHeader)
    .accessibilityValue(String(localized: isExpanded
      ? LocalizedStringResource("common.expanded", defaultValue: "Expanded", table: "Localizable", bundle: LorvexL10n.bundle)
      : LocalizedStringResource("common.collapsed", defaultValue: "Collapsed", table: "Localizable", bundle: LorvexL10n.bundle)))
    .accessibilityHint(String(
      localized: "settings.advanced.a11y_hint",
      defaultValue: "Shows or hides advanced options.",
      table: "Localizable",
      bundle: LorvexL10n.bundle))
  }
}
