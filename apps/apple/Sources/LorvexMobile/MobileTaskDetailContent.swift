import LorvexCore
import LorvexMarkdownUI
import SwiftUI

/// A task's detail: the title and notes, the task's fields as rows with an
/// Add Detail menu for the rest, the tasks it depends on, assistant context,
/// the checklist and reminders when it has any, and the secondary actions. As
/// a screen of its own it carries the "Task" title and a Share toolbar item; in
/// a split's detail pane (`mobileDetailPresentation`) the header ends with a
/// row of the pane's actions instead: `paneActions` (the status transition
/// and Edit) followed by Share.
///
/// `actions` receives whether a task the detail's task waits on is still
/// unfinished (``LorvexTask/isHeldUp(by:)``), judged from the same resolved
/// tasks the Waits On rows show, so Start is unavailable exactly while a row
/// above it shows an unfinished task.
struct MobileTaskDetailContent<Actions: View, PaneActions: View>: View {
  let task: LorvexTask
  let timeZone: TimeZone
  /// The product's logical today, `yyyy-MM-dd`, which the reminders' days
  /// are named relative to.
  let logicalDay: String
  let toggleChecklistItem: ((TaskChecklistItem) async -> Void)?
  let addChecklistItem: ((String) async -> Void)?
  let removeChecklistItem: ((TaskChecklistItem) async -> Void)?
  let addReminder: ((Date) async -> Void)?
  let removeReminder: ((TaskReminder) async -> Void)?
  let resolveDependencyTasks: (([LorvexTask.ID]) async -> [LorvexTask])?
  /// Changes whenever the store's task data may have changed, which reads
  /// the tasks this task waits on again.
  let dependencyRefreshKey: UInt64
  let completeDependency: ((LorvexTask) async -> Void)?
  let isDependencyMutating: (LorvexTask.ID) -> Bool
  /// The task's fields, whose rows and Add menu open one field each through
  /// `editField`.
  let properties: MobileTaskProperties
  /// What the Share button sends (``MobileShareText/task(_:listName:logicalDay:)``).
  let shareText: String
  let editField: (MobileTaskField) -> Void
  @ViewBuilder let actions: (_ isHeldUp: Bool) -> Actions
  @ViewBuilder let paneActions: () -> PaneActions
  @Environment(\.mobileDetailPresentation) private var presentation

  // A task with no checklist or reminders shows neither section; the Add
  // Detail menu unfolds the section with its composer open. A section that
  // has items keeps an "Add …" row for the next one.
  @State private var isComposingChecklistItem = false
  @State private var isComposingReminder = false
  /// The tasks this task waits on, as the Waits On section last resolved them.
  @State private var resolvedDependencies: [LorvexTask]?

