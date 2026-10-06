import SwiftUI

/// The global quick-capture sheet — raised by the ＋ on Today / Tasks (and ⌘N).
/// Capture is an action, not a destination, so it lives in a sheet with the
/// native Cancel / Capture bar actions rather than occupying a primary tab.
struct MobileStoreCaptureSheet: View {
  @Bindable var store: MobileStore
  /// True when the presenting window is regular width, where the sheet shows as
  /// a card. The sheet's own size class reads compact there, so the presenter
  /// passes it in.
  var showsAsCard = false

  /// Points the form needs as a card at the default text size: the title and a
  /// two-line preview, the notes box, and the hint under it in a script whose
  /// lines run tall, such as Telugu.
  private static let cardHeight: CGFloat = 480

  var body: some View {
    NavigationStack {
      Form {
        MobileCaptureSections(
          draft: $store.captureDraft,
          isCapturing: store.isCapturing,
          preview: store.capturePreview
        ) {
          await store.submitCaptureDraft()
        }
      }
      // Long capture form with multi-line notes: let the user swipe the scroll to
      // dismiss the keyboard.
      .scrollDismissesKeyboard(.interactively)
      .mobileSheetTitle(
        String(
          localized: "capture.sheet.title", defaultValue: "Capture", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
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
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await store.submitCaptureDraft() }
          } label: {
            if store.isCapturing {
              ProgressView().tint(.white)
            } else {
              Text(
                String(
                  localized: "common.add", defaultValue: "Add", table: "Localizable",
                  bundle: MobileL10n.bundle))
            }
          }
          .mobileProminentToolbarButtonStyle()
          .disabled(!store.captureDraft.canSubmit || store.isCapturing)
          .accessibilityLabel(
            store.isCapturing
              ? String(
                localized: "capture.capturing_task.a11y", defaultValue: "Capturing task",
                table: "Localizable", bundle: MobileL10n.bundle)
              : String(
                localized: "capture.capture_task.a11y", defaultValue: "Capture task",
                table: "Localizable", bundle: MobileL10n.bundle)
          )
          .accessibilityIdentifier("mobileCapture.confirm")
        }
      }
    }
    .mobileCompactEditorSheetPresentation(cardHeight: showsAsCard ? Self.cardHeight : nil)
  }
}
