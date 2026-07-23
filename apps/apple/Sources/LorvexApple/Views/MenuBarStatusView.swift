import LorvexCore
import SwiftUI

/// The menu-bar quick panel (rendered as a `.window`-style `MenuBarExtra`): a
/// compact today HUD with a date header and attention stats, an inline
/// quick-add, the next-up task list with one-click completion, and a footer to
/// jump into the app.
struct MenuBarStatusView: View {
  @Bindable var store: AppStore
  @Environment(\.openWindow) private var openWindow
  /// Claimed when the panel opens so the user can type a capture immediately.
  @FocusState private var quickAddFocused: Bool
  /// The menu-bar capture's own draft, kept separate from the shared
  /// `store.draftTitle` so half-typed text here doesn't bleed into the main
  /// window's Quick Capture (and vice versa).
  @State private var quickAddText = ""

  private static let maxRows = 6

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, LorvexDesign.Spacing.m)
        .padding(.top, LorvexDesign.Spacing.m)
        .padding(.bottom, LorvexDesign.Spacing.s)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
          quickAdd
          taskList
        }
        .padding(LorvexDesign.Spacing.m)
      }
      .frame(maxHeight: 340)

      Divider()

      footer
        .padding(LorvexDesign.Spacing.s)
    }
    .frame(width: 320)
    .tint(.accentColor)
    .task {
      quickAddFocused = false
      await Task.yield()
      quickAddFocused = true
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
      Text(Self.dateFormatter.string(from: Date()))
        .font(.system(.title3, design: .rounded).weight(.semibold))
        .foregroundStyle(.primary)

      Spacer(minLength: 0)

      if attentionCount > 0 {
        Text(MenuBarStatusCopy.dueText(attentionCount))
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.orange)
          .padding(.horizontal, LorvexDesign.Spacing.s)
          .padding(.vertical, 3)
          .background(Color.orange.opacity(0.14), in: Capsule())
          .accessibilityLabel(MenuBarStatusCopy.dueText(attentionCount))
      }
    }
  }

  // MARK: - Quick add

  /// One field: type a title and press Return to capture a task into the inbox.
  /// No notes field and no separate button — the lightest possible capture.
  private var quickAdd: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "plus.circle.fill")
        .foregroundStyle(.tint)
      TextField(
        String(
          localized: "menubar.quick_add", defaultValue: "Add a task, then press Return",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        text: $quickAddText
      )
      .textFieldStyle(.plain)
      .font(LorvexDesign.Typography.secondaryText)
      .focused($quickAddFocused)
      .onSubmit { submitQuickAdd() }
      .accessibilityIdentifier("menubar.quickAdd")
    }
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, 6)
    .background(.quaternary.opacity(0.5), in: Capsule())
  }

  /// Capture the typed title directly (like the command palette) rather than
  /// routing through the shared `store.draftTitle` draft, then clear the field.
  private func submitQuickAdd() {
    let title = quickAddText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    quickAddText = ""
    Task { await store.createTask(title: title, notes: "") }
  }

  // MARK: - Task list

  private var nextUp: [LorvexTask] {
    Array(store.today.tasks.filter { $0.status.isActionable }
      .prefix(Self.maxRows))
  }

  @ViewBuilder
  private var taskList: some View {
    if nextUp.isEmpty {
      MenuBarAllClear()
    } else {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
        Text(LocalizedStringResource("menubar.section.next_up", defaultValue: "Next Up", table: "Localizable", bundle: LorvexL10n.bundle))
          .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
          .foregroundStyle(.secondary)
          .textCase(.uppercase)

        ForEach(nextUp) { task in
          MenuBarTaskRow(
            task: task,
            today: store.logicalTodayDateString,
            complete: { Task { await store.menuBarCompleteTask(task) } },
            open: {
              store.selectedTaskID = task.id
              perform(.openMain)
            }
          )
        }
      }
    }
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        perform(.openMain)
      } label: {
        Label(
          String(localized: "menubar.action.open_app", defaultValue: "Open Lorvex", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "arrow.up.forward.app")
      }
      .buttonStyle(.borderless)

      Spacer(minLength: 0)

      footerIcon(.refresh, "arrow.clockwise")
      footerIcon(.quit, "power")
    }
  }

  private func footerIcon(_ action: MenuBarStatusAction, _ systemImage: String) -> some View {
    Button {
      perform(action)
    } label: {
      Image(systemName: systemImage)
        .frame(width: 18, height: 18)
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
    .help(action.title)
    .accessibilityLabel(action.title)
    .accessibilityIdentifier("menubar.action.\(action)")
  }

  // MARK: - Helpers

  private var attentionCount: Int { store.menuBarAttentionCount }

  private func perform(_ action: MenuBarStatusAction) {
    LorvexCommandDispatcher(
      store: store,
      openWindow: { windowID in openWindow(windowID) },
      activateApplication: { NSApp.activate() },
      terminateApplication: { NSApplication.shared.terminate(nil) }
    )
    .perform(action.commandAction)
  }

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
    return f
  }()

}

/// One task line in the menu-bar panel: a large completion circle, the title,
/// and a quiet trailing due/priority hint. Clicking the title opens the task in
/// the main window; clicking the circle completes it in place.
private struct MenuBarTaskRow: View {
  let task: LorvexTask
  let today: String
  let complete: () -> Void
  let open: () -> Void

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button(action: complete) {
        Image(systemName: "circle")
          .font(.system(size: 17))
          .foregroundStyle(priorityTint)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help(String(localized: "menubar.row.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(
        format: String(localized: "menubar.row.complete_a11y", defaultValue: "Complete %@", table: "Localizable", bundle: LorvexL10n.bundle),
        task.title))

      Button(action: open) {
        Text(task.title)
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if let due = dueHint {
        Text(due.text)
          .font(LorvexDesign.Typography.tertiaryText.weight(.medium).monospacedDigit())
          .foregroundStyle(due.overdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
          .fixedSize()
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var priorityTint: Color {
    switch task.priority {
    case .p1: return .red
    case .p2: return .orange
    default: return .secondary
    }
  }

  private var dueHint: (text: String, overdue: Bool)? {
    guard let dueDate = task.dueDate else { return nil }
    let dueYmd = LorvexDateFormatters.ymdUTC.string(from: dueDate)
    if dueYmd < today {
      return (String(localized: "menubar.row.overdue", defaultValue: "Overdue", table: "Localizable", bundle: LorvexL10n.bundle), true)
    }
    if dueYmd == today {
      return (String(localized: "menubar.row.due_today", defaultValue: "Today", table: "Localizable", bundle: LorvexL10n.bundle), false)
    }
    return (LorvexMonthDayFormatter.utc.string(from: dueDate), false)
  }
}

/// Empty-state for the menu-bar panel when nothing is due.
private struct MenuBarAllClear: View {
  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
      Text(LocalizedStringResource("menubar.all_clear", defaultValue: "All clear — nothing due.", table: "Localizable", bundle: LorvexL10n.bundle))
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, LorvexDesign.Spacing.s)
  }
}
