import LorvexCore
import SwiftUI

/// A circular progress ring with the habit's icon (or a check when met) at its
/// center. Clicking it checks the habit in (``HabitRingAction``) — the primary
/// check-in target on a habit's card and in its inspector's header. The track
/// is the neutral tertiary style, not a wash of `tint`: until something is
/// logged the track outlines the whole control, and a hue at low alpha all but
/// vanishes on the card for deep hues in dark mode and for every hue in light
/// mode. The stroke and the center glyphs scale with `diameter`, so the ring
/// reads the same at the card's 46 pt and the header's smaller size.
struct HabitProgressRing: View {
  let completed: Int
  let target: Int
  let tint: Color
  let icon: String
  var diameter: CGFloat = 46
  let action: () -> Void

  @State private var hovering = false

  private var isComplete: Bool { completed >= max(target, 1) }
  /// 4 pt on the card's 46 pt ring.
  private var lineWidth: CGFloat { (diameter * 0.087).rounded(.toNearestOrEven) }
  private var fraction: Double {
    guard target > 0 else { return isComplete ? 1 : 0 }
    return min(1, Double(completed) / Double(target))
  }

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .stroke(.tertiary, lineWidth: lineWidth)
        LorvexProgressArc(fraction: fraction, style: tint.gradient, lineWidth: lineWidth)
        if isComplete {
          Image(systemName: "checkmark")
            .font(.system(size: diameter * 0.35, weight: .bold))  // lorvex-design-token: allow
            .foregroundStyle(tint)
        } else {
          Image(systemName: icon)
            .font(.system(size: diameter * 0.33, weight: .medium))  // lorvex-design-token: allow
            .foregroundStyle(hovering ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
        }
      }
      .frame(width: diameter, height: diameter)
      .contentShape(Circle())
      .scaleEffect(hovering ? 1.06 : 1)
    }
    .buttonStyle(.plain)
    .onHover { h in lorvexAnimated(.snappy(duration: 0.14)) { hovering = h } }
    .reduceMotionAnimation(.snappy(duration: 0.2), value: fraction)
  }
}

/// One habit tile in the momentum board: the habit's color identity up top, a
/// 7-day rhythm strip, a streak chip, and the completion ring as the focal
/// action. Clicking the body opens the habit inspector; the ring checks it in.
struct HabitMomentumCard: View {
  let habit: LorvexHabit
  /// Real per-habit stats (streak + recent completions). Nil only briefly before
  /// the first stats load; the card degrades to 0 streak / empty strip, never to
  /// estimated values.
  let stats: HabitStats?
  let isSelected: Bool
  /// Adjust today's count by a delta (+1 / −1); `0` toggles the day. The core
  /// clamps to `[0, target_count]`, so `adjust(1)` at the target is a safe no-op.
  let adjust: (Int) -> Void
  /// Clear today's count to zero (the context-menu "Reset today").
  let reset: () -> Void
  let select: () -> Void
  let edit: () -> Void
  let archive: () -> Void
  let delete: () -> Void
  let canMoveUp: Bool
  let canMoveDown: Bool
  let moveUp: () -> Void
  let moveDown: () -> Void

  @State private var hovering = false
  @State private var isShowingDeleteConfirmation = false
  @State private var isShowingResetConfirmation = false
  /// The zone the completion keys are written in, which places today's cell.
  @Environment(\.lorvexProductTimeZone) private var productTimeZone

  /// Progress toward the *current period's* plan — today for daily, this week
  /// for weekly/custom, this month for monthly — so the ring fills and checks
  /// off by period (persisting across days) rather than because the habit was
  /// logged once today.
  private var progress: HabitPeriodProgress.Value {
    HabitPeriodProgress.current(
      habit: habit, recentCompletions: stats?.recentCompletions ?? [], timeZone: productTimeZone)
  }
  private var isComplete: Bool { progress.isComplete }
  /// A habit whose per-day target is more than one check-in (e.g. "8 glasses of
  /// water"); these accumulate per ring tap and clear only via the menu.
  private var isMultiTarget: Bool { habit.targetCount > 1 }
  private var tint: Color { isComplete ? LorvexDesign.Palette.done : LorvexHabitPalette.baseColor(for: habit) }
  /// Real current streak from the core; 0 until stats load.
  private var streak: Int { stats?.currentStreak ?? 0 }

