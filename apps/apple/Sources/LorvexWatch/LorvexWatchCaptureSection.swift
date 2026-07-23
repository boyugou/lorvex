import SwiftUI
#if os(watchOS)
  import WatchKit
#endif

struct LorvexWatchCaptureSection: View {
  @Bindable var store: LorvexWatchStore

  var body: some View {
    Section(String(
      localized: "watch.section.capture", defaultValue: "Capture",
      table: "Localizable", bundle: WatchL10n.bundle)) {
      TextField(String(
        localized: "watch.capture.placeholder", defaultValue: "New task",
        table: "Localizable", bundle: WatchL10n.bundle), text: $store.captureTitle)
        #if os(watchOS)
        .textInputAutocapitalization(.sentences)
        #endif
        .disabled(store.captureUnavailableReason != nil)
        .accessibilityLabel(String(
          localized: "watch.capture.title.a11y", defaultValue: "New task title",
          table: "Localizable", bundle: WatchL10n.bundle))
        .accessibilityIdentifier("watch.capture.title")

      Button {
        Task {
          await store.captureTask()
          #if os(watchOS)
          WKInterfaceDevice.current().play(store.error == nil ? .success : .failure)
          #endif
        }
      } label: {
        Label(store.isLoading
                ? String(
                  localized: "watch.capture.capturing", defaultValue: "Capturing",
                  table: "Localizable", bundle: WatchL10n.bundle)
                : String(
                  localized: "watch.capture.submit", defaultValue: "Capture",
                  table: "Localizable", bundle: WatchL10n.bundle),
              systemImage: "plus.circle.fill")
          .font(.headline)
      }
      .disabled(!store.canCaptureTask)
      .accessibilityLabel(String(
        localized: "watch.capture.submit.a11y", defaultValue: "Capture task",
        table: "Localizable", bundle: WatchL10n.bundle))
      .accessibilityIdentifier("watch.capture.submit")

      if let title = store.pendingCaptureTitle {
        Label(title, systemImage: "clock.arrow.circlepath")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .accessibilityLabel(String(format: String(
            localized: "watch.capture.pending.a11y", defaultValue: "Pending task: %@",
            table: "Localizable", bundle: WatchL10n.bundle), title))
      } else if let reason = store.captureUnavailableReason {
        Text(reason)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}
