import LorvexCore
import SwiftUI

struct MobileStoreFocusScheduleSection: View {
  @Bindable var store: MobileStore
  /// Owned by the enclosing `MobileStoreTodayView` so the clear-confirmation
  /// dialog attaches to the stable `List`. A `.confirmationDialog` on this
  /// view's conditionally-rendered `Section` would not reliably present.
  @Binding var isConfirmingClear: Bool

  private var displayedSchedule: FocusSchedule? {
    store.proposedFocusSchedule ?? store.focusSchedule
  }

  private var isShowingProposal: Bool {
    store.proposedFocusSchedule != nil
  }

  private var hasFocusMembership: Bool {
    // Gate on raw focus membership, not the today-filtered `focusTasks`: a member
    // deferred or scheduled off today still needs to be schedulable and, above
    // all, clearable from here (mirrors the macOS focus-plan controls).
    !(store.snapshot.currentFocus?.taskIDs.isEmpty ?? true)
  }

  private var isBusy: Bool {
    store.isProposingFocusSchedule
      || store.isSavingFocusSchedule
      || store.isClearingFocusSchedule
  }

  /// Resolves a focus block's task id to the task title so the schedule shows the
  /// task name, not a raw UUID (the block payload may carry only the id).
  private func taskTitle(for taskID: String?) -> String? {
    guard let taskID else { return nil }
    return store.snapshot.todayTasks.first { $0.id == taskID }?.title
  }

  var body: some View {
    if hasFocusMembership || displayedSchedule != nil {
      Section {
        if let displayedSchedule {
          if let rationale = displayedSchedule.rationale, !rationale.isEmpty {
            Text(rationale)
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("today.focusSchedule.rationale")
          }

          ForEach(Array(displayedSchedule.blocks.enumerated()), id: \.offset) { _, block in
            MobileFocusScheduleBlockRow(
              block: block, resolvedTaskTitle: taskTitle(for: block.taskID))
          }

          ForEach(displayedSchedule.unscheduled) { task in
            MobileFocusScheduleUnscheduledRow(task: task)
          }

          // Save / Discard only appear for an unsaved proposal; re-scheduling and
          // clearing live in the header ⋯ menu, not as standing buttons.
          if isShowingProposal {
            proposalControls
          }
        } else {
          // Focus tasks are waiting but not yet time-blocked. Auto-schedule lives
          // in the header ⋯ menu (no forced CTA card), so this is just a calm line.
          Text(String(localized: "focus.schedule.empty.line", defaultValue: "No focus time blocked yet — auto-schedule from the menu.", table: "Localizable", bundle: MobileL10n.bundle))
            .font(LorvexDesign.Typography.secondaryText)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("today.focusSchedule.empty")
        }
      } header: {
        header
      }
    }
  }

  @ViewBuilder
  private var header: some View {
    HStack {
      Label(
        isShowingProposal
          ? String(localized: "focus.schedule.proposed.title", defaultValue: "Proposed Schedule", table: "Localizable", bundle: MobileL10n.bundle)
          : String(localized: "focus.schedule.saved.title", defaultValue: "Focus Schedule", table: "Localizable", bundle: MobileL10n.bundle),
        systemImage: "calendar.badge.clock"
      )
      Spacer(minLength: 0)
      // Auto-schedule + the (power-user) Clear both live in this unobtrusive
      // overflow menu, so neither is a standing button that forces itself on the
      // section — re-scheduling is one tap from here when you want it.
      Menu {
        Button {
          Task { await store.proposeFocusSchedule() }
        } label: {
          Label(
            store.isProposingFocusSchedule
              ? String(localized: "focus.schedule.proposing", defaultValue: "Scheduling", table: "Localizable", bundle: MobileL10n.bundle)
              : String(localized: "focus.schedule.propose", defaultValue: "Auto-schedule", table: "Localizable", bundle: MobileL10n.bundle),
            systemImage: "sparkles"
          )
        }
        .disabled(!hasFocusMembership || isBusy)

        if hasFocusMembership {
          Divider()
          Button(role: .destructive) {
            isConfirmingClear = true
          } label: {
            Label(
              String(localized: "focus.schedule.clearConfirm.clear", defaultValue: "Clear Focus Plan", table: "Localizable", bundle: MobileL10n.bundle),
              systemImage: "xmark.circle"
            )
          }
          .disabled(isBusy)
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .accessibilityLabel(String(localized: "focus.schedule.menu.a11y", defaultValue: "Focus schedule actions", table: "Localizable", bundle: MobileL10n.bundle))
      .accessibilityIdentifier("today.focusSchedule.menu")
    }
  }

  /// Proposal commit controls — shown only while an unsaved proposal exists.
  /// Re-scheduling and clearing live in the header ⋯ menu instead.
  @ViewBuilder
  private var proposalControls: some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Button {
        Task { await store.saveProposedFocusSchedule() }
      } label: {
        busyButtonLabel(
          title: store.isSavingFocusSchedule
            ? String(localized: "focus.schedule.saving", defaultValue: "Saving", table: "Localizable", bundle: MobileL10n.bundle)
            : String(localized: "common.save", defaultValue: "Save", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "square.and.arrow.down",
          isBusy: store.isSavingFocusSchedule
        )
      }
      .disabled(isBusy)
      .accessibilityIdentifier("today.focusSchedule.save")

      Button(role: .cancel) {
        store.discardProposedFocusSchedule()
      } label: {
        Label(
          String(localized: "focus.schedule.discardProposal", defaultValue: "Discard Proposal", table: "Localizable", bundle: MobileL10n.bundle),
          systemImage: "xmark"
        )
      }
      .disabled(isBusy)
      .accessibilityIdentifier("today.focusSchedule.discardProposal")

      Spacer(minLength: 0)
    }
    // Borderless so each button owns its own tap target inside the List row.
    // Default-styled buttons in a List cell make the whole row tap-ambiguous.
    .buttonStyle(.borderless)
  }

  @ViewBuilder
  private func busyButtonLabel(title: String, systemImage: String, isBusy: Bool) -> some View {
    if isBusy {
      HStack(spacing: LorvexDesign.Spacing.xs) {
        ProgressView()
          .controlSize(.small)
        Text(title)
      }
    } else {
      Label(title, systemImage: systemImage)
    }
  }
}

private struct MobileFocusScheduleBlockRow: View {
  let block: FocusScheduleBlock
  /// The task's resolved title (looked up by the section) so a task block shows
  /// the task name, never a raw id.
  var resolvedTaskTitle: String? = nil

