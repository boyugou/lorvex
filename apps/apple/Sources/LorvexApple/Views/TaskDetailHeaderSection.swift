import LorvexCore
import SwiftUI

extension TaskDetailView {
  func headerSection(task: LorvexTask, draftHasChanges: Bool, canSave: Bool) -> some View {
    TaskDetailPanel(accessibilityIdentifier: "task.detail.header.panel", chrome: .header) {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
          TextField(
            String(localized: "task_detail.header.title_placeholder", defaultValue: "Title", table: "Localizable", bundle: LorvexL10n.bundle),
            text: taskTitleBinding(for: task),
            axis: .vertical
          )
            .font(LorvexDesign.Typography.sectionHeader)
            .textFieldStyle(.plain)
            // Start at a single line and grow up to four: a fixed 2-line minimum
            // reserved a permanently-blank second line under every short title.
            .lineLimit(1...4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .focused($titleFieldFocused)
            .accessibilityLabel(String(localized: "task_detail.header.title_a11y", defaultValue: "Task title", table: "Localizable", bundle: LorvexL10n.bundle))
            .accessibilityIdentifier("task.detail.title")

          // The dot reflects *any* unsaved edit, not just savable ones — if the
          // estimate field is mid-edit (invalid) the title/notes changes are still
          // unsaved, so the indicator must show rather than falsely reading "saved".
          // Save only appears once the draft is dirty. It still stays gated on
          // `selectedTaskCanSave`, and invalid fields explain why it's disabled.
          if draftHasChanges {
            Circle()
              .fill(.tint)
              .frame(width: 8, height: 8)
              .padding(.top, 7)
              .accessibilityLabel(Text(LocalizedStringResource("task_detail.unsaved_changes", defaultValue: "Unsaved changes", table: "Localizable", bundle: LorvexL10n.bundle)))
              .accessibilityIdentifier("task.detail.titleUnsavedIndicator")
          }

          pinAsStickyButton(task: task)

          hideInspectorButton
        }

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
            headerMetadataTokens(task: task)
            priorityPicker(task: task)
          }

          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
            headerMetadataTokens(task: task)
            priorityPicker(task: task)
          }
        }
        .accessibilityIdentifier("task.detail.header.metadata")

        headerActions(task: task, draftHasChanges: draftHasChanges, canSave: canSave)
      }
    }
  }

  private func pinAsStickyButton(task: LorvexTask) -> some View {
    Button {
      openWindow(id: LorvexWindowID.stickyTaskGroupID, value: StickyTaskRef(taskID: task.id))
    } label: {
      Label(
        String(localized: "task_detail.pin_sticky", defaultValue: "Pin as Sticky", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "pin"
      )
      .labelStyle(.iconOnly)
    }
    .buttonStyle(.lorvexNeutral)
    .fixedSize(horizontal: true, vertical: false)
    .help(String(
      localized: "task_detail.pin_sticky.help",
      defaultValue: "Open this task in a floating sticky window",
      table: "Localizable",
      bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("task.detail.pinSticky")
  }

  // The shared inspector ✕ (matches the habit and calendar panels); re-clicking
  // the task's row in the list collapses it the same way.
  private var hideInspectorButton: some View {
    InspectorCloseButton(accessibilityIdentifier: "task.detail.inspector.close") {
      store.selectedTaskID = nil
    }
  }

  @ViewBuilder
  private func headerMetadataTokens(task: LorvexTask) -> some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      TaskDetailMetadataToken(
        title: TaskDisplayText.status(task.status),
        systemImage: task.status.statusSymbolName,
        tint: task.status.statusTint
      )

      if let lateness = task.latenessState, !lateness.isEmpty {
        TaskDetailMetadataToken(
          title: Self.displayLateness(lateness),
          systemImage: "exclamationmark.triangle",
          tint: .orange
        )
      }
    }
  }

  /// Short "P1/P2/P3" labels and `fixedSize` keep the segmented control compact
  /// so it never overflows the narrow detail inspector. The full "Priority 1"
  /// wording lives in the accessibility value below.
  private func priorityPicker(task: LorvexTask) -> some View {
    LorvexSegmentedControl(
      options: LorvexTask.Priority.allCases,
      selection: taskPriorityBinding(for: task),
      title: { $0.rawValue },
      accessibilityIdentifier: "task.detail.priorityControl",
      accessibilityLabel: String(
        localized: "task_detail.header.priority", defaultValue: "Priority",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      optionTint: { $0.priorityTint }
    )
    .fixedSize()
    .accessibilityValue(TaskDisplayText.priority(displayPriority(for: task)))
  }

  /// The header can render before `TaskDetailView.onAppear`/selection-change
  /// has hydrated the draft for the newly selected task. In that short window,
  /// read from the current task so the inspector never shows stale blank
  /// placeholders like "Title" or the default P2 for a real selected task.
  func taskTitleBinding(for task: LorvexTask) -> Binding<String> {
    Binding {
      store.taskDetailDraftTaskID == task.id ? store.taskDetailTitle : task.title
    } set: { newValue in
      // No draft sync here: hydration happens on appear / selection change. A
      // force-sync inside the setter reset every draft field on each keystroke,
      // forcing a heavy re-render that jumped the caret.
      store.taskDetailTitle = newValue
    }
  }

  func taskPriorityBinding(for task: LorvexTask) -> Binding<LorvexTask.Priority> {
    Binding {
      displayPriority(for: task)
    } set: { newValue in
      store.taskDetailPriority = newValue
    }
  }

  /// Identity-guarded notes binding, mirroring ``taskTitleBinding(for:)``. Until
  /// the draft re-hydrates for the newly selected task, read the task's own notes
  /// rather than the prior task's draft — otherwise the editor briefly shows (and
  /// fast typing could mis-save onto) the previous selection's notes.
  func taskNotesBinding(for task: LorvexTask) -> Binding<String> {
    Binding {
      store.taskDetailDraftTaskID == task.id ? store.taskDetailNotes : task.notes
    } set: { newValue in
      store.taskDetailNotes = newValue
    }
  }

  /// Identity-guarded tags binding, mirroring ``taskTitleBinding(for:)``.
  func taskTagsBinding(for task: LorvexTask) -> Binding<String> {
    Binding {
      store.taskDetailDraftTaskID == task.id
        ? store.taskDetailTagsText : task.tags.joined(separator: ", ")
    } set: { newValue in
      store.taskDetailTagsText = newValue
    }
  }

  private func displayPriority(for task: LorvexTask) -> LorvexTask.Priority {
    store.taskDetailDraftTaskID == task.id ? store.taskDetailPriority : task.priority
  }

  private static func displayLateness(_ rawValue: String) -> String {
    switch rawValue {
    case "past_planned":
      String(
        localized: "task_detail.lateness.past_planned",
        defaultValue: "Past planned date",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case "overdue_unhandled":
      String(
        localized: "task_detail.lateness.overdue_unhandled",
        defaultValue: "Overdue",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    case "overdue_acknowledged":
      String(
        localized: "task_detail.lateness.overdue_acknowledged",
        defaultValue: "Overdue acknowledged",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      )
    default:
      rawValue
        .split(separator: "_")
        .map { part in
          part.prefix(1).uppercased() + String(part.dropFirst())
        }
        .joined(separator: " ")
    }
  }
}

private struct TaskDetailMetadataToken: View {
  let title: String
  let systemImage: String
  let tint: Color

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: systemImage)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      Text(title)
        .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .accessibilityLabel(title)
  }
}
