import AppKit
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
            .accessibilityAddTraits(.isHeader)
        }
      }
    }
    .listStyle(.sidebar)
    // Applied before the column width, which must stay the outer modifier for
    // the split view to read it.
    .toolbar(removing: .sidebarToggle)
    .navigationSplitViewColumnWidth(
      min: SettingsLayoutMetrics.sidebarMinWidth,
      ideal: SettingsLayoutMetrics.sidebarIdealWidth,
      max: SettingsLayoutMetrics.sidebarMaxWidth
    )
    .navigationTitle(String(localized: "settings.title", defaultValue: "Settings", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("settings.sidebar")
  }
}

/// One line per category, named exactly like its page's title in the window's
/// toolbar.
private struct SettingsSidebarRow: View {
  let category: SettingsCategory

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: category.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 22, alignment: .center)
        .accessibilityHidden(true)
      Text(category.title)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
  }
}

/// One category's page: its grouped form, named by the window's toolbar title
/// as System Settings names its panes, so the form starts right under the
/// toolbar.
struct SettingsDetailPage<Content: View>: View {
  let category: SettingsCategory
  @ViewBuilder let content: Content

  var body: some View {
    Form {
      content
    }
    .formStyle(.grouped)
    .labelStyle(SettingsRowLabelStyle())
    .navigationTitle(category.title)
    .navigationSplitViewColumnWidth(
      min: SettingsLayoutMetrics.detailMinWidth,
      ideal: SettingsLayoutMetrics.detailIdealWidth,
      max: SettingsLayoutMetrics.detailMaxWidth
    )
    .accessibilityIdentifier("settings.detail.content")
  }
}

/// The labels of settings rows: the glyph centered in a column of one fixed
/// width, so every row's title starts on the same edge whatever its glyph's
/// width, as System Settings' uniform icon tiles keep its titles aligned. The
/// glyph sits on the title's first baseline, so a message that wraps keeps its
/// glyph beside the first line.
struct SettingsRowLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      configuration.icon
        .frame(width: SettingsLayoutMetrics.rowIconWidth)
      configuration.title
    }
  }
}

/// Gives the Settings window a single-row unified toolbar, the row that holds
/// the traffic lights and the page's title. The Settings scene opens its
/// window in the preference style, which centers the window's title on a row
/// of its own above a second row meant for tab icons; with a sidebar instead
/// of tabs that second row stays empty and pushes every page down. Applied
/// when the view joins its window.
struct SettingsWindowToolbarStyle: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { WindowObservingView() }

  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class WindowObservingView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.toolbarStyle = .unified
    }
  }
}

/// A settings row holding one action that belongs to the rows above it (open
/// iCloud settings under the account, resume under the pause), at the row's
/// trailing edge, where a grouped form puts every other control.
struct SettingsTrailingActionRow<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack {
      Spacer(minLength: 0)
      content
    }
  }
}

/// A settings row that opens a sheet (the About pane's Acknowledgments and
/// Privacy Policy): its glyph and title, and a chevron at the trailing edge.
/// The whole row takes the click.
struct SettingsSheetLinkRow: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Label(title, systemImage: systemImage)
        Spacer(minLength: 0)
        Image(systemName: "chevron.forward")
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.tertiary)
          .accessibilityHidden(true)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A copy button's title: `title`, or "Copied" for a moment after a copy, in
/// the width of the wider of the two, so the button keeps its size at the
/// row's trailing edge while its title changes.
struct SettingsCopyButtonTitle: View {
  var title = String(localized: "common.copy", defaultValue: "Copy", table: "Localizable", bundle: LorvexL10n.bundle)
  let copied: Bool

  var body: some View {
    let copiedTitle = String(localized: "common.copied", defaultValue: "Copied", table: "Localizable", bundle: LorvexL10n.bundle)
    ZStack {
      Text(title).hidden()
      Text(copiedTitle).hidden()
      Text(copied ? copiedTitle : title)
    }
  }
}

/// The shared disclosure header that folds detail out of a settings pane's
/// default view: "Advanced" in the Storage, Cloud Sync, and Assistant panes, and
/// an entry count over the Activity pane's changelog and logs. A plain `Button` rather than `DisclosureGroup`: the native disclosure
/// triangle drops its first click inside a freshly laid-out grouped Form (the
/// Settings detail is an NSTableView-backed Form in a `NavigationSplitView`), so
/// a collapsed section needed a dead first tap until the pane was re-shown; a
/// plain button hit-tests on the first click. Each pane supplies its own
/// `accessibilityIdentifier` (`settings.<region>.advancedToggle`).
struct SettingsAdvancedDisclosureButton: View {
  @Binding var isExpanded: Bool
  var title = LocalizedStringResource("settings.advanced", defaultValue: "Advanced", table: "Localizable", bundle: LorvexL10n.bundle)
  let accessibilityIdentifier: String

  var body: some View {
    Button {
      lorvexAnimated(.snappy(duration: 0.2)) { isExpanded.toggle() }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.s) {
        Text(title)
        Spacer(minLength: 0)
        LorvexDisclosureChevron(isExpanded: isExpanded)
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.tertiary)
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
      defaultValue: "Shows or hides more detail.",
      table: "Localizable",
      bundle: LorvexL10n.bundle))
  }
}
