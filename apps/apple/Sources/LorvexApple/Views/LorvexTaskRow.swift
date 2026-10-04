import LorvexCore
import SwiftUI

/// The unified task row used across every task list (Today, Tasks, Lists, Saved
/// Search). Calm and scannable:
///
/// - a leading completion circle, tinted by priority, that you tap to check the
///   task off **without** opening its detail inspector;
/// - the title, struck through and dimmed once the task is done or cancelled;
/// - one compact metadata line that reads as a single unit — the due date
///   (tinted when overdue) leads, followed by estimate and tags, the last tags
///   dropping whole when the line runs out of room — rendered only
///   when there's something to say. Due and overdue share this inline treatment
///   so the row never strands a badge against the far edge.
/// - a Started marker on a task the user has begun, and a blocked marker when
///   the host says the task's dependencies are still open.
/// - on Today, the task's time leading the metadata line, and status chips the
///   host supplies ("Until 3:00 PM", "Pushed 4 times").
///
/// Priority is carried by the circle's tint and status by its glyph, so the row
/// needs no redundant "Open" / "P2" status or priority text.
struct LorvexTaskRow: View {
  let task: LorvexTask
  var isSelected: Bool = false
  /// Mark the task as waiting on a dependency. Supplied by the host rather than
  /// derived here: whether a task is blocked depends on the *other* rows' statuses,
  /// which a single row cannot see. The row stays fully interactive — the answer to
  /// a blocked task is usually to open it or push it out, not to be unable to touch
  /// it.
  var isBlocked: Bool = false
  /// The task's owning list, shown leading in the metadata line on cross-list
  /// surfaces (Tasks, Today) where which list a task belongs to is
  /// important context. `nil` on single-list surfaces, where it is redundant.
  var owningList: TaskRowListLabel? = nil
  /// The task's time today ("2:00 – 3:00 PM"), leading the metadata line.
  /// Supplied by Today and by the list surfaces for today's timed tasks;
  /// `nil` for a task with no time today.
  var timeLabel: String? = nil
  /// The time is running now, so `timeLabel` reads "Until 12:30 PM" and is
  /// drawn in the accent color.
  var timeIsRunning: Bool = false
  /// Host-supplied status chips shown under the title beside the in-progress
  /// and blocked badges.
  var chips: [LorvexTaskRowChip] = []
  /// Tap-to-complete from the leading circle. When `nil` the circle is read-only
  /// (e.g. previews, or surfaces that don't own a completion action).
  var onToggleComplete: (() -> Void)?

  /// The zone the due facts count days in, so they agree with the lists the
  /// product's logical day builds.
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  private var isDone: Bool { task.status == .completed }
  private var isCancelled: Bool { task.status == .cancelled }
  /// Started work carries a restrained "Started" marker; the leading circle is
  /// unchanged (tap still completes) and the badge disappears with the status.
  private var isInProgress: Bool { task.status == .inProgress }
  /// Someday tasks are parked, not finished — the title stays upright (no
  /// strikethrough) but reads muted, and the row carries its own dormant glyph.
  private var isSomeday: Bool { task.status == .someday }
  private var isInactive: Bool { isDone || isCancelled }
  /// Tasks that should read as set-aside rather than active open work: finished,
  /// cancelled, or parked in Someday/Maybe.
  private var isDormant: Bool { isInactive || isSomeday }

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      completionCircle

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(userContent: task.title)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(isDormant ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .strikethrough(isInactive, color: .secondary)
          .lineLimit(2)

        if isInProgress || isBlocked || !chips.isEmpty {
          HStack(spacing: LorvexDesign.Spacing.xs) {
            ForEach(chips) { chip in
              chipView(chip)
            }
            if isInProgress { inProgressBadge }
            if isBlocked { blockedBadge }
          }
        }

        metadataLine
      }

