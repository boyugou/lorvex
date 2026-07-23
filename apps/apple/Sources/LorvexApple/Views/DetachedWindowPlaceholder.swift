import LorvexCore
import SwiftUI

struct DetachedWindowPlaceholder: View {
  let systemImage: String
  let title: String
  /// Why the detached window is empty (item not yet picked, or removed on
  /// another device). Gives the user something to act on instead of a mute
  /// icon.
  var message: String = String(
    localized:
      "detached_window.placeholder.message",
      defaultValue: "Select an item from the main window — or it may have been deleted on another device.",
      table: "Localizable",
      bundle: LorvexL10n.bundle
    )
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    LorvexEmptyStatePanel(
      title: title,
      message: message,
      systemImage: systemImage,
      tint: .accentColor,
      chips: [
        LorvexEmptyStateChip(
          title: String(localized: "detached_window.placeholder.chip", defaultValue: "Detached Window", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "macwindow",
          tint: .accentColor
        )
      ]
    ) {
      Button {
        openWindow(.main)
      } label: {
        Label(
          String(
            localized:
              "detached_window.open_main",
              defaultValue: "Open Main Window",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
          systemImage: LorvexWindowID.main.systemImage
        )
      }
      .accessibilityIdentifier("detachedWindow.openMain")
    }
  }
}

struct DetachedWindowLoadingView: View {
  let systemImage: String
  let title: String

  var body: some View {
    VStack(spacing: LorvexDesign.Spacing.m) {
      Image(systemName: systemImage)
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text(title)
        .font(LorvexDesign.Typography.sectionHeader)
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel(String(localized: "common.loading", defaultValue: "Loading", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("detachedWindow.loading")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(40)
  }
}
