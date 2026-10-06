import AppKit
import LorvexCore
import SwiftUI

/// Settings control for opening Lorvex when the user signs in, in a group of
/// its own so its explanation is the footer directly under it. The switch
/// follows the system's state (``OpenAtLoginModel``), which it asks again each
/// time the app becomes active, so a change made in System Settings shows up
/// when the user comes back. An item that waits for the user's approval there
/// gets a row of its own with the way to System Settings.
struct SettingsOpenAtLoginSection: View {
  @State private var model: OpenAtLoginModel

  init(loginItem: any LoginItemControlling = SystemLoginItem()) {
    _model = State(initialValue: OpenAtLoginModel(loginItem: loginItem))
  }

  var body: some View {
    Section {
      Toggle(
        String(
          localized: "settings.open_at_login", defaultValue: "Open at Login",
          table: "Localizable", bundle: LorvexL10n.bundle),
        isOn: Binding(get: { model.isOn }, set: { model.setOn($0) })
      )
      .accessibilityIdentifier("settings.openAtLogin.toggle")

      if model.status == .needsApproval {
        approvalRow
      }
    } footer: {
      SettingsOpenAtLoginFooter(failed: model.lastChangeFailed)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in model.refresh()
    }
  }

  /// The way out sits at the notice's trailing edge, like every settings
  /// control, rather than on a line of its own under it.
  private var approvalRow: some View {
    LabeledContent {
      Button(
        String(
          localized: "settings.open_at_login.open_settings", defaultValue: "Open Login Items",
          table: "Localizable", bundle: LorvexL10n.bundle)
      ) {
        model.openSystemSettings()
      }
      .buttonStyle(.bordered)
    } label: {
      Label {
        Text(SettingsOpenAtLoginFooter.approvalCaption)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(LorvexDesign.Palette.warning)
      }
    }
    .accessibilityIdentifier("settings.openAtLogin.approval")
  }
}

/// The caption under the switch: what turning it on does, or, when the last
/// change did not take, a warning that points to System Settings.
struct SettingsOpenAtLoginFooter: View {
  /// Whether the last change ended somewhere other than where it was asked to.
  let failed: Bool

  var body: some View {
    if failed {
      Label {
        Text(Self.failedCaption)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(LorvexDesign.Palette.warning)
      }
      .accessibilityIdentifier("settings.openAtLogin.failed")
    } else {
      Text(Self.caption)
    }
  }

  nonisolated static var caption: String {
    String(
      localized: "settings.open_at_login.detail",
      defaultValue:
        "Lorvex opens at login, so the menu bar and the Quick Capture shortcut are always ready.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// Shown beside the Open Login Items button while the item waits for the
  /// user's approval.
  nonisolated static var approvalCaption: String {
    String(
      localized: "settings.open_at_login.approval",
      defaultValue: "Turn on Lorvex in System Settings > General > Login Items & Extensions.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }

  nonisolated static var failedCaption: String {
    String(
      localized: "settings.open_at_login.failed",
      defaultValue:
        "Lorvex couldn’t change this. Use System Settings > General > Login Items & Extensions instead.",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
