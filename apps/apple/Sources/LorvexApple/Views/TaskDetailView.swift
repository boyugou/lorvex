import LorvexCore
import SwiftUI

private enum TaskDetailInspectorMetrics {
  static let maxContentWidth: CGFloat = 500
  static let horizontalPadding: CGFloat = LorvexDesign.Spacing.m
  static let topPadding: CGFloat = LorvexDesign.Spacing.m
  static let bottomPadding: CGFloat = LorvexDesign.Spacing.xl
}

struct TaskDetailView: View {
  @Bindable var store: AppStore
  @Environment(\.undoManager) var undoManager
  @Environment(\.openWindow) var openWindow

  @State var showScheduling = false
  @State var showOrganization = false
  @State var showDependencies = false
  @State var showReminders = false
  @State var showRecurrence = false
  @State var showAINotes = false
  @FocusState var titleFieldFocused: Bool

  var body: some View {
    Group {
      if let task = store.selectedTask {
        let draftHasChanges = store.selectedTaskDraftHasChanges
        let canSave = store.selectedTaskCanSave(draftHasChanges: draftHasChanges)
        ScrollView {
          TaskDetailInspectorColumn {
            VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
              headerSection(task: task, draftHasChanges: draftHasChanges, canSave: canSave)
              notesSection(task: task)
              checklistSection(task: task)
              advancedSection(task: task)
            }
          }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(.quaternary.opacity(0.035))
      } else {
        TaskDetailInspectorColumn {
          noTaskSelectedEmptyState
        }
        .background(.quaternary.opacity(0.035))
      }
    }
    // No `navigationTitle` here: as the main window's inspector, its title would
    // override the window's title bar with "Detail" instead of the active
    // workspace (Today / Calendar / …). The standalone task-detail window (the
    // `.taskDetail` `Window` scene in `lorvexWorkspaceScenes`) supplies its own
    // static "Task Detail" title from the scene initializer, so this view adds none.
    .onAppear {
      store.syncSelectedTaskDraft()
      Task { await store.loadSelectedTaskDetail() }
    }
    .onChange(of: titleFieldFocused) { _, isFocused in
      guard !isFocused else { return }
      Task { await store.saveSelectedTaskDraftIfNeeded() }
    }
    // Autosave ~1.2s after the user stops editing any draft field. Blur and
    // navigation saves still run; this covers the paths they miss — closing
    // the window or quitting with focus still in a field. Each keystroke
    // changes the fingerprint, cancelling the pending sleep (debounce).
    .task(id: store.taskDetailDraftFingerprint) {
      guard let id = store.selectedTaskID, store.taskDetailDraftHasChanges(for: id) else { return }
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard !Task.isCancelled else { return }
      await store.saveSelectedTaskDraftIfNeeded()
    }
    .onChange(of: store.selectedTaskID) { oldValue, newValue in
      Task {
        if let oldValue,
          oldValue != newValue,
          store.taskDetailDraftHasChanges(for: oldValue)
        {
          // Save on navigation even when the estimate field is malformed —
          // `saveTaskDetailDraft` keeps the task's existing estimate in that
          // case so the user's title / notes / priority edits aren't dropped.
          await store.saveTaskDetailDraft(id: oldValue, preserveSelection: newValue)
        } else {
          store.syncSelectedTaskDraft()
        }
        await store.loadSelectedTaskDetail()
      }
    }
    .onDisappear {
      // Closing a detail/workspace window cancels the view-owned debounce.
      // Capture the current target and hand the write to the store, which
      // outlives this view. Normal application Quit has an AppKit barrier too.
      guard let id = store.selectedTaskID, store.taskDetailDraftHasChanges(for: id) else { return }
      Task { await store.saveTaskDetailDraft(id: id, preserveSelection: id) }
    }
    .userActivity(LorvexActivityType.openTask, isActive: store.selectedTaskID != nil) { activity in
      guard let taskID = store.selectedTaskID else { return }
      let built = makeOpenTaskActivity(taskID: taskID, title: store.selectedTask?.title)
      activity.title = built.title
      activity.isEligibleForHandoff = built.isEligibleForHandoff
      activity.isEligibleForSearch = built.isEligibleForSearch
      activity.requiredUserInfoKeys = built.requiredUserInfoKeys
      activity.addUserInfoEntries(from: built.userInfo ?? [:])
    }
  }

  private var noTaskSelectedEmptyState: some View {
    LorvexEmptyStatePanel(
      title: String(localized: "task_detail.empty.no_selection", defaultValue: "No Task Selected", table: "Localizable", bundle: LorvexL10n.bundle),
      message: String(
        localized: "task_detail.empty.no_selection_description",
        defaultValue: "Select a task from Today, Tasks, Lists, or Calendar to review its details here.",
        table: "Localizable",
        bundle: LorvexL10n.bundle
      ),
      systemImage: "checklist",
      tint: .accentColor,
      style: .inline,
      chips: [
        LorvexEmptyStateChip(
          title: String(localized: "task_detail.empty.inspector_chip", defaultValue: "Inspector", table: "Localizable", bundle: LorvexL10n.bundle),
          systemImage: "sidebar.right",
          tint: .accentColor
        )
      ]
    )
  }

