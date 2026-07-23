import SwiftUI

/// Empty-state for task lists that funnels the user into capture rather than
/// dead-ending on a bare "No tasks" label. Lorvex is AI-first — the human's
/// fastest path is to capture a task (or let the assistant plan), so the empty
/// state surfaces a prominent Capture button that raises the quick-capture sheet.
struct MobileStoreTaskEmptyState: View {
  @Bindable var store: MobileStore
  var title: String = String(
    localized: "tasks.empty.title", defaultValue: "No Open Tasks", table: "Localizable",
    bundle: MobileL10n.bundle)
  var message: String = String(
    localized: "tasks.empty.message",
    defaultValue: "Capture a task to get started — or ask your AI assistant to plan your day.",
    table: "Localizable", bundle: MobileL10n.bundle)

  var body: some View {
    // A bounded inline empty-state — never a ContentUnavailableView in a List row
    // (that inflates to unbounded height and stretches the action into a bar). No
    // action button: the global ＋ already owns "add a task", so a second Capture
    // button here is redundant (and nonsensical on the Completed / Cancelled tabs).
    MobileEmptyState(
      icon: "checkmark.circle",
      title: title,
      message: message
    )
    .accessibilityIdentifier("mobileEmptyState.tasks")
  }
}
