import LorvexCore
import SwiftUI

/// The unified mobile task row — calm and scannable, and aligned with the
/// macOS `LorvexTaskRow`:
///
/// - a leading completion circle tinted by priority (P1 red, P2 orange, P3 quiet),
///   its glyph carrying status (open / done / cancelled / someday);
/// - the title at body size, struck through and dimmed once resolved, on up
///   to two lines, or as many as it needs at accessibility text sizes;
/// - chips for state that explains the row: Started, Blocked, and whatever the
///   host adds ("Until 3:00 PM", "Pushed 4 times");
/// - the metadata (``MobileTaskMetadataLine``) — the task's time today when
///   the host supplies it, the due date (red when overdue), a repeat glyph,
///   then estimate and tags — on one line whose last tags drop whole when it
///   runs out of room, wrapping instead at accessibility text sizes; rendered
///   only when there's something to say.
///
/// Priority is carried by the circle's tint and status by its glyph, so the row
/// needs no redundant "p1" / "Open" text. The row opens the task without a
/// trailing disclosure chevron: a task row is plainly tappable, and the
/// chevron would only crowd the title.
struct MobileTaskRow: View, Equatable {
  let task: LorvexTask
  /// See ``MobileTaskRowContent/isBlocked``.
  var isBlocked: Bool = false
  /// Hidden when the parent renders its own tappable completion circle alongside.
  var showsLeadingCircle: Bool = true
  /// See ``MobileTaskRowContent/timeLabel``.
  var timeLabel: String? = nil
  /// See ``MobileTaskRowContent/timeIsRunning``.
  var timeIsRunning: Bool = false
  /// See ``MobileTaskRowContent/chips``.
  var chips: [LorvexTaskRowChip] = []
  /// See ``MobileTaskRowContent/timeZone``.
  var timeZone: TimeZone = .autoupdatingCurrent

  var body: some View {
    NavigationLink(value: MobileRoute.task(task.id)) {
      MobileTaskRowContent(
        task: task, isBlocked: isBlocked, showsLeadingCircle: showsLeadingCircle,
        timeLabel: timeLabel, timeIsRunning: timeIsRunning, chips: chips, timeZone: timeZone
      )
      .equatable()
    }
    .navigationLinkIndicatorVisibility(.hidden)
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
    .lorvexRowHoverEffect()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      taskAccessibilityLabel(
        task, timeLabel: timeLabel,
        details: chips.map(\.title) + (isBlocked ? [MobileTaskDisplayText.blocked] : []),
        timeZone: timeZone))
    .accessibilityIdentifier("mobile.task.row.\(task.id)")
  }
}

struct MobileTaskRowContent: View, Equatable {
  let task: LorvexTask
  /// Mark the task as waiting on a dependency. Supplied by the host rather than
  /// derived here: whether a task is blocked depends on the *other* rows'
  /// statuses, which a single row cannot see. The row stays fully interactive —
  /// the answer to a blocked task is usually to open it or push it out.
  var isBlocked: Bool = false
  /// Hidden when a leading batch-selection checkbox takes the slot instead.
  var showsLeadingCircle: Bool = true
  /// The task's time today ("10:55 AM – 11:55 AM"), leading the metadata line.
  /// Supplied by Today and by the task lists for today's timed tasks; `nil`
  /// for a task with no time today.
  var timeLabel: String? = nil
  /// The time is running now, so `timeLabel` reads "Until 12:30 PM" and is
  /// drawn in the accent color.
  var timeIsRunning: Bool = false
  /// Status chips the host supplies ("Until 3:00 PM", "Pushed 4 times"), drawn
  /// beside the Started and Blocked badges. Display only.
  var chips: [LorvexTaskRowChip] = []
  /// The zone the due facts count days in: the product time zone the host
  /// reads from the environment (`lorvexProductTimeZone`), so they agree with
  /// the lists the product's logical day builds. A stored
  /// value rather than an environment read, so the synthesized equality that
  /// lets the row skip redraws also notices a change of zone.
  var timeZone: TimeZone = .autoupdatingCurrent

