import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// A button that marks the primary focus task complete.
///
/// Disabled while the store is loading or when there is no primary task to act on.
public struct LorvexWatchCompleteButton: View {
  @State private var store: LorvexWatchStore

  public init(store: LorvexWatchStore) {
    self.store = store
  }

  public var body: some View {
    Button {
      Task {
        await store.completePrimaryTask()
        #if os(watchOS)
        WKInterfaceDevice.current().play(store.error == nil ? .success : .failure)
        #endif
      }
    } label: {
      Label(String(
        localized: "watch.action.complete", defaultValue: "Complete",
        table: "Localizable", bundle: WatchL10n.bundle), systemImage: "checkmark.circle.fill")
        .font(.headline)
        .foregroundStyle(store.canCompletePrimaryTask ? Color.green : Color.secondary)
    }
    .disabled(!store.canCompletePrimaryTask)
    .buttonStyle(.borderedProminent)
    .tint(.green)
    .accessibilityLabel(String(
      localized: "watch.action.complete.primary.a11y", defaultValue: "Mark task complete",
      table: "Localizable", bundle: WatchL10n.bundle))
    .accessibilityHint(
      store.completionUnavailableReason
        ?? store.primaryTask.map {
          String(format: String(
            localized: "watch.action.complete.hint", defaultValue: "Completes %@",
            table: "Localizable", bundle: WatchL10n.bundle), $0.title)
        }
        ?? String(
          localized: "watch.action.complete.none", defaultValue: "No task to complete",
          table: "Localizable", bundle: WatchL10n.bundle)
    )
  }
}