      Spacer(minLength: LorvexDesign.Spacing.s)
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .background(rowBackground)
    .contentShape(Rectangle())
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      taskAccessibilityLabel(
        task, timeLabel: timeLabel, details: accessibilityDetails,
        timeZone: productTimeZone))
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    // The leading completion circle is `accessibilityHidden`, so expose its
    // action on the combined row — otherwise VoiceOver users can't check a task
    // off (the row's default activation only selects/opens it).
    .accessibilityAction(named: Text(TaskDisplayText.completionToggle(isDone: isDone))) {
      if !isCancelled, !isSomeday { onToggleComplete?() }
    }
    .accessibilityIdentifier("task.row.\(task.id)")
    .reduceMotionAnimation(.snappy(duration: 0.16), value: isSelected)
  }

  @ViewBuilder
  private var rowBackground: some View {
    if isSelected {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .fill(LorvexDesign.Palette.selectionFill)
    }
  }

  private var completionCircle: some View {
    Button {
      onToggleComplete?()
    } label: {
      Image(systemName: task.statusCircleGlyph)
        .font(LorvexDesign.Typography.primaryText)
        .imageScale(.large)
        .foregroundStyle(task.statusCircleStyle)
        // Native symbol cross-fade when the glyph flips on complete / reopen,
        // so checking a task off animates in place rather than snapping — plus a
        // small bounce on the state change so completion feels rewarding.
        .contentTransition(.symbolEffect(.replace))
        .reduceMotionBounce(value: isDone)
        .frame(width: 24, height: 24)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    // Cancelled and someday tasks have no "check it off" affordance — a parked
    // task is activated from its menu, not by tapping a completion circle.
    .disabled(onToggleComplete == nil || isCancelled || isSomeday)
    .help(TaskDisplayText.completionToggle(isDone: isDone))
    .accessibilityHidden(true)
  }

  private func chipView(_ chip: LorvexTaskRowChip) -> some View {
    LorvexChip(chip.title, systemImage: chip.systemImage, tint: chip.tint)
      .accessibilityIdentifier("task.row.chip.\(chip.id)")
  }

  /// A small accent capsule marking a started task: a `play.fill` glyph and
  /// short label in the app accent, the same "Started" the widgets and the
  /// watch show.
  private var inProgressBadge: some View {
    LorvexChip(
      String(localized: "task.row.started", defaultValue: "Started", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "play.fill",
      tint: LorvexDesign.Palette.accent
    )
  }

  /// A muted capsule marking a task whose dependencies are still open. Deliberately
  /// quieter than ``inProgressBadge`` and not tinted like an error: being blocked is
  /// a fact about the day's shape, not something the user did wrong.
  private var blockedBadge: some View {
    LorvexChip(
      TaskDisplayText.blocked,
      systemImage: "lock.fill",
      tint: LorvexDesign.Palette.blocked
    )
  }

  /// What the row shows beyond the task's own fields, for VoiceOver, in the
  /// row's order: host chips, the blocked badge, the owning list, and the day
  /// a hidden task comes back.
  private var accessibilityDetails: [String] {
    var details = chips.map(\.title)
    if isBlocked { details.append(TaskDisplayText.blocked) }
    if let owningList { details.append(owningList.name) }
    if let hiddenLabel = task.hiddenUntilShortLabel(timeZone: productTimeZone) {
      details.append(TaskDisplayText.hiddenUntil(hiddenLabel))
    }
    return details
  }

  /// The estimate, then up to three tags: the calm part of the metadata that
  /// always reads `.secondary`. The due date is rendered separately so it can
  /// carry its own (overdue) tint. A row showing Today's time drops the
  /// estimate, since the time already says how long the work takes.
  private var calmMetadata: [String] {
    var parts: [String] = []
    if timeLabel == nil, let minutes = task.estimatedMinutes {
      parts.append(LorvexDurationFormat.minutes(minutes))
    }
    parts.append(contentsOf: task.tags.prefix(3))
    return parts
  }

  /// One inline metadata line: Today's time leads when the host supplies one, then the owning list, the "Hidden until" badge for a deferred-until
  /// task, the due date (red when overdue, orange when due today or tomorrow), and finally estimate and tags. Rendered only when at least one piece
  /// exists, so an empty row stays a clean title.
  @ViewBuilder
  private var metadataLine: some View {
    let dueLabel = task.cachedDueRelativeLabel(timeZone: productTimeZone)
    let isDueOverdue = task.isOverdue(timeZone: productTimeZone)
    let isDueSoon = !isDueOverdue && task.isDueSoon(timeZone: productTimeZone)
    // Hidden-until only surfaces on rows that reach a list at all (Scheduled
    // section, search); on the day surfaces the task is filtered out entirely.
    let hiddenLabel = task.hiddenUntilShortLabel(timeZone: productTimeZone)
    let calm = calmMetadata
    if timeLabel != nil || owningList != nil || hiddenLabel != nil || dueLabel != nil
      || !calm.isEmpty
    {
      HStack(spacing: LorvexDesign.Spacing.sm) {
        if let timeLabel {
          // The time leads: it is when the work happens today.
          HStack(spacing: LorvexDesign.Spacing.xs) {
            Image(systemName: "clock").accessibilityHidden(true)
            Text(timeLabel).monospacedDigit()
          }
          .foregroundStyle(
            timeIsRunning ? AnyShapeStyle(LorvexDesign.Palette.accent) : AnyShapeStyle(.secondary))
          .layoutPriority(2)
          if owningList != nil || hiddenLabel != nil || dueLabel != nil {
            Text("·").foregroundStyle(.tertiary)
          }
        }
        if let owningList {
          // The owning list leads in its own color so a task's home is the first
          // thing you read on a cross-list surface.
          HStack(spacing: LorvexDesign.Spacing.xs) {
            LorvexListIconView(
              icon: owningList.icon,
              tint: owningList.tint,
              size: 11,
              font: LorvexDesign.Typography.tertiaryText)
            Text(owningList.name)
          }
          .foregroundStyle(owningList.tint)
          .lineLimit(1)
          .layoutPriority(1)
        }
        if let hiddenLabel {
          if owningList != nil { Text("·").foregroundStyle(.tertiary) }
          // Muted like the Someday/moon treatment — a parked, set-aside state
          // rather than active work.
          HStack(spacing: LorvexDesign.Spacing.xs) {
            Image(systemName: "eye.slash").accessibilityHidden(true)
            Text(TaskDisplayText.hiddenUntil(hiddenLabel)).monospacedDigit()
          }
          .foregroundStyle(.secondary)
        }
        if let due = dueLabel {
          if owningList != nil || hiddenLabel != nil { Text("·").foregroundStyle(.tertiary) }
          HStack(spacing: LorvexDesign.Spacing.xs) {
            Image(systemName: isDueOverdue ? "clock.badge.exclamationmark" : "calendar")
              .accessibilityHidden(true)
            Text(due).monospacedDigit()
          }
          .foregroundStyle(
            isDueOverdue
              ? AnyShapeStyle(LorvexDesign.Palette.overdue)
              : isDueSoon ? AnyShapeStyle(LorvexDesign.Palette.dueSoon) : AnyShapeStyle(.secondary))
        }
        if !calm.isEmpty {
          // Short of room, the last tags drop whole rather than truncating.
          LorvexWholeLabelsLine(
            calm,
            leadingSeparator: timeLabel != nil || owningList != nil || hiddenLabel != nil
              || dueLabel != nil,
            spacing: LorvexDesign.Spacing.sm)
        }
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .lineLimit(1)
    }
  }

}

/// A task's owning-list label for ``LorvexTaskRow``'s metadata line: the list
/// name plus its icon (SF Symbol or emoji, rendered by ``LorvexListIconView``)
/// and accent tint.
struct TaskRowListLabel: Equatable {
  let name: String
  let icon: String?
  let tint: Color
}

/// Store-bound `LorvexTaskRow`: the single task row used by every list surface.
/// Wires the leading circle to `toggleTaskCompletion` (so checking off never
/// changes the selection) once, so hosts only pass `store` and `task` and layer
/// on their own `.tag` / `.contextMenu` / drop targets.
struct TaskRowItem: View {
  @Bindable var store: AppStore
  let task: LorvexTask
  /// See ``LorvexTaskRow/isBlocked``.
  var isBlocked: Bool = false
  /// Show the task's owning list in the row metadata — set on cross-list surfaces
  /// (Tasks, Today); left off where the surface is a single list.
  var showsOwningList: Bool = false
  /// See ``LorvexTaskRow/timeLabel``.
  var timeLabel: String? = nil
  /// See ``LorvexTaskRow/timeIsRunning``.
  var timeIsRunning: Bool = false
  /// See ``LorvexTaskRow/chips``.
  var chips: [LorvexTaskRowChip] = []
  @Environment(\.undoManager) private var undoManager

  private var isSelected: Bool { store.selectedTaskID == task.id }

  /// Resolve the task's owning list to a row label, when the surface asks for it.
  private var owningListLabel: TaskRowListLabel? {
    guard showsOwningList, let listID = task.listID,
      let list = store.lists?.lists.first(where: { $0.id == listID })
    else { return nil }
    return TaskRowListLabel(
      name: list.displayName, icon: list.icon, tint: Color(lorvexHex: list.color) ?? .secondary)
  }

  var body: some View {
    LorvexTaskRow(
      task: task, isSelected: isSelected, isBlocked: isBlocked,
      owningList: owningListLabel, timeLabel: timeLabel, timeIsRunning: timeIsRunning,
      chips: chips
    ) {
      Task { await store.toggleTaskCompletion(task, undoManager: undoManager) }
    }
  }
}