  private var isDone: Bool { task.status == .completed }
  private var isCancelled: Bool { task.status == .cancelled }
  private var isSomeday: Bool { task.status == .someday }
  private var isInProgress: Bool { task.status == .inProgress }
  private var isInactive: Bool { isDone || isCancelled }
  private var isDormant: Bool { isInactive || isSomeday }

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      if showsLeadingCircle {
        Image(systemName: task.statusCircleGlyph)
          .font(.title3)
          .foregroundStyle(task.statusCircleStyle)
          .mobileTaskCircleFrame()
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(userContent: task.title)
          .font(.body)
          .foregroundStyle(isDormant ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .strikethrough(isInactive, color: .secondary)
          .lineLimitUnlessAccessibilitySize(2)
        if isInProgress || isBlocked || !chips.isEmpty {
          HStack(spacing: LorvexDesign.Spacing.xs) {
            ForEach(chips) { chip in
              chipBadge(chip)
            }
            if isInProgress { inProgressBadge }
            if isBlocked { blockedBadge }
          }
        }
        metadataLine
      }

      Spacer(minLength: LorvexDesign.Spacing.s)
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }

  /// A host's status chip, in the same capsule as the status badges.
  private func chipBadge(_ chip: LorvexTaskRowChip) -> some View {
    HStack(spacing: 3) {
      if let systemImage = chip.systemImage {
        Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true)
      }
      Text(chip.title)
    }
    .font(.caption2.weight(.medium))
    .foregroundStyle(chip.tint)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(chip.tint.opacity(0.14), in: Capsule())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("mobile.task.row.chip.\(chip.id)")
  }

  /// A small accent capsule marking a started task, the "Started" the macOS
  /// row, the widgets, and the watch show.
  private var inProgressBadge: some View {
    HStack(spacing: 3) {
      Image(systemName: "play.fill").imageScale(.small).accessibilityHidden(true)
      Text(
        String(
          localized: "task.row.started", defaultValue: "Started", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
    .font(.caption2)
    .foregroundStyle(.tint)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.accentColor.opacity(0.14), in: Capsule())
    .accessibilityElement(children: .combine)
  }

  /// A muted capsule marking a task whose dependencies are still open. Quieter
  /// than ``inProgressBadge`` and not tinted like an error: being blocked is a
  /// fact about the day's shape, not something the user did wrong.
  private var blockedBadge: some View {
    HStack(spacing: 3) {
      Image(systemName: "lock.fill").imageScale(.small).accessibilityHidden(true)
      Text(MobileTaskDisplayText.blocked)
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.secondary.opacity(0.12), in: Capsule())
    .accessibilityElement(children: .combine)
  }

  /// The estimate, then up to two tags: the calm part of the metadata. The due
  /// date is rendered separately so it can carry its own overdue tint. A row
  /// showing Today's time drops the estimate, since the time already says how
  /// long the work takes.
  private var calmMetadata: [String] {
    var parts: [String] = []
    if timeLabel == nil, let minutes = task.estimatedMinutes {
      parts.append(LorvexDurationFormat.minutes(minutes))
    }
    parts.append(contentsOf: task.tags.prefix(2))
    return parts
  }

  @ViewBuilder
  private var metadataLine: some View {
    let dueLabel = task.cachedDueRelativeLabel(timeZone: timeZone)
    let calm = calmMetadata
    if timeLabel != nil || dueLabel != nil || task.recurrence != nil || !calm.isEmpty {
      MobileTaskMetadataLine(
        timeLabel: timeLabel, timeIsRunning: timeIsRunning, dueLabel: dueLabel,
        isOverdue: task.isOverdue(timeZone: timeZone), isDueSoon: task.isDueSoon(timeZone: timeZone),
        repeats: task.recurrence != nil, calmLabels: calm)
    }
  }
}

/// A task row with its actions: the completion circle, the row that opens
/// the task, and the shared swipe actions and context menu
/// (``MobileTaskRowActions``).
struct MobileActionTaskRow: View {
  let task: LorvexTask
  /// See ``MobileTaskRowContent/isBlocked``.
  var isBlocked: Bool = false
  let isMutating: Bool
  let actions: MobileTaskRowActions
  /// See ``MobileTaskRowContent/timeLabel``.
  var timeLabel: String? = nil
  /// See ``MobileTaskRowContent/timeIsRunning``.
  var timeIsRunning: Bool = false
  /// See ``MobileTaskRowContent/chips``.
  var chips: [LorvexTaskRowChip] = []
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      MobileTaskCompletionCircle(task: task, isMutating: isMutating, complete: actions.complete)
      // `MobileTaskRow` is itself a `NavigationLink(value: .task(id))`; it pushes
      // the detail onto the active stack (`routePath` / `tasksRoutePath`). It
      // must NOT carry a competing tap gesture — a `simultaneousGesture`
      // `TapGesture` races the link's own recognizer and intermittently
      // swallows the activation, so taps only sometimes open the detail. The
      // regular/iPad split view syncs `selectedTaskID` through its own
      // `List(selection:)` row instead.
      MobileTaskRow(
        task: task, isBlocked: isBlocked, showsLeadingCircle: false, timeLabel: timeLabel,
        timeIsRunning: timeIsRunning, chips: chips, timeZone: productTimeZone
      )
      .equatable()
    }
    // Long-press (iPhone) / right-click (iPad pointer) context menu mirrors the
    // swipe actions — the standard iOS/iPadOS row idiom, which swipe alone
    // doesn't satisfy for pointer users.
    .taskRowActions(task: task, actions: actions, isMutating: isMutating, isBatchSelecting: false)
  }
}