  /// Secondary fields, collapsed by default to keep the default view calm.
  /// Essentials (title, status, priority, notes, primary actions, checklist)
  /// stay visible above this; everything advanced lives here.
  func advancedSection(task: LorvexTask) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      TaskDetailPanel(accessibilityIdentifier: "task.detail.advancedDisclosures", padding: 0) {
        VStack(alignment: .leading, spacing: 0) {
          LorvexDisclosure(
            String(localized: "task_detail.section.scheduling", defaultValue: "Scheduling", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "calendar.badge.clock",
            showsDivider: true,
            accessibilityID: "task.detail.disclosure.scheduling",
            isExpanded: $showScheduling
          ) {
            schedulingContent
          }
          LorvexDisclosure(
            String(localized: "task_detail.section.organization", defaultValue: "Organization", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "tag",
            showsDivider: true,
            accessibilityID: "task.detail.disclosure.organization",
            isExpanded: $showOrganization
          ) {
            organizationContent(task: task)
          }
          LorvexDisclosure(
            String(
              localized: "task_detail.section.dependencies", defaultValue: "Dependencies",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            systemImage: "arrow.triangle.branch",
            showsDivider: true,
            accessibilityID: "task.detail.disclosure.dependencies",
            isExpanded: $showDependencies
          ) {
            dependenciesContent(task: task)
          }
          LorvexDisclosure(
            String(localized: "task_detail.section.recurrence", defaultValue: "Recurrence", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "repeat",
            showsDivider: true,
            accessibilityID: "task.detail.disclosure.recurrence",
            isExpanded: $showRecurrence
          ) {
            recurrenceContent
          }
          LorvexDisclosure(
            String(localized: "task_detail.section.reminders", defaultValue: "Reminders", table: "Localizable", bundle: LorvexL10n.bundle),
            systemImage: "bell",
            showsDivider: true,
            accessibilityID: "task.detail.disclosure.reminders",
            isExpanded: $showReminders
          ) {
            remindersContent(task: task)
          }
          LorvexDisclosure(
            String(
              localized: "task_detail.section.assistant_context",
              defaultValue: "Assistant Context",
              table: "Localizable",
              bundle: LorvexL10n.bundle),
            systemImage: "sparkles",
            showsDivider: false,
            accessibilityID: "task.detail.disclosure.aiNotes",
            isExpanded: $showAINotes
          ) {
            aiNotesContent(task: task)
          }
        }
      }
    }
  }
}

private struct TaskDetailInspectorColumn<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .frame(maxWidth: TaskDetailInspectorMetrics.maxContentWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(.horizontal, TaskDetailInspectorMetrics.horizontalPadding)
      .padding(.top, TaskDetailInspectorMetrics.topPadding)
      .padding(.bottom, TaskDetailInspectorMetrics.bottomPadding)
  }
}

private enum TaskDetailDisclosureMetrics {
  static let iconWidth: CGFloat = 15
  static let accentRailWidth: CGFloat = 2
  static let horizontalPadding: CGFloat = 12
  static let verticalPadding: CGFloat = 8
}

private enum TaskDetailDisclosureTypography {
  static let icon = LorvexDesign.Typography.tertiaryText.weight(.semibold)
  static let title = LorvexDesign.Typography.secondaryText.weight(.semibold)
  static let chevron = LorvexDesign.Typography.tertiaryText.weight(.semibold)
}

/// A compact inspector disclosure row for advanced task metadata. These rows
/// are secondary navigation under the selected-task summary, not another stack
/// of page titles.
private struct LorvexDisclosure<Content: View>: View {
  let title: String
  let systemImage: String
  let showsDivider: Bool
  let accessibilityID: String
  @Binding var isExpanded: Bool
  @ViewBuilder let content: () -> Content

  init(
    _ title: String,
    systemImage: String,
    showsDivider: Bool,
    accessibilityID: String,
    isExpanded: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.showsDivider = showsDivider
    self.accessibilityID = accessibilityID
    _isExpanded = isExpanded
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        lorvexAnimated(.snappy(duration: 0.22)) { isExpanded.toggle() }
      } label: {
        HStack(spacing: LorvexDesign.Spacing.s) {
          Image(systemName: systemImage)
            .font(TaskDetailDisclosureTypography.icon)
            .foregroundStyle(isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: TaskDetailDisclosureMetrics.iconWidth)
          Text(title)
            .font(TaskDetailDisclosureTypography.title)
            .foregroundStyle(.primary)
          Spacer(minLength: LorvexDesign.Spacing.s)
          Image(systemName: "chevron.right")
            .font(TaskDetailDisclosureTypography.chevron)
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        // The whole header row is the hit target, not just the chevron.
        .contentShape(Rectangle())
        .padding(.horizontal, TaskDetailDisclosureMetrics.horizontalPadding)
        .padding(.vertical, TaskDetailDisclosureMetrics.verticalPadding)
        .background {
          if isExpanded {
            RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
              .fill(.quaternary.opacity(0.08))
              .padding(.horizontal, LorvexDesign.Spacing.xs)
              .padding(.vertical, 2)
          }
        }
        .overlay(alignment: .leading) {
          if isExpanded {
            Capsule()
              .fill(.tint)
              .frame(width: TaskDetailDisclosureMetrics.accentRailWidth)
              .padding(.vertical, LorvexDesign.Spacing.s)
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier(accessibilityID)

      if isExpanded {
        content()
          .padding(.top, LorvexDesign.Spacing.s)
          .padding(.horizontal, LorvexDesign.Spacing.s)
          .padding(.bottom, LorvexDesign.Spacing.s)
          .frame(maxWidth: .infinity, alignment: .leading)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if showsDivider {
        Divider()
          .padding(.leading, dividerLeadingPadding)
      }
    }
  }

  private var dividerLeadingPadding: CGFloat {
    TaskDetailDisclosureMetrics.horizontalPadding
      + TaskDetailDisclosureMetrics.iconWidth
      + LorvexDesign.Spacing.s
  }
}
