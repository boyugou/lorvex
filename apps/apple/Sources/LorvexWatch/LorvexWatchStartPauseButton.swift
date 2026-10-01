import LorvexCore
import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

/// Starts a task, or pauses it when it is already started. A started task
/// moves up with the other started tasks at the top of Today.
struct LorvexWatchStartPauseButton: View {
  @Bindable var store: LorvexWatchStore
  let task: LorvexTask
  /// Runs after the action, to close the sheet the button sits in.
  let onDone: () -> Void

  private var isStarted: Bool { task.status == .inProgress }

  var body: some View {
    Button {
      Task {
        if isStarted {
          await store.pauseTask(id: task.id)
        } else {
          await store.startTask(id: task.id)
        }
        #if os(watchOS)
          WKInterfaceDevice.current().play(store.error == nil ? .click : .failure)
        #endif
        onDone()
      }
    } label: {
      Label(
        isStarted
          ? String(localized: "watch.action.pause", defaultValue: "Pause", table: "Localizable", bundle: WatchL10n.bundle)
          : String(localized: "watch.action.start", defaultValue: "Start", table: "Localizable", bundle: WatchL10n.bundle),
        systemImage: isStarted ? "pause.circle" : "play.circle"
      )
      .font(.headline)
      .foregroundStyle(store.canMutateTasks ? LorvexDesign.Palette.accent : Color.secondary)
    }
    .disabled(!store.canMutateTasks)
    .buttonStyle(.bordered)
    .tint(LorvexDesign.Palette.accent)
    .accessibilityHint(
      isStarted
        ? String(
          format: String(
            localized: "watch.action.pause.hint", defaultValue: "Takes %@ out of the started tasks",
            table: "Localizable", bundle: WatchL10n.bundle), task.title)
        : String(
          format: String(
            localized: "watch.action.start.hint", defaultValue: "Marks %@ as started",
            table: "Localizable", bundle: WatchL10n.bundle), task.title))
    .accessibilityIdentifier("watch.task.actions.startPause")
  }
}
