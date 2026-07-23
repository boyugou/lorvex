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

  func organizationContent(task: LorvexTask) -> some View {
    TaskDetailOrganizationPanel(store: store, tagsText: taskTagsBinding(for: task), taskID: task.id)
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
    TaskDetailPanel(accessibilityIdentifier: "task.detail.aiNotes.panel") {
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
            MarkdownNoteView(aiNotes, taskItemAccessibility: .init(
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
          .padding(LorvexDesign.Spacing.s)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
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

/// Tags as removable capsule chips over a comma-separated `tagsText` binding.
///
/// `tagsText` stays the single source of truth (the draft binding the rest of
/// the detail view edits and saves); the chips are a presentation of its parsed
/// values, and every edit — remove, add, dedup — rewrites the same binding.
/// Each tag reads as a discrete `#tag` chip with its own remove control, and a
/// trailing inline field commits new tags on Return/comma.
private struct TaskDetailOrganizationPanel: View {
  @Bindable var store: AppStore
  @Binding var tagsText: String
  /// The selected task's id — the draft resets when this changes (a task
  /// switch), not on every `tagsText` mutation (which also fires on add/remove
  /// chip and would wipe a half-typed tag).
  let taskID: String
  @State private var draft: String = ""

  /// Trimmed, non-empty tags parsed from the comma-separated binding, in order.
  private var tags: [String] {
    tagsText
      .split(separator: ",", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private var currentList: LorvexList? {
    guard let listID = store.selectedTask?.listID else { return nil }
    return store.lists?.lists.first { $0.id == listID }
  }

  var body: some View {
    TaskDetailPanel(accessibilityIdentifier: "task.detail.organization.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      TaskDetailInlineField(
        title: String(localized: "task_detail.organization.list", defaultValue: "List", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "checklist"
      ) {
        Menu {
          ForEach(store.lists?.lists.filter { $0.archivedAt == nil } ?? []) { list in
            Button {
              Task { await store.moveSelectedTaskToList(list.id) }
            } label: {
              Label(list.name, systemImage: list.icon ?? "list.bullet")
            }
          }
        } label: {
          HStack(spacing: LorvexDesign.Spacing.xs) {
            LorvexListIconView(
              icon: currentList?.icon,
              tint: Color(lorvexHex: currentList?.color) ?? .accentColor,
              size: 16,
              font: .system(size: 10, weight: .medium),
              background: .none
            )
            Text(currentList?.name ?? String(
              localized: "task_detail.organization.no_list", defaultValue: "No List",
              table: "Localizable",
              bundle: LorvexL10n.bundle))
              .font(LorvexDesign.Typography.primaryText)
              .foregroundStyle(.primary)
              .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(.tertiary)
          }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("task.detail.organization.list")
        .accessibilityLabel(String(
          localized: "task_detail.organization.list_a11y", defaultValue: "Task's list",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
        .accessibilityValue(currentList?.name ?? String(
          localized: "task_detail.organization.no_list", defaultValue: "No List",
          table: "Localizable",
          bundle: LorvexL10n.bundle))
      }

      TaskDetailInlineField(
        title: String(localized: "task_detail.organization.tags", defaultValue: "Tags", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "number"
      ) {
        LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs) {
          ForEach(tags, id: \.self) { tag in
            tagChip(tag)
          }
          addField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Drop any half-typed tag when the inspector switches tasks, so it never
        // lingers as stray text under a different task. Keyed on the task id, not
        // tagsText, so adding/removing a chip doesn't wipe an in-progress tag.
        .onChange(of: taskID) { _, _ in draft = "" }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "task_detail.organization.tags_a11y", defaultValue: "Task tags", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("task.detail.organization.tags")
      }
      }
    }
  }

  private func tagChip(_ tag: String) -> some View {
    HStack(spacing: LorvexDesign.Spacing.xs) {
      Text("#\(tag)")
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.primary)
        .lineLimit(1)
      Button {
        removeTag(tag)
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())
      .help(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle) + " #\(tag)")
      .accessibilityIdentifier("task.detail.organization.tagRemove")
    }
    .padding(.leading, LorvexDesign.Spacing.s)
    .padding(.trailing, LorvexDesign.Spacing.xs)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .background(.tint.opacity(0.10), in: Capsule())
    .overlay {
      Capsule().strokeBorder(.tint.opacity(0.18), lineWidth: 0.5)
    }
    .accessibilityElement(children: .combine)
  }

  /// Inline new-tag field, shaped as a subtle (untinted) capsule with a leading
  /// "#" so half-typed text reads as a tag being entered — not stray text beside
  /// the committed chips. Return or a typed comma commits it.
  private var addField: some View {
    HStack(spacing: 1) {
      Text("#")
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.tertiary)
      TextField(
        String(localized: "task_detail.organization.add_tag", defaultValue: "Add tag", table: "Localizable", bundle: LorvexL10n.bundle),
        text: $draft
      )
      .font(LorvexDesign.Typography.secondaryText)
      .textFieldStyle(.plain)
      .frame(minWidth: 60)
      .fixedSize()
      .accessibilityLabel(String(localized: "task_detail.organization.tags_a11y", defaultValue: "Task tags", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityIdentifier("task.detail.organization.tagsAdd")
      .onChange(of: draft) { _, newValue in
        // A typed comma is the same "commit this tag" gesture as Return.
        guard newValue.contains(",") else { return }
        for piece in newValue.split(separator: ",") { commitTag(String(piece)) }
        draft = ""
      }
      .onSubmit { commitDraft() }
    }
    .padding(.leading, LorvexDesign.Spacing.s)
    .padding(.trailing, LorvexDesign.Spacing.s)
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .background(.quaternary.opacity(0.45), in: Capsule())
    .overlay {
      Capsule().strokeBorder(.quaternary.opacity(0.6), lineWidth: 0.5)
    }
  }

  private func commitDraft() {
    commitTag(draft)
    draft = ""
  }

  /// Append `raw` (trimmed) to the binding, skipping blanks and case-insensitive
  /// duplicates of an existing tag.
  private func commitTag(_ raw: String) {
    let tag = raw.trimmingCharacters(in: .whitespaces)
    guard !tag.isEmpty else { return }
    guard !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
    tagsText = (tags + [tag]).joined(separator: ", ")
  }

  private func removeTag(_ tag: String) {
    tagsText = tags.filter { $0 != tag }.joined(separator: ", ")
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
    TaskDetailPanel(accessibilityIdentifier: "task.detail.notes.panel") {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          Label(
            String(localized: "task_detail.notes.title", defaultValue: "Notes", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "note.text"
          )
          .font(LorvexDesign.Typography.primaryEmphasis)

          Spacer()

          // The count exists to guard the 50k-codepoint body cap, so it only
          // appears once the cap is actually near — an always-on "58 chars"
          // pill is noise that reads as an unexplained UI element.
          if isApproachingLimit {
            Text(
              String(
                format: String(
                  localized: "task_detail.notes.character_limit",
                  defaultValue: "%1$lld / %2$lld characters",
                  table: "Localizable",
                  bundle: LorvexL10n.bundle
                ),
                characterCount,
                ValidationLimits.maxBodyLength
              )
            )
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(characterCount >= ValidationLimits.maxBodyLength ? AnyShapeStyle(.red) : AnyShapeStyle(.orange))
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
