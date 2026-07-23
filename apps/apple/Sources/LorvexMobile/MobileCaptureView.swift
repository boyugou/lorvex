import LorvexCore
import SwiftUI

struct MobileCaptureSections: View {
  @Binding var draft: MobileCaptureDraft
  let isCapturing: Bool
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
      .accessibilityLabel(
        String(
          localized: "capture.title.a11y", defaultValue: "Task title", table: "Localizable",
          bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("mobileCapture.title")
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
      // Surface the quick-capture model: dump many, let the assistant organize.
      Text(
        String(
          localized: "capture.footer.hint",
          defaultValue:
            "Capture one task per line — your assistant sorts the priorities, dates, and lists.",
          table: "Localizable", bundle: MobileL10n.bundle))
    }

    Section {
      Button {
        submit()
      } label: {
        if isCapturing {
          Label {
            Text(
              String(
                localized: "capture.capturing", defaultValue: "Capturing", table: "Localizable",
                bundle: MobileL10n.bundle))
          } icon: {
            // White to read on the prominent (accent) button fill, matching the
            // label text; a spinning ProgressView instead of a static glyph.
            ProgressView().tint(.white)
          }
          .frame(maxWidth: .infinity)
        } else {
          Label(
            String(
              localized: "capture.capture", defaultValue: "Capture", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "plus.circle.fill"
          )
          .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!draft.canSubmit || isCapturing)
      .accessibilityLabel(
        isCapturing
          ? String(
            localized: "capture.capturing_task.a11y", defaultValue: "Capturing task",
            table: "Localizable", bundle: MobileL10n.bundle)
          : String(
            localized: "capture.capture_task.a11y", defaultValue: "Capture task",
            table: "Localizable", bundle: MobileL10n.bundle)
      )
      .accessibilityIdentifier("mobileCapture.confirm")
      .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
  }

  private func submit() {
    Task {
      await onSubmit?()
    }
  }
}
