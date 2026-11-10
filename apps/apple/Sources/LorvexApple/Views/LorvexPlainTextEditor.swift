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
///
/// By default the editor takes the height its container gives it, at least
/// `minHeight`, and scrolls text that does not fit. With `growsWithContent` it
/// is as tall as its text (between `minHeight` and `maxHeight`), for an editor
/// inside a page that scrolls: all of the text shows, and nothing hides below
/// an edge that has no scroll bar to say so.
struct LorvexPlainTextEditor: View {
  @Binding var text: String
  var placeholder: String = ""
  var minHeight: CGFloat = 80
  var maxHeight: CGFloat?
  var fontSize: CGFloat = 13
  var growsWithContent = false
  var onFocusChange: @MainActor @Sendable (Bool) -> Void = { _ in }

  /// The height the text takes at the editor's width, as the text view last
  /// laid it out; zero until its first layout.
  @State private var contentHeight: CGFloat = 0

  var body: some View {
    ZStack(alignment: .topLeading) {
      editor
      if text.isEmpty && !placeholder.isEmpty {
        Text(placeholder)
          // Must track the caller-supplied `fontSize` exactly: this overlay only
          // stands in for the AppKit `NSTextView` below, whose real font is set
          // to the same `fontSize`, so a fixed typography token here would
          // desync the placeholder's size from the actual typed text.
          .font(.system(size: fontSize))  // lorvex-design-token: allow
          .foregroundStyle(LorvexDesign.Palette.placeholderText)
          .padding(.top, 1)
          .allowsHitTesting(false)
          // The text view carries the placeholder as its accessibility
          // placeholder value; this copy would be a stop of its own.
          .accessibilityHidden(true)
      }
    }
  }

  @ViewBuilder
  private var editor: some View {
    if growsWithContent {
      PlainTextNSEditor(
        text: $text, placeholder: placeholder, fontSize: fontSize, onFocusChange: onFocusChange,
        onContentHeightChange: { contentHeight = $0 }
      )
      .frame(
        height: Self.fittedHeight(
          contentHeight: contentHeight, minHeight: minHeight, maxHeight: maxHeight))
    } else {
      PlainTextNSEditor(
        text: $text, placeholder: placeholder, fontSize: fontSize, onFocusChange: onFocusChange,
        onContentHeightChange: nil
      )
      .frame(minHeight: minHeight, maxHeight: maxHeight)
    }
  }

  /// A growing editor's height: its text's height, no less than `minHeight`
  /// and no more than `maxHeight` when one is set.
  static func fittedHeight(
    contentHeight: CGFloat, minHeight: CGFloat, maxHeight: CGFloat?
  ) -> CGFloat {
    max(minHeight, min(contentHeight, maxHeight ?? .greatestFiniteMagnitude))
  }
}

/// The height `textView`'s text takes at its current width, insets included,
/// from the layout the text view itself made; zero while it has no width.
@MainActor
func plainTextEditorContentHeight(of textView: NSTextView) -> CGFloat {
  guard textView.bounds.width > 0 else { return 0 }
  let insets = textView.textContainerInset.height * 2
  if let layout = textView.textLayoutManager {
    layout.ensureLayout(for: layout.documentRange)
    return ceil(layout.usageBoundsForTextContainer.height) + insets
  }
  guard let layout = textView.layoutManager, let container = textView.textContainer else {
    return 0
  }
  layout.ensureLayout(for: container)
  return ceil(layout.usedRect(for: container).height) + insets
}

/// A scroll view that hands a scroll gesture to the view behind it while its
/// own document fits, so an editor inside a scrolling page never holds the
/// page still under the pointer.
private final class PlainTextScrollView: NSScrollView {
  override func scrollWheel(with event: NSEvent) {
    let documentHeight = documentView?.frame.height ?? 0
    if documentHeight <= contentSize.height + 0.5 {
      nextResponder?.scrollWheel(with: event)
    } else {
      super.scrollWheel(with: event)
    }
  }
}

private struct PlainTextNSEditor: NSViewRepresentable {
  @Binding var text: String
  var placeholder: String
  var fontSize: CGFloat
  var onFocusChange: @MainActor @Sendable (Bool) -> Void
  /// Receives the text's height whenever its layout changes it; nil for an
  /// editor that does not grow.
  var onContentHeightChange: (@MainActor (CGFloat) -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(
      text: $text, onFocusChange: onFocusChange, onContentHeightChange: onContentHeightChange)
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
    textView.setAccessibilityPlaceholderValue(placeholder)

    let scroll = PlainTextScrollView()
    scroll.documentView = textView
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = false
    scroll.hasHorizontalScroller = false
    if onContentHeightChange != nil {
      // A change of width rewraps the text, which changes its height.
      textView.postsFrameChangedNotifications = true
      context.coordinator.observeFrame(of: textView)
    }
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let textView = scroll.documentView as? NSTextView else { return }
    context.coordinator.onFocusChange = onFocusChange
    if textView.accessibilityPlaceholderValue() != placeholder {
      textView.setAccessibilityPlaceholderValue(placeholder)
    }
    // Only push external changes (e.g. a draft sync) into the view; never while
    // the user is the source of the change, to avoid fighting the caret.
    if textView.string != text {
      textView.string = text
    }
    if textView.font?.pointSize != fontSize {
      textView.font = .systemFont(ofSize: fontSize)
    }
    context.coordinator.onContentHeightChange = onContentHeightChange
    context.coordinator.reportContentHeight(of: textView)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    private let text: Binding<String>
    var onFocusChange: @MainActor @Sendable (Bool) -> Void
    var onContentHeightChange: (@MainActor (CGFloat) -> Void)?
    private var reportedContentHeight: CGFloat = -1

    init(
      text: Binding<String>,
      onFocusChange: @escaping @MainActor @Sendable (Bool) -> Void,
      onContentHeightChange: (@MainActor (CGFloat) -> Void)?
    ) {
      self.text = text
      self.onFocusChange = onFocusChange
      self.onContentHeightChange = onContentHeightChange
    }

    /// Watches `textView`'s frame. The center drops a selector observer when
    /// it is deallocated, so nothing has to remove this one.
    func observeFrame(of textView: NSTextView) {
      NotificationCenter.default.addObserver(
        self, selector: #selector(textViewFrameDidChange(_:)),
        name: NSView.frameDidChangeNotification, object: textView)
    }

    @objc @MainActor
    private func textViewFrameDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      reportContentHeight(of: textView)
    }

    /// Hands a changed text height to the editor. The hand-off waits a turn:
    /// this runs inside a view update or a layout pass, where SwiftUI state
    /// cannot change.
    @MainActor
    func reportContentHeight(of textView: NSTextView) {
      guard let onContentHeightChange else { return }
      let height = plainTextEditorContentHeight(of: textView)
      guard height > 0, abs(height - reportedContentHeight) > 0.5 else { return }
      reportedContentHeight = height
      Task { @MainActor in onContentHeightChange(height) }
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
      MainActor.assumeIsolated { reportContentHeight(of: textView) }
    }
  }
}