  /// Real recent-activity cells at the habit's cadence granularity: days for a
  /// daily habit, rolling weeks for weekly/custom, months for monthly — so a
  /// weekly or monthly habit isn't shown a near-empty last-7-days strip.
  private var rhythmCells: [HabitRhythmStrip.Cell] {
    HabitRhythmStrip.cells(
      completions: Set(stats?.recentCompletions ?? []),
      habit: habit,
      today: Date(),
      timeZone: productTimeZone)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.m) {
      header
      Spacer(minLength: LorvexDesign.Spacing.s)
      rhythmRow
      footer
      if let milestone = habit.milestone {
        HabitMilestoneProgressView(
          milestone: milestone,
          frequencyType: habit.frequencyType,
          tint: LorvexHabitPalette.baseColor(for: habit),
          style: .compact)
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
    .background(cardBackground)
    .overlay(cardBorder)
    .clipShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
    .shadow(color: .black.opacity(hovering ? 0.10 : 0), radius: 8, y: 3)
    .contentShape(RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous))
    .onTapGesture { select() }
    .onHover { h in lorvexAnimated(.easeOut(duration: 0.14)) { hovering = h } }
    .focusable()
    .onKeyPress(.return) { select(); return .handled }
    .onKeyPress(.space) { select(); return .handled }
    .accessibilityElement(children: .contain)
    // The card opens the inspector on tap / Return / Space, but a raw
    // `.onTapGesture` is invisible to VoiceOver. Expose the same affordance as
    // an accessibility action so VO users can open the detail.
    .accessibilityAction { select() }
    .accessibilityIdentifier("habit.tracker.card.\(habit.id)")
    .contextMenu { contextMenu }
    .confirmationDialog(
      String(
        format: String(localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?", table: "Localizable", bundle: LorvexL10n.bundle),
        habit.name),
      isPresented: $isShowingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: "habits.row.delete_confirm.delete", defaultValue: "Delete Habit", table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive, action: delete)
      Button(String(localized: "common.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
    } message: {
      Text(LocalizedStringResource("habits.row.delete_confirm.message", defaultValue: "This removes its completion history.", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .confirmationDialog(
      String(localized: "habits.row.reset_confirm.title", defaultValue: "Reset today’s progress?", table: "Localizable", bundle: LorvexL10n.bundle),
      isPresented: $isShowingResetConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: "habits.row.reset_today", defaultValue: "Reset today", table: "Localizable", bundle: LorvexL10n.bundle), role: .destructive, action: reset)
      Button(String(localized: "common.keep", defaultValue: "Keep", table: "Localizable", bundle: LorvexL10n.bundle), role: .cancel) {}
    } message: {
      Text(LocalizedStringResource("habits.row.reset_confirm.message", defaultValue: "This clears today’s check-ins for this habit.", table: "Localizable", bundle: LorvexL10n.bundle))
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.s) {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
        Text(userContent: habit.name)
          .font(LorvexDesign.Typography.primaryEmphasis)
          .foregroundStyle(.primary)
          .lineLimit(2)
        if let cue = habit.cue, !cue.isEmpty {
          Text(userContent: cue)
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: LorvexDesign.Spacing.s)
      HabitProgressRing(
        completed: progress.completed,
        target: progress.required,
        tint: tint,
        icon: LorvexSymbol.name(for: habit.icon, fallback: "repeat.circle"),
        action: ringTapped
      )
      .help(ringAction.label(for: habit))
      .accessibilityLabel(ringAction.label(for: habit))
      .accessibilityIdentifier(ringAction.cardIdentifier)
    }
  }

  private var ringAction: HabitRingAction { HabitRingAction.action(habit: habit, progress: progress) }

  /// Ring tap, by the shared rule (``HabitRingAction``): `adjust(1)` adds a
  /// check-in and `adjust(0)` toggles the day.
  private func ringTapped() {
    switch ringAction {
    case .addOne: adjust(1)
    case .checkIn, .undoToday: adjust(0)
    case .none: break
    }
  }

  /// The recent periods as capsules, the current one ringed. A daily habit's
  /// seven days carry their narrow weekday underneath, today's in the
  /// habit's color, so the strip reads as "this week" rather than seven
  /// anonymous marks; a weekly or monthly strip stays unlabeled.
  private var rhythmRow: some View {
    let labels = rhythmDayLabels
    return HStack(alignment: .top, spacing: LorvexDesign.Spacing.xs) {
      ForEach(Array(rhythmCells.enumerated()), id: \.offset) { index, cell in
        VStack(spacing: LorvexDesign.Spacing.xs) {
          Capsule()
            .fill(cell.filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary.opacity(0.18)))
            .frame(height: 6)
            .overlay {
              if cell.isCurrent {  // the current period gets a ring
                Capsule().strokeBorder(tint.opacity(cell.filled ? 0 : 0.6), lineWidth: 1)
              }
            }
          if index < labels.count {
            Text(labels[index])
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(cell.isCurrent ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary))
              .fixedSize()
          }
        }
      }
    }
    .accessibilityHidden(true)
  }

  /// Narrow weekdays for a daily habit's seven cells, oldest first; empty for
  /// a weekly or monthly strip.
  private var rhythmDayLabels: [String] {
    HabitRhythmStrip.dayLabels(habit: habit, today: Date(), timeZone: productTimeZone)
  }

  /// The streak as a reading ("12-day streak", "No streak yet"), the stepper
  /// for a multi-check-in habit, and the 30-day completion rate, which gives
  /// way first when the card is too narrow for all three.
  private var footer: some View {
    ViewThatFits(in: .horizontal) {
      footerRow(showsRate: true)
      footerRow(showsRate: false)
    }
  }

  private func footerRow(showsRate: Bool) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Label {
        Text(HabitDisplayText.milestoneValueLabel(metric: "streak", value: streak, frequencyType: habit.frequencyType))
          .monospacedDigit()
      } icon: {
        Image(systemName: "flame.fill")
      }
      .font(LorvexDesign.Typography.tertiaryText.weight(.medium))
      .foregroundStyle(streak > 0 ? tint : LorvexDesign.Palette.neutral)
      .fixedSize()

      if isMultiTarget {
        accumulativeStepper
          .fixedSize()
      }

      Spacer(minLength: 0)

      if showsRate {
        Text(
          String(
            format: String(localized: "habits.card.rate_30d", defaultValue: "%@ in 30 days", table: "Localizable", bundle: LorvexL10n.bundle),
            habit.completionRate30d.formatted(.percent.precision(.fractionLength(0))))
        )
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
        .foregroundStyle(.secondary)
        .fixedSize()
      }
    }
  }

  /// `[−] N/target [+]` micro-stepper for accumulative habits: a discoverable
  /// way to correct the count down (the ring only adds), with the decrement
  /// disabled at zero and the increment disabled once the target is met.
  private var accumulativeStepper: some View {
    HStack(spacing: LorvexDesign.Spacing.sm) {
      Button { adjust(-1) } label: {
        Image(systemName: "minus")
          .font(.system(size: 10, weight: .bold))  // lorvex-design-token: allow
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.plain)
      .disabled(habit.completionsToday <= 0)
      .help(String(localized: "habits.row.decrement", defaultValue: "Remove one", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "habits.row.decrement", defaultValue: "Remove one", table: "Localizable", bundle: LorvexL10n.bundle))

      Text("\(habit.completionsToday)/\(habit.targetCount)")
        .font(LorvexDesign.Typography.tertiaryText.monospacedDigit())
        .foregroundStyle(isComplete ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
        .accessibilityLabel(String(
          localized: "habits.row.today_progress_a11y",
          defaultValue: "\(habit.completionsToday) of \(habit.targetCount) done today",
          table: "Localizable", bundle: LorvexL10n.bundle))

      Button { adjust(1) } label: {
        Image(systemName: "plus")
          .font(.system(size: 10, weight: .bold))  // lorvex-design-token: allow
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.plain)
      .disabled(isComplete)
      .help(String(localized: "habits.row.add_one", defaultValue: "Add one", table: "Localizable", bundle: LorvexL10n.bundle))
      .accessibilityLabel(String(localized: "habits.row.add_one", defaultValue: "Add one", table: "Localizable", bundle: LorvexL10n.bundle))
    }
    .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private var contextMenu: some View {
    Button(
      String(localized: "habits.row.reset_today", defaultValue: "Reset today", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "arrow.counterclockwise"
    ) {
      // One stray check-in clears like unchecking a box; more than one is real
      // accumulated progress, so confirm before wiping it.
      if habit.completionsToday > 1 {
        isShowingResetConfirmation = true
      } else {
        reset()
      }
    }
    .disabled(habit.completionsToday == 0)
    Divider()
    Button(String(localized: "habits.row.move_up", defaultValue: "Move Up", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "chevron.up", action: moveUp)
      .disabled(!canMoveUp)
    Button(String(localized: "habits.row.move_down", defaultValue: "Move Down", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "chevron.down", action: moveDown)
      .disabled(!canMoveDown)
    Divider()
    Button(String(localized: "common.edit", defaultValue: "Edit", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "pencil", action: edit)
    Button(
      String(localized: "habits.row.archive", defaultValue: "Archive", table: "Localizable", bundle: LorvexL10n.bundle),
      systemImage: "archivebox", action: archive)
    Button(String(localized: "common.delete", defaultValue: "Delete", table: "Localizable", bundle: LorvexL10n.bundle), systemImage: "trash", role: .destructive) {
      isShowingDeleteConfirmation = true
    }
  }

  private var cardBackground: some ShapeStyle {
    // A whisper of the habit's color so each tile carries its own identity
    // without shouting; deepens slightly on hover.
    tint.opacity(hovering ? 0.10 : 0.06)
  }

  @ViewBuilder
  private var cardBorder: some View {
    RoundedRectangle(cornerRadius: LorvexDesign.Radius.m, style: .continuous)
      .strokeBorder(
        isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.18)),
        lineWidth: isSelected ? 1.5 : 0.5)
  }
}
