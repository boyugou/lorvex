import LorvexCore
import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// Cancels a task occurrence after a confirmation. A repeating task continues
/// with its next occurrence.
struct LorvexWatchCancelButton: View {
  @Bindable var store: LorvexWatchStore
  let task: LorvexTask
  /// Runs after the action, to close the sheet the button sits in.
  let onDone: () -> Void
  @State private var showingConfirmation = false

  var body: some View {
    Button(role: .destructive) {
      showingConfirmation = true
    } label: {
      Label(
        String(localized: "watch.action.cancel", defaultValue: "Cancel Task", table: "Localizable", bundle: WatchL10n.bundle),
        systemImage: "xmark.circle"
      )
      .font(.headline)
      .foregroundStyle(store.canMutateTasks ? LorvexDesign.Palette.destructive : Color.secondary)
    }
    .disabled(!store.canMutateTasks)
    .buttonStyle(.bordered)
    .tint(LorvexDesign.Palette.destructive)
    .accessibilityLabel(
      String(
        localized: "watch.action.cancel.a11y", defaultValue: "Cancel occurrence",
        table: "Localizable", bundle: WatchL10n.bundle))
    .accessibilityHint(
      String(
        format: String(
          localized: "watch.action.cancel.hint", defaultValue: "Cancels this occurrence of %@",
          table: "Localizable", bundle: WatchL10n.bundle), task.title))
    .accessibilityIdentifier("watch.task.actions.cancel")
    .confirmationDialog(
      String(
        format: String(
          localized: "watch.action.cancel.confirm", defaultValue: "Cancel this occurrence of %@?",
          table: "Localizable", bundle: WatchL10n.bundle), task.title),
      isPresented: $showingConfirmation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "watch.action.cancel_task", defaultValue: "Cancel Occurrence",
          table: "Localizable", bundle: WatchL10n.bundle), role: .destructive
      ) {
        Task {
          await store.cancelTask(id: task.id)
          #if os(watchOS)
            WKInterfaceDevice.current().play(store.error == nil ? .success : .failure)
          #endif
          onDone()
        }
      }
      Button(
        String(
          localized: "watch.action.keep_task", defaultValue: "Keep Task",
          table: "Localizable", bundle: WatchL10n.bundle), role: .cancel
      ) {}
    } message: {
      Text(
        String(
          localized: "watch.action.cancel.message",
          defaultValue: "For repeating tasks, only this occurrence is cancelled and future occurrences continue.",
          table: "Localizable", bundle: WatchL10n.bundle))
    }
  }
}
