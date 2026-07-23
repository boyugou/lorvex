import LorvexCore
import SwiftUI

extension LorvexMobileStoreRootView {
  /// Hidden buttons that register hardware-keyboard shortcuts for visionOS.
  /// `.keyboardShortcut` on visionOS requires the button to be in the responder
  /// chain; placing them in a zero-frame, invisible overlay attaches them
  /// without disturbing the visible layout.
  ///
  /// Shortcuts:
  /// - ⌘R refreshes the snapshot.
  /// - ⌘1…⌘5 switch to Today / Tasks / Calendar / Habits / More.
  /// - ⌘N raises the quick-capture sheet (matching the macOS quick-capture key).
  /// - mnemonic keys open extended iPad workspaces.
  var keyboardShortcuts: some View {
    #if os(visionOS)
      ZStack {
        Button("") { Task { await store.refreshResettingCloudSyncPacing() } }
          .keyboardShortcut("r", modifiers: .command)
        Button("") { store.openPrimaryShortcutTab(.today) }
          .keyboardShortcut("1", modifiers: .command)
        Button("") { store.openPrimaryShortcutTab(.tasks) }
          .keyboardShortcut("2", modifiers: .command)
        Button("") { store.openPrimaryShortcutTab(.calendar) }
          .keyboardShortcut("3", modifiers: .command)
        Button("") { store.openPrimaryShortcutTab(.habits) }
          .keyboardShortcut("4", modifiers: .command)
        Button("") { store.openPrimaryShortcutTab(.more) }
          .keyboardShortcut("5", modifiers: .command)
        Button("") { store.isPresentingCapture = true }
          .keyboardShortcut("n", modifiers: .command)
        ForEach(MobileDestination.allCases) { destination in
          Button("") { store.openShortcutDestination(destination) }
            .keyboardShortcut(
              KeyEquivalent(Character(destination.keyboardShortcutKey)),
              modifiers: .command
            )
        }
      }
      .frame(width: 0, height: 0)
      .opacity(0)
      .accessibilityHidden(true)
    #else
      EmptyView()
    #endif
  }
}
