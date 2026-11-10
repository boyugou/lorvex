import LorvexCore
import SwiftUI

/// Inline quick-add at the top of a task lane: type a line, press Return, and
/// the task is created in place. The field is never disabled and keeps focus
/// across a submit, so consecutive entries flow while the host commits and
/// publishes the previous line; the host serializes those commits.
///
/// The line may carry details ("Call the caterer tomorrow 20 min #offsite").
/// While the user types, `preview` reads them out and the row shows the title
/// it will create and each detail as a tinted word, so what Return does is
/// visible before it happens. The caller owns parsing and creation and answers
/// whether the task was created; a line that was not comes back into the field
/// when nothing has been typed since.
///
/// `focusToken` is the host's quick-add focus signal (`AppStore.quickAddFocusToken`):
/// the New Task command (⌘N) and empty-state capture buttons bump it, and this
/// row claims keyboard focus whenever the value changes. Pass `nil` to opt out
/// (a surface where ⌘N should not steer here).
struct QuickAddRow: View {
  let placeholder: String
  var focusToken: Int? = nil
  let preview: (String) -> LorvexCapturePreview
  let submit: (String) async -> Bool

  @State private var title = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    let current = preview(title)
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      field
      if !current.words.isEmpty {
        QuickAddPreviewLine(preview: current)
          .padding(.leading, QuickAddRowMetrics.previewLeading)
          .transition(.opacity)
      }
    }
    .reduceMotionAnimation(.snappy(duration: 0.18), value: current.words.isEmpty)
    // The panel's horizontal inset equals a task row's inner padding, so in a
    // lane of task rows the plus sits in their marker column and the typed
    // text starts on their title column.
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .lorvexInsetPanel(padding: LorvexDesign.Spacing.s)
    .contentShape(Rectangle())
    .onTapGesture { isFocused = true }
    .onChange(of: focusToken) { _, _ in isFocused = true }
    .accessibilityIdentifier("workspace.quickAdd")
  }

  private var field: some View {
    HStack(spacing: WorkspaceTaskColumns.markerSpacing) {
      Image(systemName: "plus.circle.fill")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.secondary)
        .frame(width: WorkspaceTaskColumns.markerWidth)
        .accessibilityHidden(true)

      TextField(placeholder, text: $title)
        .textFieldStyle(.plain)
        .font(LorvexDesign.Typography.primaryText)
        .focused($isFocused)
        .onSubmit(submitTitle)
        .lorvexSingleLine($title)
        .accessibilityIdentifier("workspace.quickAdd.field")
    }
  }

  /// Clears the field and keeps it focused before handing the line to the
  /// host. Focus is asserted now, not after the host's `await` returns: that
  /// return can trail a sync cycle, and reclaiming focus then would pull the
  /// cursor out of wherever the user went next. A line the host did not create
  /// is put back as text only, with no focus change.
  private func submitTitle() {
    let value = title
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    title = ""
    isFocused = true
    Task {
      let created = await submit(value)
      if let restored = Self.restoredTitle(submitted: value, created: created, current: title) {
        title = restored
      }
    }
  }

  /// The text to put back in the field once the host has answered for
  /// `submitted`, or `nil` to leave the field as it is. A line that was not
  /// created returns only while the field is still empty: the user may already
  /// be typing the next line, and that is never overwritten.
  static func restoredTitle(submitted: String, created: Bool, current: String) -> String? {
    guard !created, current.isEmpty else { return nil }
    return submitted
  }
}

enum QuickAddRowMetrics {
  /// Lines the preview up with the field's text, past the leading plus symbol.
  static let previewLeading = WorkspaceTaskColumns.markerWidth + WorkspaceTaskColumns.markerSpacing
}
