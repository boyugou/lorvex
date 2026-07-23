import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// A button that removes the primary task from today's focus plan.
public struct LorvexWatchRemoveFocusButton: View {
  @State private var store: LorvexWatchStore

  public init(store: LorvexWatchStore) {
    self.store = store
  }

  public var body: some View {
    Button(role: .destructive) {
      Task {
        await store.removePrimaryTaskFromFocus()
        #if os(watchOS)
        WKInterfaceDevice.current().play(store.error == nil ? .click : .failure)
        #endif
      }
    } label: {
      Label(String(
        localized: "watch.action.remove", defaultValue: "Remove",
        table: "Localizable", bundle: WatchL10n.bundle), systemImage: "scope")
        .font(.headline)
        .foregroundStyle(store.canRemovePrimaryTaskFromFocus ? Color.red : Color.secondary)
    }
    .disabled(!store.canRemovePrimaryTaskFromFocus)
    .buttonStyle(.bordered)
    .tint(.red)
    .accessibilityLabel(String(
      localized: "watch.action.remove.a11y", defaultValue: "Remove task from focus",
      table: "Localizable", bundle: WatchL10n.bundle))
    .accessibilityHint(
      store.focusMutationUnavailableReason
        ?? store.primaryTask.map {
          String(format: String(
            localized: "watch.action.remove.hint", defaultValue: "Removes %@ from today's focus",
            table: "Localizable", bundle: WatchL10n.bundle), $0.title)
        }
        ?? String(
          localized: "watch.action.remove.none", defaultValue: "No task to remove from focus",
          table: "Localizable", bundle: WatchL10n.bundle)
    )
  }
}
