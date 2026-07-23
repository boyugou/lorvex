import LorvexCore
import SwiftUI

/// The unified mobile task row — calm and scannable, and aligned with the
/// macOS `LorvexTaskRow`:
///
/// - a leading completion circle tinted by priority (P1 red, P2 orange, P3 quiet),
///   its glyph carrying status (open / done / cancelled / someday);
/// - the title at body size, struck through and dimmed once resolved;
/// - one compact metadata line — due date leading (orange when overdue), then
///   estimate and tags — rendered only when there's something to say;
/// - a trailing focus marker for tasks pulled into the day's focus.
///
/// Priority is carried by the circle's tint and status by its glyph, so the row
/// needs no redundant "p1" / "Open" text.
struct MobileTaskRow: View, Equatable {
  let task: LorvexTask
  var isFocused: Bool = false
  /// Hidden when the parent renders its own tappable completion circle alongside.
  var showsLeadingCircle: Bool = true

  var body: some View {
    NavigationLink(value: MobileRoute.task(task.id)) {
      MobileTaskRowContent(task: task, isFocused: isFocused, showsLeadingCircle: showsLeadingCircle)
        .equatable()
    }
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
    .lorvexRowHoverEffect()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(taskAccessibilityLabel(task, isFocused: isFocused, vocabulary: .mobileLocalized))
    .accessibilityIdentifier("mobile.task.row.\(task.id)")
  }
}

struct MobileTaskRowContent: View, Equatable {
  let task: LorvexTask
  var isFocused: Bool = false
  /// Hidden when a leading batch-selection checkbox takes the slot instead.
  var showsLeadingCircle: Bool = true

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
          .frame(width: 26, height: 26)
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(task.title)
          .font(.body)
          .foregroundStyle(isDormant ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .strikethrough(isInactive, color: .secondary)
          .lineLimit(2)
        if isInProgress { inProgressBadge }
        metadataLine
      }

      Spacer(minLength: LorvexDesign.Spacing.s)

      if isFocused {
        Image(systemName: "scope")
          .font(.footnote)
          .foregroundStyle(LorvexDesign.Palette.focus)
          .accessibilityHidden(true)
          .padding(.top, 3)
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.xs)
  }

  /// A small accent capsule marking a started task — the primary in_progress
  /// signal on the mobile row (watch / widgets deliberately omit it in v1).
  private var inProgressBadge: some View {
    HStack(spacing: 3) {
      Image(systemName: "play.fill").imageScale(.small).accessibilityHidden(true)
      Text(
        String(
          localized: "task.status.in_progress", defaultValue: "In Progress", table: "Localizable",
          bundle: MobileL10n.bundle))
    }
    .font(.caption2)
    .foregroundStyle(.tint)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.accentColor.opacity(0.14), in: Capsule())
    .accessibilityElement(children: .combine)
  }

  /// Estimate and tags, joined — the calm part of the metadata; the due date is
  /// rendered separately so it can carry its own overdue tint.
  private var estimateAndTags: String? {
    var parts: [String] = []
    if let minutes = task.estimatedMinutes {
      parts.append(MobileTaskDisplayText.compactEstimateMinutes(minutes))
    }
    parts.append(contentsOf: task.tags.prefix(2))
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  @ViewBuilder
  private var metadataLine: some View {
    let dueLabel = task.cachedDueRelativeLabel()
    let isDueOverdue = task.isOverdue()
    let rest = estimateAndTags
    if dueLabel != nil || rest != nil || task.recurrence != nil {
      HStack(spacing: 5) {
        if let due = dueLabel {
          HStack(spacing: 3) {
            Image(systemName: isDueOverdue ? "clock.badge.exclamationmark" : "calendar")
              .accessibilityHidden(true)
            Text(due).monospacedDigit()
          }
          .foregroundStyle(isDueOverdue ? AnyShapeStyle(LorvexDesign.Palette.dueSoon) : AnyShapeStyle(.secondary))
        }
        if task.recurrence != nil {
          if dueLabel != nil { Text("·").foregroundStyle(.tertiary) }
          Image(systemName: "repeat").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        if let rest {
          if dueLabel != nil || task.recurrence != nil {
            Text("·").foregroundStyle(.tertiary)
          }
          Text(rest).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      .font(.footnote)
      .lineLimit(1)
    }
  }
}

struct MobileActionTaskRow: View {
  let task: LorvexTask
  let isFocused: Bool
  let isMutating: Bool
  let select: () -> Void
  let toggleFocus: () async -> Void
  let complete: () async -> Void
  let deferTask: () async -> Void
  /// Start / Mark-as-Not-Started, threaded on surfaces (Today) that own the
  /// in_progress toggle. `nil` elsewhere, where the swipe/menu simply omits it.
  var start: (() async -> Void)? = nil
  var markNotStarted: (() async -> Void)? = nil

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      MobileTaskCompletionCircle(task: task, isMutating: isMutating, complete: complete)
      MobileTaskRow(task: task, isFocused: isFocused, showsLeadingCircle: false)
        .equatable()
        .simultaneousGesture(TapGesture().onEnded(select))
    }
    // Long-press (iPhone) / right-click (iPad pointer) context menu mirrors the
    // swipe actions — the standard iOS/iPadOS row idiom, which swipe alone
    // doesn't satisfy for pointer users.
    .taskRowActions(
      task: task,
      isFocused: isFocused,
      isMutating: isMutating,
      isBatchSelecting: false,
      toggleFocus: toggleFocus,
      complete: complete,
      deferTask: deferTask,
      start: start,
      markNotStarted: markNotStarted)
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
        .frame(width: 26, height: 26)
        .contentShape(Circle())
        .padding(.top, LorvexDesign.Spacing.xs)
    }
    .buttonStyle(.borderless)
    .disabled(isMutating || task.status.isResolved)
    .lorvexSensoryFeedback(.success, trigger: isCompleting) { _, now in now }
    .accessibilityLabel(
      task.status.isResolved
        ? String(
          localized: "task.row.completed.a11y", defaultValue: "Completed", table: "Localizable",
          bundle: MobileL10n.bundle)
        : String(
          localized: "action.complete", defaultValue: "Complete", table: "Localizable",
          bundle: MobileL10n.bundle)
    )
    .accessibilityIdentifier("mobile.task.complete.\(task.id)")
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
