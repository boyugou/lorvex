import SwiftUI

/// The global quick-capture sheet — raised by the ＋ on Today / Tasks (and ⌘N).
/// Capture is an action, not a destination, so it lives in a sheet with the
/// native dismiss idiom rather than occupying a primary tab.
struct MobileStoreCaptureSheet: View {
  @Bindable var store: MobileStore

  var body: some View {
    NavigationStack {
      Form {
        MobileCaptureSections(
          draft: $store.captureDraft,
          isCapturing: store.isCapturing
        ) {
          await store.submitCaptureDraft()
        }
      }
      // Long capture form with multi-line notes: let the user swipe the scroll to
      // dismiss the keyboard. `scrollDismissesKeyboard` is unavailable on visionOS.
      #if !os(visionOS)
        .scrollDismissesKeyboard(.interactively)
      #endif
      .navigationTitle(
        String(
          localized: "capture.sheet.title", defaultValue: "Capture", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(
            String(
              localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
              bundle: MobileL10n.bundle)
          ) {
            store.isPresentingCapture = false
          }
          .accessibilityIdentifier("mobileCapture.cancel")
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }
}