/// The leading priority/status circle rendered as a real checkbox: tapping it
/// completes an open task with a symbol cross-fade to a filled check, a spring
/// pop, and a success haptic, letting that land (300 ms) before the task
/// resolves and the row leaves the list. Borderless so it owns only its own hit
/// area — the rest of the row still navigates or selects. Disabled once the task
/// is resolved. Shared by the compact action row and the regular/iPad workspace
/// row so both give the same completion moment.
struct MobileTaskCompletionCircle: View {
  let task: LorvexTask
  let isMutating: Bool
  let complete: () async -> Void
  /// Drives the tap-to-complete animation: the circle springs to a filled check
  /// and pops before the row actually resolves and leaves the list.
  @State private var isCompleting = false

  var body: some View {
    Button(action: triggerComplete) {
      Image(systemName: showsCheck ? "checkmark.circle.fill" : task.statusCircleGlyph)
        .font(.title3)
        .foregroundStyle(showsCheck ? AnyShapeStyle(LorvexDesign.Palette.done) : task.statusCircleStyle)
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce, value: isCompleting)
        .scaleEffect(isCompleting ? 1.18 : 1)
        .mobileTaskCircleFrame()
        .contentShape(Circle())
        .padding(.top, LorvexDesign.Spacing.xs)
    }
    .buttonStyle(.borderless)
    .disabled(isMutating || task.status.isResolved)
    .lorvexSensoryFeedback(.success, trigger: isCompleting) { _, now in now }
    .accessibilityLabel(spokenLabel)
    .accessibilityIdentifier("mobile.task.complete.\(task.id)")
  }

  /// The circle to VoiceOver: the Complete action while the task can still be
  /// completed, else the state its glyph shows.
  private var spokenLabel: String {
    switch task.status {
    case .completed:
      String(
        localized: "task.row.completed.a11y", defaultValue: "Completed", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .cancelled:
      LorvexTask.Status.cancelled.localizedName
    case .open, .inProgress, .someday:
      MobileTaskActionCopy.complete
    }
  }

  /// The circle reads as checked while the completion animation plays and once
  /// the task is actually resolved.
  private var showsCheck: Bool {
    isCompleting || task.status == .completed
  }

  private func triggerComplete() {
    guard !task.status.isResolved, !isMutating, !isCompleting else { return }
    withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) {
      isCompleting = true
    }
    Task {
      // Let the fill + pop land before the task resolves and the row leaves.
      try? await Task.sleep(for: .milliseconds(300))
      await complete()
      isCompleting = false
    }
  }
}
