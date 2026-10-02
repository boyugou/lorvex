import LorvexCore
import SwiftUI

struct MobileCaptureSections: View {
  @Binding var draft: MobileCaptureDraft
  let isCapturing: Bool
  /// Reads the details out of a single typed line for the preview under the
  /// title; several lines are previewed only by the footer hint.
  let preview: (String) -> LorvexCapturePreview
  let onSubmit: (() async -> Void)?
  @FocusState private var focusedField: Field?

  private enum Field {
    case title
    case notes
  }

  var body: some View {
    Section {
      TextField(
        String(
          localized: "capture.title_placeholder", defaultValue: "Title", table: "Localizable",
          bundle: MobileL10n.bundle), text: $draft.title, axis: .vertical
      )
      .font(.title3)
      .lineLimit(1...4)
      .focused($focusedField, equals: .title)
      .submitLabel(.next)
      .onSubmit { focusedField = .notes }
      // Quick capture is a typing task; start in the title so the sheet needs
      // no first tap.
      .onAppear { focusedField = .title }
      .accessibilityLabel(
        String(
          localized: "capture.title.a11y", defaultValue: "Task title", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("mobileCapture.title")
      if draft.parsedTitles.count <= 1 {
        let current = preview(draft.title)
        if !current.words.isEmpty {
          MobileCapturePreviewLine(preview: current)
            .transition(.opacity)
        }
      }
      MobilePlainTextEditor(
        text: $draft.notes,
        placeholder: String(
          localized: "capture.notes_placeholder", defaultValue: "Notes", table: "Localizable",
          bundle: MobileL10n.bundle),
        minHeight: 72
      )
      .focused($focusedField, equals: .notes)
      .submitLabel(.done)
      .onSubmit { submit() }
      .accessibilityLabel(
        String(
          localized: "capture.notes.a11y", defaultValue: "Task notes", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("mobileCapture.notes")
    } footer: {
      // Surface the capture vocabulary: one task per line, details in words.
      Text(
        String(
          localized: "capture.footer.words",
          defaultValue:
            "One task per line. Words like “tomorrow”, “3pm”, “every Monday”, “20 min”, or “#list” fill in its details.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }
  }

  private func submit() {
    Task {
      await onSubmit?()
    }
  }
}
