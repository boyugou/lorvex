import SwiftUI

/// Bridges the main window's `NavigationSplitViewVisibility` to the menu bar.
///
/// The toolbar's sidebar toggle is the only built-in way to collapse the main
/// window's sidebar — there is no View-menu item and no keyboard shortcut, which
/// breaks the macOS convention every other app follows. Publishing the live
/// column-visibility binding through this focused value lets
/// `SidebarVisibilityCommandButton` drive the very same state the toolbar button
/// does, so the menu item, ⌃⌘S, and the toolbar button stay in lock-step.
///
/// The value is `nil` whenever no window publishes it (e.g. a detached task or
/// list window is key), which disables the command rather than letting ⌃⌘S
/// silently no-op.
struct SidebarVisibilityKey: FocusedValueKey {
  typealias Value = Binding<NavigationSplitViewVisibility>
}

extension FocusedValues {
  var sidebarVisibility: Binding<NavigationSplitViewVisibility>? {
    get { self[SidebarVisibilityKey.self] }
    set { self[SidebarVisibilityKey.self] = newValue }
  }
}

/// The standard macOS "Hide Sidebar" / "Show Sidebar" View-menu command, bound
/// to ⌃⌘S. Reads the focused window's column-visibility binding and flips it
/// between `.all` (sidebar shown) and `.detailOnly` (sidebar hidden), matching
/// the toolbar toggle. The title reflects the current state the way Finder and
/// Mail do, and the command is disabled when no window publishes the binding.
struct SidebarVisibilityCommandButton: View {
  @FocusedValue(\.sidebarVisibility) private var sidebarVisibility

  var body: some View {
    Button(title) {
      guard let sidebarVisibility else { return }
      lorvexAnimated(.snappy(duration: 0.2)) {
        sidebarVisibility.wrappedValue =
          sidebarVisibility.wrappedValue == .detailOnly ? .all : .detailOnly
      }
    }
    .keyboardShortcut("s", modifiers: [.control, .command])
    .disabled(sidebarVisibility == nil)
  }

  private var title: String {
    if sidebarVisibility?.wrappedValue == .detailOnly {
      String(localized: "app.commands.show_sidebar", defaultValue: "Show Sidebar", table: "Localizable", bundle: LorvexL10n.bundle)
    } else {
      String(localized: "app.commands.hide_sidebar", defaultValue: "Hide Sidebar", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}
