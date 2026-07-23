import SwiftUI

struct LorvexMenuBarExtraView: View {
  let store: AppStore

  var body: some View {
    MenuBarStatusView(store: store)
      .tint(.accentColor)
  }
}

/// The menu-bar status-item glyph: the app mark, with the attention count
/// (tasks due today or overdue) appended like a peer task manager's tray badge
/// when there's something to act on. Renders as a template image so it inverts
/// with the menu bar's light/dark appearance.
struct LorvexMenuBarExtraLabel: View {
  @Bindable var store: AppStore

  var body: some View {
    let count = store.menuBarAttentionCount
    if count > 0 {
      Label("\(count)", systemImage: LorvexWindowID.main.systemImage)
        .accessibilityLabel(Text(LocalizedStringResource(
          "menubar.icon.due_a11y", defaultValue: "Lorvex — tasks needing attention",
          table: "Localizable",
          bundle: LorvexL10n.bundle)))
        .accessibilityValue("\(count)")
    } else {
      Image(systemName: LorvexWindowID.main.systemImage)
        .accessibilityLabel(Text(LorvexWindowID.main.title))
    }
  }
}
