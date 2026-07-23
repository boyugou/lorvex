import AppKit
import LorvexCore
import SwiftUI

/// The app's standard multi-line plain-text editor.
///
/// Wraps `NSTextView` directly instead of SwiftUI's `TextEditor` / a
/// `TextField(axis: .vertical)`. Those have intermittent macOS bugs where an
/// edit (notably deleting to empty) is not committed to the binding and the
/// field reverts to a stale value on focus change, and where a computed binding
/// causes the caret to jump. The AppKit text view commits every change through
/// its delegate — including clearing the field — so editing is reliable. The
/// scroll bar is suppressed for a calm surface; scrolling still works.
struct LorvexPlainTextEditor: View {
  @Binding var text: String
  var placeholder: String = ""
  var minHeight: CGFloat = 80
  var maxHeight: CGFloat?
  var fontSize: CGFloat = 13
  var onFocusChange: @MainActor @Sendable (Bool) -> Void = { _ in }

  var body: some View {
    ZStack(alignment: .topLeading) {
      PlainTextNSEditor(text: $text, fontSize: fontSize, onFocusChange: onFocusChange)
        .frame(minHeight: minHeight, maxHeight: maxHeight)
      if text.isEmpty && !placeholder.isEmpty {
        Text(placeholder)
          .font(.system(size: fontSize))
          .foregroundStyle(.tertiary)
          .padding(.top, 1)
          .allowsHitTesting(false)
      }
    }
  }
}

private struct PlainTextNSEditor: NSViewRepresentable {
  @Binding var text: String
  var fontSize: CGFloat
  var onFocusChange: @MainActor @Sendable (Bool) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, onFocusChange: onFocusChange)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = NSTextView()
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.font = .systemFont(ofSize: fontSize)
    textView.textContainerInset = NSSize(width: 0, height: 2)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    // Plain prose: don't let smart quotes / dashes rewrite what the user typed.
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.string = text

    let scroll = NSScrollView()
    scroll.documentView = textView
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = false
    scroll.hasHorizontalScroller = false
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let textView = scroll.documentView as? NSTextView else { return }
    context.coordinator.onFocusChange = onFocusChange
    // Only push external changes (e.g. a draft sync) into the view; never while
    // the user is the source of the change, to avoid fighting the caret.
    if textView.string != text {
      textView.string = text
    }
    if textView.font?.pointSize != fontSize {
      textView.font = .systemFont(ofSize: fontSize)
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    private let text: Binding<String>
    var onFocusChange: @MainActor @Sendable (Bool) -> Void

    init(text: Binding<String>, onFocusChange: @escaping @MainActor @Sendable (Bool) -> Void) {
      self.text = text
      self.onFocusChange = onFocusChange
    }

    func textDidBeginEditing(_ notification: Notification) {
      Task { @MainActor in onFocusChange(true) }
    }

    func textDidEndEditing(_ notification: Notification) {
      Task { @MainActor in onFocusChange(false) }
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }
  }
}
