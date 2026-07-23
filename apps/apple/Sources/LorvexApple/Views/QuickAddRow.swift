import LorvexCore
import SwiftUI

/// Inline quick-add at the top of a task lane: type a title, press Return, and
/// the task is created in place — the caller decides where it lands (a list,
/// today's plan). Focus stays in the field after each submit so consecutive
/// entries flow — the capture pattern every peer task manager leads its lists
/// with.
///
/// `focusToken` is the host's quick-add focus signal (`AppStore.quickAddFocusToken`):
/// the New Task command (⌘N) and empty-state capture buttons bump it, and this
/// row claims keyboard focus whenever the value changes. Pass `nil` to opt out
/// (a surface where ⌘N should not steer here).
struct QuickAddRow: View {
  let placeholder: String
  let isCreating: Bool
  var focusToken: Int? = nil
  let submit: (String) async -> Void

  @State private var title = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "plus.circle.fill")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      TextField(placeholder, text: $title)
        .textFieldStyle(.plain)
        .font(LorvexDesign.Typography.primaryText)
        .focused($isFocused)
        .onSubmit(submitTitle)
        .disabled(isCreating)
        .accessibilityIdentifier("workspace.quickAdd.field")
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .contentShape(Rectangle())
    .onTapGesture { isFocused = true }
    .onChange(of: focusToken) { _, _ in isFocused = true }
    .accessibilityIdentifier("workspace.quickAdd")
  }

  private func submitTitle() {
    let value = title
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    title = ""
    Task {
      await submit(value)
      isFocused = true
    }
  }
}