  private var isTaskBlock: Bool { block.kind == .task }

  private var iconName: String {
    switch block.kind {
    case .task: return "scope"
    case .buffer: return "cup.and.saucer"
    case .calendarEvent, .unknown: return "calendar"
    }
  }

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      VStack(spacing: 2) {
        Text(formattedStartTime)
        Text(formattedEndTime)
      }
      .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .frame(minWidth: 54, alignment: .trailing)
      .accessibilityLabel(timeAccessibilityLabel)

      Image(systemName: iconName)
        .foregroundStyle(isTaskBlock ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 22)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(1)
        Text(kindLabel)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("today.focusSchedule.block")
  }

  private var title: String {
    // Never surface a raw task/event id. Prefer the block's own title, then the
    // task title the section resolved, then a kind-appropriate generic label.
    if let title = block.title, !title.isEmpty { return title }
    if let resolvedTaskTitle { return resolvedTaskTitle }
    if block.kind == .buffer {
      return String(localized: "focus.schedule.block.buffer_title", defaultValue: "Break", table: "Localizable", bundle: MobileL10n.bundle)
    }
    return String(localized: "focus.schedule.block.fallbackTitle", defaultValue: "Focus block", table: "Localizable", bundle: MobileL10n.bundle)
  }

  private var kindLabel: String {
    switch block.kind {
    case .task:
      return String(localized: "focus.schedule.block.kind.task", defaultValue: "Focus task", table: "Localizable", bundle: MobileL10n.bundle)
    case .buffer:
      return String(localized: "focus.schedule.block.kind.buffer", defaultValue: "Buffer", table: "Localizable", bundle: MobileL10n.bundle)
    case .calendarEvent, .unknown:
      return String(localized: "focus.schedule.block.kind.calendar", defaultValue: "Calendar hold", table: "Localizable", bundle: MobileL10n.bundle)
    }
  }

  private var formattedStartTime: String {
    mobileClockTimeLabel(block.startTime)
  }

  private var formattedEndTime: String {
    mobileClockTimeLabel(block.endTime)
  }

  private var timeAccessibilityLabel: String {
    String(
      format: String(localized: "focus.schedule.block.time.a11y", defaultValue: "%@ to %@", table: "Localizable", bundle: MobileL10n.bundle),
      formattedStartTime,
      formattedEndTime
    )
  }
}

private struct MobileFocusScheduleUnscheduledRow: View {
  let task: FocusScheduleTask

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
        .frame(width: 22)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(task.title)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .lineLimit(1)
        Text(detailLabel)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("today.focusSchedule.unscheduled")
  }

  private var detailLabel: String {
    guard let estimatedMinutes = task.estimatedMinutes else {
      return String(localized: "focus.schedule.unscheduled.noEstimate", defaultValue: "Not scheduled", table: "Localizable", bundle: MobileL10n.bundle)
    }
    return String(
      format: String(localized: "focus.schedule.unscheduled.estimated", defaultValue: "Not scheduled, %@", table: "Localizable", bundle: MobileL10n.bundle),
      MobileTaskDisplayText.compactEstimateMinutes(estimatedMinutes)
    )
  }
}
