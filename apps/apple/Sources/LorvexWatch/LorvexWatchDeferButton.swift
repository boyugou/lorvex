import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// A button that defers the primary focus task until tomorrow.
public struct LorvexWatchDeferButton: View {
  @State private var store: LorvexWatchStore

  public init(store: LorvexWatchStore) {
    self.store = store
  }

  public var body: some View {
    Button {
      Task {
        await store.deferPrimaryTaskToTomorrow()
        #if os(watchOS)
        WKInterfaceDevice.current().play(store.error == nil ? .click : .failure)
        #endif
      }
    } label: {
      Label(String(
        localized: "watch.action.tomorrow", defaultValue: "Tomorrow",
        table: "Localizable", bundle: WatchL10n.bundle), systemImage: "calendar.badge.clock")
        .font(.headline)
        .foregroundStyle(store.canDeferPrimaryTask ? Color.orange : Color.secondary)
    }
    .disabled(!store.canDeferPrimaryTask)
    .buttonStyle(.bordered)
    .tint(.orange)
    .accessibilityLabel(String(
      localized: "watch.action.defer.primary.a11y", defaultValue: "Defer task until tomorrow",
      table: "Localizable", bundle: WatchL10n.bundle))
    .accessibilityHint(
      store.completionUnavailableReason
        ?? store.primaryTask.map {
          String(format: String(
            localized: "watch.action.defer.hint", defaultValue: "Defers %@ until tomorrow",
            table: "Localizable", bundle: WatchL10n.bundle), $0.title)
        }
        ?? String(
          localized: "watch.action.defer.none", defaultValue: "No task to defer",
          table: "Localizable", bundle: WatchL10n.bundle)
    )
  }
}
