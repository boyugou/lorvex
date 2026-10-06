import LorvexCore
import SwiftUI

/// The Quick Capture window's content: one field, the details it reads out of
/// the line (the same words the menu bar's field and the quick-add rows show),
/// and, once the task is written, where it landed.
///
/// The card floats on Liquid Glass; the window around it is transparent and
/// carries the margin its shadow needs. `onSizeChange` reports the size the
/// content wants (card and margin) so the window can fit it as the preview line
/// comes and goes.
struct QuickCaptureCard: View {
  @Bindable var model: QuickCaptureModel
  var onSizeChange: (CGSize) -> Void = { _ in }

  @FocusState private var fieldFocused: Bool
  @State private var selection: TextSelection?

  var body: some View {
    let preview = model.preview()
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      switch model.phase {
      case .captured(let listName):
        confirmation(listName: listName)
      case .editing, .failed:
        field
        if case .failed(let message) = model.phase, !message.isEmpty {
          failure(message)
        } else if !preview.words.isEmpty {
          QuickAddPreviewLine(preview: preview)
            .padding(.leading, QuickCaptureMetrics.detailsLeading)
        }
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(width: QuickCaptureMetrics.cardWidth, alignment: .leading)
    .lorvexFloatingGlass(
      in: RoundedRectangle(cornerRadius: QuickCaptureMetrics.cornerRadius, style: .continuous)
    )
    .padding(QuickCaptureMetrics.shadowMargin)
    .onGeometryChange(for: CGSize.self, of: { $0.size }, action: onSizeChange)
    .onChange(of: model.focusRequest) { focusField() }
    .onChange(of: fieldFocused) { _, focused in
      if focused { placeCaretAtEnd() }
    }
    .task { focusField() }
    .onExitCommand { model.cancel() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(QuickCaptureCopy.windowTitle)
  }

  private func focusField() {
    fieldFocused = true
    placeCaretAtEnd()
  }

  /// Puts the caret after the last character. A line kept from a dismissed
  /// presentation is continued, not selected, so the next keystroke does not
  /// replace it. AppKit selects a field's whole text as it takes focus, so the
  /// caret is placed again once the focus has landed.
  private func placeCaretAtEnd() {
    selection = TextSelection(insertionPoint: model.text.endIndex)
  }

  private var field: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "plus.circle.fill")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.tint)
        .frame(width: QuickCaptureMetrics.iconWidth)
        .accessibilityHidden(true)
      TextField(QuickCaptureCopy.placeholder, text: $model.text, selection: $selection)
        .textFieldStyle(.plain)
        .font(LorvexDesign.Typography.primaryText)
        .focused($fieldFocused)
        .onSubmit { Task { await model.submit() } }
        .lorvexSingleLine($model.text)
        .accessibilityIdentifier("quickCapture.field")
    }
  }

  private func confirmation(listName: String) -> some View {
    let message = AppStore.captureToastMessage(count: 1, listName: listName)
    return HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "checkmark.circle.fill")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(LorvexDesign.Palette.done)
        .frame(width: QuickCaptureMetrics.iconWidth)
        .accessibilityHidden(true)
      Text(message)
        .font(LorvexDesign.Typography.primaryText)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .onAppear { AccessibilityNotification.Announcement(message).post() }
    .accessibilityIdentifier("quickCapture.confirmation")
  }

  private func failure(_ message: String) -> some View {
    Text(message)
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(LorvexDesign.Palette.overdue)
      .padding(.leading, QuickCaptureMetrics.detailsLeading)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("quickCapture.failure")
  }
}

/// The window's measurements.
enum QuickCaptureMetrics {
  /// The glass card's width.
  static let cardWidth: CGFloat = 520
  static let cornerRadius: CGFloat = LorvexDesign.Radius.m * 2
  /// Transparent room around the card for the glass's shadow.
  static let shadowMargin: CGFloat = LorvexDesign.Spacing.l
  /// The leading symbol's column.
  static let iconWidth: CGFloat = 20
  /// Lines the details up with the field's text, past the leading symbol.
  static let detailsLeading = iconWidth + LorvexDesign.Spacing.s
  /// How far down the screen's usable area the window's top edge hangs.
  static let topInsetFraction: CGFloat = 0.2
}

/// The window's own strings; the field's prompt is the menu bar field's.
enum QuickCaptureCopy {
  /// The window's name, for VoiceOver and the window list: the command's.
  static var windowTitle: String { AppCommand.quickCapture.title }

  static var placeholder: String {
    String(
      localized: "menubar.quick_add", defaultValue: "Add a task, then press Return",
      table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