  init(
    task: LorvexTask,
    timeZone: TimeZone = .autoupdatingCurrent,
    logicalDay: String,
    toggleChecklistItem: ((TaskChecklistItem) async -> Void)? = nil,
    addChecklistItem: ((String) async -> Void)? = nil,
    removeChecklistItem: ((TaskChecklistItem) async -> Void)? = nil,
    addReminder: ((Date) async -> Void)? = nil,
    removeReminder: ((TaskReminder) async -> Void)? = nil,
    resolveDependencyTasks: (([LorvexTask.ID]) async -> [LorvexTask])? = nil,
    dependencyRefreshKey: UInt64 = 0,
    completeDependency: ((LorvexTask) async -> Void)? = nil,
    isDependencyMutating: @escaping (LorvexTask.ID) -> Bool = { _ in false },
    properties: MobileTaskProperties,
    shareText: String,
    editField: @escaping (MobileTaskField) -> Void,
    @ViewBuilder actions: @escaping (_ isHeldUp: Bool) -> Actions,
    @ViewBuilder paneActions: @escaping () -> PaneActions
  ) {
    self.task = task
    self.timeZone = timeZone
    self.logicalDay = logicalDay
    self.toggleChecklistItem = toggleChecklistItem
    self.addChecklistItem = addChecklistItem
    self.removeChecklistItem = removeChecklistItem
    self.addReminder = addReminder
    self.removeReminder = removeReminder
    self.resolveDependencyTasks = resolveDependencyTasks
    self.dependencyRefreshKey = dependencyRefreshKey
    self.completeDependency = completeDependency
    self.isDependencyMutating = isDependencyMutating
    self.properties = properties
    self.shareText = shareText
    self.editField = editField
    self.actions = actions
    self.paneActions = paneActions
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          Text(userContent: task.title)
            .font(LorvexDesign.Typography.detailTitle)
            .fixedSize(horizontal: false, vertical: true)
          if let statusChip {
            detailChip(statusChip.text, systemImage: statusChip.icon, tint: statusChip.tint)
          }
          if !task.notes.isEmpty {
            Text(userContent: task.notes)
              .font(LorvexDesign.Typography.primaryText)
              .textSelection(.enabled)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          if presentation == .pane {
            HStack(spacing: LorvexDesign.Spacing.s) {
              paneActions()
              shareButton
                .buttonStyle(.bordered)
            }
            .padding(.top, LorvexDesign.Spacing.s)
          }
        }
        .padding(.vertical, LorvexDesign.Spacing.xs)
      }
      MobileTaskPropertiesSection(
        properties: properties,
        edit: editField,
        addChecklist: showsChecklist || addChecklistItem == nil
          ? nil : { setComposingChecklistItem(true) },
        addReminder: showsReminders || addReminder == nil
          ? nil : { setComposingReminder(true) })
      MobileTaskDependenciesSection(
        task: task,
        resolvedDependencies: $resolvedDependencies,
        refreshKey: dependencyRefreshKey,
        resolveDependencyTasks: resolveDependencyTasks,
        completeDependency: completeDependency,
        isDependencyMutating: isDependencyMutating)
      if let aiNotes = task.aiNotes, !aiNotes.isEmpty {
        Section(MobileTaskPropertyCopy.assistantContext) {
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
      if showsChecklist {
        Section(MobileTaskPropertyCopy.checklist) {
          ForEach(task.checklistItems.sorted { $0.position < $1.position }) { item in
            MobileChecklistItemRow(
              item: item,
              toggleChecklistItem: toggleChecklistItem,
              removeChecklistItem: removeChecklistItem
            )
          }
          if let addChecklistItem {
            if isComposingChecklistItem {
              MobileChecklistComposerRow(
                addChecklistItem: addChecklistItem,
                dismiss: { setComposingChecklistItem(false) })
            } else {
              addRow(
                String(
                  localized: "checklist.add", defaultValue: "Add Checklist Item",
                  table: "Localizable", bundle: MobileL10n.bundle),
                accessibilityIdentifier: "task.detail.checklist.add"
              ) { setComposingChecklistItem(true) }
            }
          }
        }
      }
      if showsReminders {
        Section {
          ForEach(task.reminders) { reminder in
            MobileReminderRow(
              reminder: reminder,
              logicalDay: logicalDay,
              timeZone: timeZone,
              removeReminder: removeReminder)
          }
          if let addReminder {
            if isComposingReminder {
              MobileReminderComposerRow(
                timeZone: timeZone,
                dismiss: { setComposingReminder(false) }
              ) { date in
                await addReminder(date)
              }
            } else {
              addRow(
                String(
                  localized: "reminder.add", defaultValue: "Add Reminder",
                  table: "Localizable", bundle: MobileL10n.bundle),
                accessibilityIdentifier: "task.detail.reminders.add"
              ) { setComposingReminder(true) }
            }
          }
        } header: {
          // While the composer is open, its Cancel sits at the trailing end of
          // the section's label line, as section actions do.
          HStack(alignment: .firstTextBaseline) {
            Text(
              String(
                localized: "task_detail.section.reminders", defaultValue: "Reminders",
                table: "Localizable", bundle: MobileL10n.bundle))
            Spacer()
            if isComposingReminder {
              Button(
                String(
                  localized: "common.cancel", defaultValue: "Cancel", table: "Localizable",
                  bundle: MobileL10n.bundle)
              ) { setComposingReminder(false) }
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(LorvexDesign.Palette.accent)
              .textCase(nil)
              .accessibilityIdentifier("task.detail.reminders.cancel")
            }
          }
        }
      }
      actions(task.isHeldUp(by: resolvedDependencies ?? []))
    }
    #if DEBUG
      .onAppear {
        // Dev/QA only: the `lorvex://firsttask/compose/…` screenshot hook unfolds
        // one composer so its expanded state can be captured without a tap.
        switch MobileTaskDetailDebugState.takeInitialComposer() {
        case .checklist?: isComposingChecklistItem = true
        case .reminder?: isComposingReminder = true
        case nil: break
        }
      }
    #endif
    // The task's own title is the headline of the content; the generic
    // navigation title stays small so it does not compete with it.
    .mobileDetailScreenChrome(
      title: String(
        localized: "detail.task", defaultValue: "Task", table: "Localizable",
        bundle: MobileL10n.bundle),
      titleDisplayMode: .inline
    ) {
      ToolbarItem(placement: .automatic) {
        shareButton
      }
    }
  }

  private var showsChecklist: Bool {
    !task.checklistItems.isEmpty || isComposingChecklistItem
  }

  private var showsReminders: Bool {
    !task.reminders.isEmpty || isComposingReminder
  }

  private var shareButton: some View {
    ShareLink(item: shareText) {
      Label(
        String(
          localized: "common.share", defaultValue: "Share", table: "Localizable",
          bundle: MobileL10n.bundle), systemImage: "square.and.arrow.up")
    }
  }

  // MARK: Composer rows

  private func addRow(
    _ title: String, accessibilityIdentifier: String, expand: @escaping () -> Void
  ) -> some View {
    Button(action: expand) {
      Label(title, systemImage: "plus.circle.fill")
    }
    .accessibilityIdentifier(accessibilityIdentifier)
  }

  private func setComposingChecklistItem(_ isComposing: Bool) {
    withAnimation(.snappy) { isComposingChecklistItem = isComposing }
  }

  private func setComposingReminder(_ isComposing: Bool) {
    withAnimation(.snappy) { isComposingReminder = isComposing }
  }

  // MARK: Status chip

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
      return (LorvexTask.Status.inProgress.localizedName, "play.fill", Color.accentColor)
    case .completed:
      return (LorvexTask.Status.completed.localizedName, "checkmark.circle.fill", LorvexDesign.Palette.done)
    case .cancelled:
      return (LorvexTask.Status.cancelled.localizedName, "xmark.circle.fill", Color.secondary)
    case .someday:
      return (LorvexTask.Status.someday.localizedName, "moon.zzz.fill", LorvexDesign.Palette.someday)
    }
  }
}
