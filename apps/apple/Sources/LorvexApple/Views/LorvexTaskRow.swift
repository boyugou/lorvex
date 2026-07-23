import LorvexCore
import SwiftUI

/// The unified task row used across every task list (Today, Tasks, Lists, Saved
/// Search). Calm and scannable:
///
/// - a leading completion circle, tinted by priority, that you tap to check the
///   task off **without** opening its detail inspector;
/// - the title, struck through and dimmed once the task is done or cancelled;
/// - one compact metadata line that reads as a single unit — the due date
///   (tinted when overdue) leads, followed by estimate and tags — rendered only
///   when there's something to say. Due and overdue share this inline treatment
///   so the row never strands a badge against the far edge.
/// - a trailing focus marker for tasks pulled into the day's focus.
///
/// Priority is carried by the circle's tint and status by its glyph, so the row
/// needs no redundant "Open" / "P2" status or priority text.
struct LorvexTaskRow: View {
  let task: LorvexTask
  var isFocused: Bool = false
  var isSelected: Bool = false
  /// The task's owning list, shown leading in the metadata line on cross-list
  /// surfaces (Tasks, Today) where which list a task belongs to is
  /// important context. `nil` on single-list surfaces, where it is redundant.
  var owningList: TaskRowListLabel? = nil
  /// Tap-to-complete from the leading circle. When `nil` the circle is read-only
  /// (e.g. previews, or surfaces that don't own a completion action).
  var onToggleComplete: (() -> Void)?

  private var isDone: Bool { task.status == .completed }
  private var isCancelled: Bool { task.status == .cancelled }
  /// Started work carries a restrained "In Progress" marker; the leading circle
  /// is unchanged (tap still completes) and the badge disappears with the status.
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

