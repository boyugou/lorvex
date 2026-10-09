import LorvexCore
import LorvexDomain
import LorvexMarkdownUI
import SwiftUI

extension TaskDetailView {
  func notesSection(task: LorvexTask) -> some View {
    // Task notes are short and edited inline — a calm single editing field, not
    // a three-way Edit / Preview / Split mode switcher (that belonged to the
    // heavier standalone notes surface). Assistant context is rendered separately.
    let notes = taskNotesBinding(for: task)
    return TaskDetailNotesPanel(notes: notes, characterCount: notes.wrappedValue.count)
  }

  func aiNotesContent(task: LorvexTask) -> some View {
    TaskDetailAINotesPanel(
      aiNotes: task.aiNotes,
      clear: { Task { await store.clearSelectedTaskAINotes() } }
    )
  }
}

private struct TaskDetailAINotesPanel: View {
  let aiNotes: String?
  let clear: () -> Void
  @State private var confirmClear = false

  var body: some View {
    InspectorPanel(accessibilityIdentifier: "task.detail.aiNotes.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
        if let aiNotes, !aiNotes.isEmpty {
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
            HStack(alignment: .center, spacing: LorvexDesign.Spacing.s) {
              Text(LocalizedStringResource(
                "task_detail.ai_notes.context_label",
                defaultValue: "Assistant Context",
                table: "Localizable",
                bundle: LorvexL10n.bundle
              ))
              .font(LorvexDesign.Typography.tertiaryText.weight(.semibold))
              .foregroundStyle(.secondary)
              .accessibilityAddTraits(.isHeader)
              Spacer(minLength: LorvexDesign.Spacing.s)
              Button(role: .destructive) {
                confirmClear = true
              } label: {
                Label(
                  String(
                    localized: "task_detail.ai_notes.clear",
                    defaultValue: "Clear",
                    table: "Localizable",
                    bundle: LorvexL10n.bundle
                  ),
                  systemImage: "trash")
              }
              .buttonStyle(.borderless)
              .controlSize(.small)
              .accessibilityIdentifier("task.detail.aiNotes.clear")
            }
            MarkdownSourceView(aiNotes, taskItemAccessibility: .init(
              completedFormat: String(
                localized: "markdown.task.completed_a11y", defaultValue: "Completed: %@",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              todoFormat: String(
                localized: "markdown.task.todo_a11y", defaultValue: "To do: %@",
                table: "Localizable",
                bundle: LorvexL10n.bundle)))
              .accessibilityIdentifier("task.detail.aiNotes.content")
          }
          .padding(LorvexDesign.Spacing.m)
          .background(
            AnyShapeStyle(.tint.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
        } else {
          HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
            Image(systemName: "sparkles")
              .foregroundStyle(.tint)
            Text(LocalizedStringResource(
              "task_detail.ai_notes.empty",
              defaultValue: "No AI notes yet. Your assistant adds notes here.",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ))
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
          }
          .lorvexInsetPanel(padding: LorvexDesign.Spacing.s)
          .accessibilityIdentifier("task.detail.aiNotes.empty")
        }
      }
    }
    .confirmationDialog(
      String(
        localized: "task_detail.ai_notes.clear_confirm.title",
        defaultValue: "Clear assistant context?",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      isPresented: $confirmClear
    ) {
      Button(
        String(
          localized: "task_detail.ai_notes.clear_confirm.button",
          defaultValue: "Clear Context",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        role: .destructive,
        action: clear
      )
      Button(
        String(localized: "common.cancel", defaultValue: "Cancel", table: "Localizable", bundle: LorvexL10n.bundle),
        role: .cancel
      ) {}
    } message: {
      Text(LocalizedStringResource(
        "task_detail.ai_notes.clear_confirm.message",
        defaultValue: "This removes the assistant-maintained context for this task. The task body and activity history are unchanged.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ))
    }
  }
}

private struct TaskDetailNotesPanel: View {
  @Binding var notes: String
  let characterCount: Int

  /// Within 10% of the body cap — the only zone where a character count
  /// carries information the user can act on.
  private var isApproachingLimit: Bool {
    characterCount >= ValidationLimits.maxBodyLength * 9 / 10
  }

  private var editorMinHeight: CGFloat {
    104
  }

  var body: some View {
    InspectorPanel(accessibilityIdentifier: "task.detail.notes.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          Label(
            String(localized: "task_detail.notes.title", defaultValue: "Notes", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "note.text"
          )
          .labelStyle(.inspectorPanelTitle)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .accessibilityAddTraits(.isHeader)

          Spacer()

          // The count exists to guard the 50k-codepoint body cap, so it only
          // appears once the cap is actually near — an always-on "58 chars"
          // pill is noise that reads as an unexplained UI element.
          if isApproachingLimit {
            Text(
              String(
                localized: "task_detail.notes.character_limit",
                defaultValue: "\(characterCount) / \(ValidationLimits.maxBodyLength) characters",
                table: "Localizable", bundle: LorvexL10n.bundle)
            )
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(
              characterCount >= ValidationLimits.maxBodyLength
                ? AnyShapeStyle(LorvexDesign.Palette.error)
                : AnyShapeStyle(LorvexDesign.Palette.warning))
            .monospacedDigit()
            .padding(.horizontal, LorvexDesign.Spacing.s)
            .padding(.vertical, LorvexDesign.Spacing.xs)
            .background(.quaternary.opacity(0.35), in: Capsule())
            .accessibilityIdentifier("task.detail.notes.count")
          }
        }

        // A single always-on text editor owns both empty and non-empty states;
        // the editor draws its own placeholder when empty, so focus stays stable
        // while the user types the first character.
        notesEditor
      }
    }
  }

  private var notesEditor: some View {
    LorvexPlainTextEditor(
      text: $notes,
      placeholder: String(localized: "task_detail.notes.empty_placeholder", defaultValue: "Add notes", table: "Localizable", bundle: LorvexL10n.bundle),
      minHeight: editorMinHeight,
      fontSize: 14
    )
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .background(.quaternary.opacity(0.10), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .stroke(.separator.opacity(0.16), lineWidth: 0.5)
    }
    .accessibilityLabel(String(localized: "task_detail.notes.a11y", defaultValue: "Task notes", table: "Localizable", bundle: LorvexL10n.bundle))
    .accessibilityIdentifier("task.detail.notes.editor")
  }
}
