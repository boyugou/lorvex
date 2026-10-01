import LorvexCore
import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// Defers a task until tomorrow, which takes it off Today.
struct LorvexWatchDeferButton: View {
  @Bindable var store: LorvexWatchStore
  let task: LorvexTask
  /// Runs after the action, to close the sheet the button sits in.
  let onDone: () -> Void

  var body: some View {
    Button {
      Task {
        await store.deferTaskToTomorrow(id: task.id)
        #if os(watchOS)
          WKInterfaceDevice.current().play(store.error == nil ? .click : .failure)
        #endif
        onDone()
      }
    } label: {
      Label(
        String(localized: "watch.action.tomorrow", defaultValue: "Tomorrow", table: "Localizable", bundle: WatchL10n.bundle),
        systemImage: "calendar.badge.clock"
      )
      .font(.headline)
      .foregroundStyle(store.canMutateTasks ? Color.primary : Color.secondary)
    }
    .disabled(!store.canMutateTasks)
    // Neutral: deferring is not urgent (orange) and must not read as the
    // blue Start/Pause beside it.
    .buttonStyle(.bordered)
    .accessibilityLabel(
      String(
        localized: "watch.action.defer.a11y", defaultValue: "Defer until tomorrow",
        table: "Localizable", bundle: WatchL10n.bundle))
    .accessibilityHint(
      String(
        format: String(
          localized: "watch.action.defer.hint", defaultValue: "Defers %@ until tomorrow",
          table: "Localizable", bundle: WatchL10n.bundle), task.title))
    .accessibilityIdentifier("watch.task.actions.tomorrow")
  }
}