      VStack(alignment: .leading, spacing: 3) {
        Text(task.title)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(isDormant ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .strikethrough(isInactive, color: .secondary)
          .lineLimit(2)

        if isInProgress { inProgressBadge }

        metadataLine
      }

      Spacer(minLength: LorvexDesign.Spacing.s)

      trailing
        .padding(.top, 1)
    }
    .padding(.vertical, LorvexDesign.Spacing.s)
    .padding(.horizontal, LorvexDesign.Spacing.s)
    .background(rowBackground)
    .contentShape(Rectangle())
    .draggable(LorvexTaskRef(id: task.id, title: task.title))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(taskAccessibilityLabel(task, isFocused: isFocused, vocabulary: .lorvexLocalized))
    .accessibilityAddTraits(.isButton)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    // The leading completion circle is `accessibilityHidden`, so expose its
    // action on the combined row — otherwise VoiceOver users can't check a task
    // off (the row's default activation only selects/opens it).
    .accessibilityAction(named: Text(completionActionTitle)) {
      if !isCancelled, !isSomeday { onToggleComplete?() }
    }
    .accessibilityIdentifier("task.row.\(task.id)")
    .reduceMotionAnimation(.snappy(duration: 0.16), value: isSelected)
  }

  @ViewBuilder
  private var rowBackground: some View {
    if isSelected {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
        .fill(.quaternary.opacity(0.42))
        .overlay {
          RoundedRectangle(cornerRadius: LorvexDesign.Radius.s)
            .stroke(.secondary.opacity(0.12), lineWidth: 0.5)
        }
    }
  }

  private var completionActionTitle: LocalizedStringResource {
    isDone
      ? LocalizedStringResource("common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle)
      : LocalizedStringResource("common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var completionCircle: some View {
    Button {
      onToggleComplete?()
    } label: {
      Image(systemName: circleGlyph)
        .font(LorvexDesign.Typography.primaryText)
        .foregroundStyle(circleStyle)
        // Native symbol cross-fade when the glyph flips on complete / reopen,
        // so checking a task off animates in place rather than snapping — plus a
        // small bounce on the state change so completion feels rewarding.
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce, value: isDone)
        .frame(width: 20, height: 20)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    // Cancelled and someday tasks have no "check it off" affordance — a parked
    // task is activated from its menu, not by tapping a completion circle.
    .disabled(onToggleComplete == nil || isCancelled || isSomeday)
    .help(
      isDone
        ? String(localized: "common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle)
        : String(localized: "common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle)
    )
    .accessibilityHidden(true)
  }

  private var circleGlyph: String {
    if isDone { return "checkmark.circle.fill" }
    if isCancelled { return "xmark.circle" }
    if isSomeday { return "moon" }
    return "circle"
  }

  private var circleStyle: AnyShapeStyle {
    if isDone { return AnyShapeStyle(.green) }
    if isCancelled { return AnyShapeStyle(.tertiary) }
    if isSomeday { return AnyShapeStyle(.secondary) }
    return AnyShapeStyle(task.priority.priorityTint)
  }

  /// A small accent capsule marking a started task. Restrained: a `play.fill`
  /// glyph and short label, tinted with the app accent — the primary in_progress
  /// signal on the row (watch / widgets deliberately omit it in v1).
  private var inProgressBadge: some View {
    HStack(spacing: 3) {
      Image(systemName: "play.fill").imageScale(.small).accessibilityHidden(true)
      Text(String(localized: "task.status.in_progress", defaultValue: "In Progress", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .font(LorvexDesign.Typography.tertiaryText)
    .foregroundStyle(.tint)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.accentColor.opacity(0.14), in: Capsule())
    .accessibilityElement(children: .combine)
  }

  /// Estimate and tags, joined — the calm part of the metadata that always reads
  /// `.secondary`. The due date is rendered separately so it can carry its own
  /// (overdue) tint.
  private var estimateAndTags: String? {
    var parts: [String] = []
    if let minutes = task.estimatedMinutes { parts.append(lorvexMinutesLabel(minutes)) }
    parts.append(contentsOf: task.tags.prefix(3))
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// One inline metadata line: the owning list leads, then the "Hidden until"
  /// badge for a deferred-until task, the due date (tinted orange when overdue),
  /// and finally estimate and tags. Rendered only when at least one piece
  /// exists, so an empty row stays a clean title.
  @ViewBuilder
  private var metadataLine: some View {
    let dueLabel = task.cachedDueRelativeLabel()
    let isDueOverdue = task.isOverdue()
    // Hidden-until only surfaces on rows that reach a list at all (Scheduled
    // section, search); on the day surfaces the task is filtered out entirely.
    let hiddenLabel = task.hiddenUntilShortLabel()
    let estimateAndTags = estimateAndTags
    if owningList != nil || hiddenLabel != nil || dueLabel != nil || estimateAndTags != nil {
      HStack(spacing: 6) {
        if let owningList {
          // The owning list leads in its own color so a task's home is the first
          // thing you read on a cross-list surface.
          HStack(spacing: 3) {
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
          HStack(spacing: 3) {
            Image(systemName: "eye.slash").accessibilityHidden(true)
            Text(String(
              format: String(
                localized: "task.row.hidden_until", defaultValue: "Hidden until %@",
                table: "Localizable",
                bundle: LorvexL10n.bundle),
              hiddenLabel
            )).monospacedDigit()
          }
          .foregroundStyle(.secondary)
        }
        if let due = dueLabel {
          if owningList != nil || hiddenLabel != nil { Text("·").foregroundStyle(.tertiary) }
          HStack(spacing: 3) {
            Image(systemName: isDueOverdue ? "clock.badge.exclamationmark" : "calendar")
              .accessibilityHidden(true)
            Text(due).monospacedDigit()
          }
          .foregroundStyle(isDueOverdue ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        if let rest = estimateAndTags {
          if owningList != nil || hiddenLabel != nil || dueLabel != nil {
            Text("·").foregroundStyle(.tertiary)
          }
          Text(rest).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .lineLimit(1)
    }
  }

  @ViewBuilder
  private var trailing: some View {
    if isFocused {
      Image(systemName: "scope")
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
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
  var isFocused: Bool = false
  /// Show the task's owning list in the row metadata — set on cross-list surfaces
  /// (Tasks, Today); left off where the surface is a single list.
  var showsOwningList: Bool = false
  @Environment(\.undoManager) private var undoManager

  private var isSelected: Bool { store.selectedTaskID == task.id }

  /// Resolve the task's owning list to a row label, when the surface asks for it.
  private var owningListLabel: TaskRowListLabel? {
    guard showsOwningList, let listID = task.listID,
      let list = store.lists?.lists.first(where: { $0.id == listID })
    else { return nil }
    return TaskRowListLabel(
      name: list.name, icon: list.icon, tint: Color(lorvexHex: list.color) ?? .secondary)
  }

  var body: some View {
    LorvexTaskRow(
      task: task, isFocused: isFocused, isSelected: isSelected, owningList: owningListLabel
    ) {
      Task { await store.toggleTaskCompletion(task, undoManager: undoManager) }
    }
  }
}
