import LorvexCore
import LorvexMarkdownUI
import SwiftUI

struct MobileTaskDetailContent<Actions: View>: View {
  let task: LorvexTask
  let timeZone: TimeZone
  let toggleChecklistItem: ((TaskChecklistItem) async -> Void)?
  let addChecklistItem: ((String) async -> Void)?
  let removeChecklistItem: ((TaskChecklistItem) async -> Void)?
  let addReminder: ((Date) async -> Void)?
  let removeReminder: ((TaskReminder) async -> Void)?
  let resolveDependencyTasks: (([LorvexTask.ID]) async -> [LorvexTask])?
  @ViewBuilder let actions: () -> Actions

  init(
    task: LorvexTask,
    timeZone: TimeZone = .autoupdatingCurrent,
    toggleChecklistItem: ((TaskChecklistItem) async -> Void)? = nil,
    addChecklistItem: ((String) async -> Void)? = nil,
    removeChecklistItem: ((TaskChecklistItem) async -> Void)? = nil,
    addReminder: ((Date) async -> Void)? = nil,
    removeReminder: ((TaskReminder) async -> Void)? = nil,
    resolveDependencyTasks: (([LorvexTask.ID]) async -> [LorvexTask])? = nil,
    @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.task = task
    self.timeZone = timeZone
    self.toggleChecklistItem = toggleChecklistItem
    self.addChecklistItem = addChecklistItem
    self.removeChecklistItem = removeChecklistItem
    self.addReminder = addReminder
    self.removeReminder = removeReminder
    self.resolveDependencyTasks = resolveDependencyTasks
    self.actions = actions
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          Text(task.title)
            .font(LorvexDesign.Typography.sectionHeader)
            .fixedSize(horizontal: false, vertical: true)
          glanceChips
          if !task.notes.isEmpty {
            Text(task.notes)
              .font(LorvexDesign.Typography.primaryText)
              .textSelection(.enabled)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.vertical, LorvexDesign.Spacing.xs)
      }
      MobileTaskDetailMetadataSection(task: task, resolveDependencyTasks: resolveDependencyTasks)
      if let aiNotes = task.aiNotes, !aiNotes.isEmpty {
        Section(
          String(
            localized: "task_detail.section.assistant_context", defaultValue: "Assistant Context",
            table: "Localizable", bundle: MobileL10n.bundle)
        ) {
          MarkdownNoteView(aiNotes,
            taskItemAccessibility: .init(
              completedFormat: String(
                localized: "markdown.task.completed_a11y", defaultValue: "Completed: %@",
                table: "Localizable", bundle: MobileL10n.bundle),
              todoFormat: String(
                localized: "markdown.task.todo_a11y", defaultValue: "To do: %@",
                table: "Localizable", bundle: MobileL10n.bundle))
          )
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      if !task.checklistItems.isEmpty || addChecklistItem != nil {
        Section(
          String(
            localized: "task_detail.section.checklist", defaultValue: "Checklist",
            table: "Localizable", bundle: MobileL10n.bundle)
        ) {
          ForEach(task.checklistItems.sorted { $0.position < $1.position }) { item in
            MobileChecklistItemRow(
              item: item,
              toggleChecklistItem: toggleChecklistItem,
              removeChecklistItem: removeChecklistItem
            )
          }
          if addChecklistItem != nil {
            MobileChecklistComposerRow { text in await addChecklistItem?(text) }
          }
        }
      }
      if !task.reminders.isEmpty || addReminder != nil {
        Section(
          String(
            localized: "task_detail.section.reminders", defaultValue: "Reminders",
            table: "Localizable", bundle: MobileL10n.bundle)
        ) {
          ForEach(task.reminders) { reminder in
            MobileReminderRow(
              reminder: reminder,
              timeZone: timeZone,
              removeReminder: removeReminder)
          }
          if addReminder != nil {
            MobileReminderComposerRow(timeZone: timeZone) { date in
              await addReminder?(date)
            }
          }
        }
      }
      actions()
    }
    .lorvexSpatialContainerPadding()
    .navigationTitle(
      String(
        localized: "detail.task", defaultValue: "Task", table: "Localizable",
        bundle: MobileL10n.bundle)
    )
    .toolbar {
      ToolbarItem(placement: .automatic) {
        ShareLink(item: LorvexTaskMarkdownExport.render(task)) {
          Label(
            String(
              localized: "common.share", defaultValue: "Share", table: "Localizable",
              bundle: MobileL10n.bundle), systemImage: "square.and.arrow.up")
        }
      }
    }
  }

  // MARK: Glance chips
  //
  // The most-scanned metadata (priority, due, estimate, a non-open status) reads
  // at a glance as colored chips above the fold; the full "Details" section below
  // carries only what the chips don't (tags, dependencies, lateness, recurrence).

  @ViewBuilder
  private var glanceChips: some View {
    LorvexFlowLayout(spacing: LorvexDesign.Spacing.xs, lineSpacing: LorvexDesign.Spacing.xs) {
      detailChip(
        MobileTaskDisplayText.priority(task.priority),
        systemImage: task.priority.prioritySymbolName,
        tint: task.priority.priorityTint)
      if let due = task.dueDateDisplaySummary {
        detailChip(due, systemImage: "calendar", tint: LorvexDesign.Palette.accent)
      }
      if let estimate = task.estimatedMinutes {
        detailChip(
          MobileTaskDisplayText.compactEstimateMinutes(estimate),
          systemImage: "clock", tint: .secondary)
      }
      if let statusChip {
        detailChip(statusChip.text, systemImage: statusChip.icon, tint: statusChip.tint)
      }
    }
  }

  private func detailChip(_ text: String, systemImage: String, tint: Color) -> some View {
    // An explicit HStack, not a `Label`: a bare `Label` placed by the custom
    // `LorvexFlowLayout` renders icon-only (it still reports the title's width,
    // so the capsule looks padded but the text never draws).
    HStack(spacing: 5) {
      Image(systemName: systemImage)
        .imageScale(.small)
      Text(text)
        .lineLimit(1)
    }
    .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
    .foregroundStyle(tint)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .padding(.vertical, 5)
    .background(tint.opacity(0.14), in: Capsule())
  }

  private var statusChip: (text: String, icon: String, tint: Color)? {
    switch task.status {
    case .open:
      return nil
    case .inProgress:
      return (MobileTaskDisplayText.status(.inProgress), "play.fill", Color.accentColor)
    case .completed:
      return (MobileTaskDisplayText.status(.completed), "checkmark.circle.fill", LorvexDesign.Palette.done)
    case .cancelled:
      return (MobileTaskDisplayText.status(.cancelled), "xmark.circle.fill", Color.secondary)
    case .someday:
      return (MobileTaskDisplayText.status(.someday), "moon.zzz.fill", LorvexDesign.Palette.someday)
    }
  }
}

extension MobileTaskDetailContent where Actions == EmptyView {
  init(task: LorvexTask) {
    self.task = task
    self.timeZone = .autoupdatingCurrent
    self.toggleChecklistItem = nil
    self.addChecklistItem = nil
    self.removeChecklistItem = nil
    self.addReminder = nil
    self.removeReminder = nil
    self.resolveDependencyTasks = nil
    self.actions = { EmptyView() }
  }
}
