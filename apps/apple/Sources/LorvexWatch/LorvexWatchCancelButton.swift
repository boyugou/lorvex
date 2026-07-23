import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// A button that cancels the primary focus task, with a confirmation dialog.
public struct LorvexWatchCancelButton: View {
  @State private var store: LorvexWatchStore
  @State private var showingConfirmation = false

  public init(store: LorvexWatchStore) {
    self.store = store
  }

  public var body: some View {
    Button(role: .destructive) {
      showingConfirmation = true
    } label: {
      Label(String(
        localized: "watch.action.cancel", defaultValue: "Cancel",
        table: "Localizable", bundle: WatchL10n.bundle), systemImage: "xmark.circle")
        .font(.headline)
        .foregroundStyle(store.canCancelPrimaryTask ? Color.red : Color.secondary)
    }
    .disabled(!store.canCancelPrimaryTask)
    .buttonStyle(.bordered)
    .tint(.red)
    .accessibilityLabel(String(
      localized: "watch.action.cancel.a11y", defaultValue: "Cancel occurrence",
      table: "Localizable", bundle: WatchL10n.bundle))
    .accessibilityHint(
      store.completionUnavailableReason
        ?? store.primaryTask.map {
          String(format: String(
            localized: "watch.action.cancel.hint", defaultValue: "Cancels this occurrence of %@",
            table: "Localizable", bundle: WatchL10n.bundle), $0.title)
        }
        ?? String(
          localized: "watch.action.cancel.none", defaultValue: "No task to cancel",
          table: "Localizable", bundle: WatchL10n.bundle)
    )
    .confirmationDialog(
      String(format: String(
        localized: "watch.action.cancel.confirm", defaultValue: "Cancel this occurrence of %@?",
        table: "Localizable", bundle: WatchL10n.bundle), store.primaryTask?.title ?? String(
        localized: "watch.task.fallback", defaultValue: "task",
        table: "Localizable", bundle: WatchL10n.bundle)),
      isPresented: $showingConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(
        localized: "watch.action.cancel_task", defaultValue: "Cancel Occurrence",
        table: "Localizable", bundle: WatchL10n.bundle), role: .destructive) {
        Task {
          await store.cancelPrimaryTask()
          #if os(watchOS)
          WKInterfaceDevice.current().play(store.error == nil ? .success : .failure)
          #endif
        }
      }
      Button(String(
        localized: "watch.action.keep_task", defaultValue: "Keep Task",
        table: "Localizable", bundle: WatchL10n.bundle), role: .cancel) {}
    } message: {
      Text(String(
        localized: "watch.action.cancel.message", defaultValue: "For repeating tasks, only this occurrence is cancelled and future occurrences continue.",
        table: "Localizable", bundle: WatchL10n.bundle))
    }
  }
}
