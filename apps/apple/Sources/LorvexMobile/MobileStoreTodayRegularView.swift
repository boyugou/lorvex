import LorvexCore
import SwiftUI

/// The iPad / visionOS (regular-width) Today — a centered, readable single column
/// of cards instead of the phone's full-bleed `List`.
///
/// `List` can't be width-constrained on iPadOS (it always fills the detail column,
/// reading as a blown-up phone), so this is a `ScrollView` capped to a comfortable
/// width. It stays the day plan — header, the focus schedule, and the day's tasks —
/// and omits the embedded Habits/Calendar previews, which are first-class tabs on
/// this layout rather than things to duplicate here.
struct MobileStoreTodayRegularView: View {
  @Bindable var store: MobileStore
  @Binding var isConfirmingClear: Bool

  private var nextTask: LorvexTask? { store.snapshot.nextTask }
  private var todayTasks: [LorvexTask] {
    MobileTodayTaskSections.todayTasks(from: store.snapshot)
  }
  private var inProgressTasks: [LorvexTask] { store.snapshot.inProgressTasks }
  private var displayedSchedule: FocusSchedule? {
    store.proposedFocusSchedule ?? store.focusSchedule
  }
  private var hasFocusMembership: Bool {
    !(store.snapshot.currentFocus?.taskIDs.isEmpty ?? true)
  }
  /// Today's events, filtered out of the loaded timeline window to the current
  /// day and agenda-ordered (Lorvex-owned plus mirrored EventKit events).
  private var todayEvents: [CalendarTimelineEvent] {
    store.calendarTimeline?.eventsOccurring(on: store.logicalTodayString) ?? []
  }
  /// Show the standalone schedule card: there are events today and no focus
  /// timeline is folding them in. Once a schedule exists, the events ride inside
  /// the focus card instead of being listed twice.
  private var showsStandaloneSchedule: Bool {
    displayedSchedule == nil && !todayEvents.isEmpty
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
        MobileTodayHeader(summary: store.summary)
        if !inProgressTasks.isEmpty { inProgressCard }
        if showsStandaloneSchedule { scheduleCard }
        focusCard
        if nextTask != nil || MobileTodayTaskSections.showsOpenTaskEmptyState(for: store.snapshot) {
          nextCard
        }
        if !todayTasks.isEmpty { todayCard }
      }
      // ScrollView content honors maxWidth (unlike List); cap + center it so the
      // wide iPad column reads as a designed column, not a stretched phone.
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
      .padding(LorvexDesign.Spacing.l)
    }
    .background(LorvexDesign.Palette.groupedBackground)
    .refreshable { await store.refreshResettingCloudSyncPacing() }
    .toolbar {
      Button {
        store.isPresentingCapture = true
      } label: {
        Label(
          String(
            localized: "today.capture", defaultValue: "Capture", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "plus.circle")
      }
      .lorvexToolbarHoverEffect()
      .accessibilityIdentifier("today.toolbar.capture")
    }
  }

  // MARK: Cards

  /// The day's fixed commitments (Lorvex events plus the mirrored EventKit
  /// external calendar) as the readable column's opening card, framing the
  /// focus and task cards below.
  @ViewBuilder
  private var scheduleCard: some View {
    cardSection {
      sectionTitle(
        String(
          localized: "today.section.schedule", defaultValue: "Schedule", table: "Localizable",
          bundle: MobileL10n.bundle))
      VStack(spacing: 0) {
        ForEach(todayEvents) { event in
          scheduleEventRow(event)
          if event.id != todayEvents.last?.id { Divider() }
        }
      }
    }
  }

  private func scheduleEventRow(_ event: CalendarTimelineEvent) -> some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Text(
        event.allDay
          ? String(
            localized: "calendar.all_day_short", defaultValue: "All day", table: "Localizable",
            bundle: MobileL10n.bundle)
          : event.startTime.map(mobileClockTimeLabel) ?? "—"
      )
      .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium))
      .foregroundStyle(.secondary).frame(minWidth: 54, alignment: .trailing)
      Image(systemName: event.allDay ? "sun.max" : "calendar")
        .foregroundStyle(.secondary)
        .frame(width: 22)
      Text(event.title).font(.body).lineLimit(1)
      Spacer(minLength: 0)
      if event.isRecurring || event.supportsScopedMutation {
        Image(systemName: "repeat")
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.tertiary)
          .accessibilityLabel(
            String(
              localized: "calendar.repeating_event.a11y", defaultValue: "Repeating event",
              table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var focusCard: some View {
    if hasFocusMembership || displayedSchedule != nil {
      cardSection {
        HStack {
          sectionTitle(
            store.proposedFocusSchedule != nil
              ? String(
                localized: "focus.schedule.proposed.title", defaultValue: "Proposed Schedule",
                table: "Localizable", bundle: MobileL10n.bundle)
              : String(
                localized: "focus.schedule.saved.title", defaultValue: "Focus Schedule",
                table: "Localizable", bundle: MobileL10n.bundle))
          Spacer(minLength: 0)
          Menu {
            Button {
              Task { await store.proposeFocusSchedule() }
            } label: {
              Label(
                store.isProposingFocusSchedule
                  ? String(
                    localized: "focus.schedule.proposing", defaultValue: "Scheduling",
                    table: "Localizable", bundle: MobileL10n.bundle)
                  : String(
                    localized: "focus.schedule.propose", defaultValue: "Auto-schedule",
                    table: "Localizable", bundle: MobileL10n.bundle),
                systemImage: "sparkles")
            }
            .disabled(!hasFocusMembership || store.isProposingFocusSchedule)
            if hasFocusMembership {
              Divider()
              Button(role: .destructive) {
                isConfirmingClear = true
              } label: {
                Label(
                  String(
                    localized: "focus.schedule.clearConfirm.clear",
                    defaultValue: "Clear Focus Plan", table: "Localizable",
                    bundle: MobileL10n.bundle),
                  systemImage: "xmark.circle")
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
          }
          .accessibilityLabel(
            String(
              localized: "focus.schedule.menu.a11y", defaultValue: "Focus schedule actions",
              table: "Localizable", bundle: MobileL10n.bundle))
        }

        if let displayedSchedule, !displayedSchedule.blocks.isEmpty {
          VStack(spacing: 0) {
            ForEach(Array(displayedSchedule.blocks.enumerated()), id: \.offset) { index, block in
              focusBlockRow(block)
              if index < displayedSchedule.blocks.count - 1 { Divider() }
            }
          }
        } else {
          Text(
            String(
              localized: "focus.schedule.empty.line",
              defaultValue: "No focus time blocked yet — auto-schedule from the menu.",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .font(LorvexDesign.Typography.secondaryText)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  private func focusBlockRow(_ block: FocusScheduleBlock) -> some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      Text(mobileClockTimeLabel(block.startTime))
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary).frame(minWidth: 54, alignment: .trailing)
      Image(systemName: focusBlockIcon(block))
        .foregroundStyle(block.kind == .task ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(width: 22)
      Text(focusBlockTitle(block))
        .font(.body).lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }

  private func focusBlockIcon(_ block: FocusScheduleBlock) -> String {
    switch block.kind {
    case .task: return "scope"
    case .buffer: return "cup.and.saucer"
    case .calendarEvent, .unknown: return "calendar"
    }
  }

  private func focusBlockTitle(_ block: FocusScheduleBlock) -> String {
    if let title = block.title, !title.isEmpty { return title }
    if block.kind == .buffer {
      return String(
        localized: "focus.schedule.block.buffer_title", defaultValue: "Break", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
    // A block without a human title falls back to a placeholder, never a raw
    // task/event ID — those are opaque and meaningless to the user.
    return String(
      localized: "focus.schedule.block.fallbackTitle", defaultValue: "Focus block",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  @ViewBuilder
  private var nextCard: some View {
    cardSection {
      sectionTitle(
        String(
          localized: "today.section.next", defaultValue: "Next", table: "Localizable",
          bundle: MobileL10n.bundle))
      if let task = nextTask {
        taskRow(task)
      } else {
        MobileStoreTaskEmptyState(store: store)
      }
    }
  }

  @ViewBuilder
  private var inProgressCard: some View {
    cardSection {
      sectionTitle(
        String(
          localized: "today.section.in_progress", defaultValue: "In Progress", table: "Localizable",
          bundle: MobileL10n.bundle))
      VStack(spacing: 0) {
        ForEach(inProgressTasks) { task in
          taskRow(task)
          if task.id != inProgressTasks.last?.id { Divider() }
        }
      }
    }
  }

  @ViewBuilder
  private var todayCard: some View {
    cardSection {
      sectionTitle(
        String(
          localized: "today.section.today", defaultValue: "Today", table: "Localizable",
          bundle: MobileL10n.bundle))
      VStack(spacing: 0) {
        ForEach(todayTasks) { task in
          taskRow(task)
          if task.id != todayTasks.last?.id { Divider() }
        }
      }
    }
  }

  private func taskRow(_ task: LorvexTask) -> some View {
    // Reuses the shared action row: tap opens detail, context menu carries
    // complete/defer/focus. (Swipe is List-only and simply inert here, which is
    // fine — context menu is the iPad/pointer idiom.)
    MobileActionTaskRow(
      task: task,
      isFocused: store.taskIsFocused(task.id),
      isMutating: store.taskIsMutating(task.id),
      select: { store.selectTask(task.id) },
      toggleFocus: { await store.toggleTaskFocus(task.id) },
      complete: { await store.completeTask(task.id) },
      deferTask: { await store.deferTaskToTomorrow(task.id) },
      start: { await store.startTask(task.id) },
      markNotStarted: { await store.markTaskNotStarted(task.id) }
    )
    // Outside a List, a NavigationLink tints its whole label with the accent
    // color; `.plain` keeps the row's own typography (primary title, etc.).
    .buttonStyle(.plain)
  }

  // MARK: Card chrome

  private func sectionTitle(_ text: String) -> some View {
    Text(text)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private func cardSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(LorvexDesign.Spacing.cardPadding)
    .background(
      LorvexDesign.Palette.card,
      in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
  }
}
