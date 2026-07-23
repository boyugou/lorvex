#if DEBUG
  import AppKit
  import LorvexCore
  import SwiftUI

  /// DEBUG-only milestone design verifier, rendered by `--dump-snapshots` beside
  /// the base component gallery. Renders the three habit-milestone surfaces as
  /// plain-SwiftUI components (which `ImageRenderer` renders fully, unlike the
  /// `List`/`Table`-backed workspaces): the momentum cards carrying the compact
  /// milestone bar, the create/edit milestone-goal picker, and the celebration
  /// badge.
  enum LorvexMilestoneSnapshotDump {
    @MainActor
    static func dump(to dir: String) {
      LorvexAppleSnapshotDump.write(
        cardsGallery(), "milestone-cards", CGSize(width: 780, height: 560), dir)
      LorvexAppleSnapshotDump.write(
        pickerGallery(), "milestone-picker", CGSize(width: 520, height: 560), dir)
      LorvexAppleSnapshotDump.write(
        celebrationGallery(), "milestone-celebration", CGSize(width: 600, height: 300), dir)
    }

    // MARK: - Fixtures

    private static func recentISODays(_ n: Int) -> [String] {
      let fmt = DateFormatter()
      fmt.dateFormat = "yyyy-MM-dd"
      fmt.calendar = Calendar(identifier: .gregorian)
      fmt.timeZone = .current
      let cal = Calendar.current
      return (0..<n).compactMap { offset in
        cal.date(byAdding: .day, value: -offset, to: Date()).map(fmt.string(from:))
      }
    }

    private static func habit(
      id: String, name: String, icon: String, color: String, cue: String?,
      frequencyType: String, completionsToday: Int, milestoneTarget: Int?,
      metric: String, value: Int, current: Int?, next: Int, progress: Double,
      perPeriodTarget: Int? = nil
    ) -> LorvexHabit {
      LorvexHabit(
        id: id, name: name, icon: icon, color: color, cue: cue, frequencyType: frequencyType,
        targetCount: 1, completionsToday: completionsToday, totalCompletions: value,
        completionRate30d: progress, archived: false, perPeriodTarget: perPeriodTarget,
        milestoneTarget: milestoneTarget,
        milestone: HabitMilestoneInfo(
          metric: metric, value: value, currentMilestone: current, nextMilestone: next,
          progressToNext: progress))
    }

    private static func stats(id: String, streak: Int, completions: [String]) -> HabitStats {
      HabitStats(
        habitID: id, currentStreak: streak, bestStreak: streak, totalCompletions: completions.count,
        completionsToday: completions.first == recentISODays(1).first ? 1 : 0,
        completionRate30d: 0.9, progressKind: "binary", recentCompletions: completions)
    }

    @MainActor
    private static func card(_ habit: LorvexHabit, _ stats: HabitStats) -> some View {
      HabitMomentumCard(
        habit: habit, stats: stats, isSelected: false, adjust: { _ in }, reset: {}, select: {},
        edit: {}, archive: {}, delete: {}, canMoveUp: false, canMoveDown: false, moveUp: {},
        moveDown: {}
      )
      .frame(width: 340)
    }

    // MARK: - Galleries

    @MainActor @ViewBuilder
    private static func cardsGallery() -> some View {
      let meditation = habit(
        id: "med", name: "Morning meditation", icon: "brain.head.profile", color: "#5E5CE6",
        cue: "After waking up, before coffee", frequencyType: "daily", completionsToday: 1,
        milestoneTarget: nil, metric: "streak", value: 13, current: 7, next: 14, progress: 6.0 / 7.0)
      let walk = habit(
        id: "walk", name: "Walk 8,000 steps", icon: "figure.walk", color: "#34C759", cue: nil,
        frequencyType: "times_per_week", completionsToday: 0, milestoneTarget: nil, metric: "count",
        value: 24, current: 10, next: 25, progress: 14.0 / 15.0, perPeriodTarget: 5)
      let read = habit(
        id: "read", name: "Read 20 minutes", icon: "book.fill", color: "#FF9500",
        cue: "Before bed", frequencyType: "daily", completionsToday: 1, milestoneTarget: 30,
        metric: "streak", value: 5, current: nil, next: 30, progress: 5.0 / 30.0)

      VStack(alignment: .leading, spacing: 20) {
        Text("Habit board — streak + next-milestone progress")
          .font(.title3.weight(.semibold))
        HStack(alignment: .top, spacing: 16) {
          card(meditation, stats(id: "med", streak: 13, completions: recentISODays(7)))
          card(walk, stats(id: "walk", streak: 4, completions: recentISODays(24).filter { !recentISODays(7).contains($0) }))
        }
        HStack(alignment: .top, spacing: 16) {
          card(read, stats(id: "read", streak: 5, completions: recentISODays(5)))
          VStack(alignment: .leading, spacing: 8) {
            Text("Inspector detail").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            HabitCatalogRowDetail(habit: walk, recentCompletions: recentISODays(24))
              .frame(width: 320)
              .padding(12)
              .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10))
          }
        }
      }
      .padding(24)
      .frame(width: 780, alignment: .leading)
      .background(Color(nsColor: .windowBackgroundColor))
    }

    // A faithful static stand-in for the milestone-goal `DraftSheetField`:
    // `ImageRenderer` draws native `TextField`s as an unsupported-view
    // placeholder, so the value is shown as text in the same field chrome the
    // real control uses (label + flag glyph, clearable input, cadence hint).
    @MainActor
    private static func milestoneField(value: String?, hint: String) -> some View {
      DraftSheetField(
        title: String(
          localized: "habits.sheet.field.milestone_goal", defaultValue: "Celebrate after",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
        systemImage: "flag.checkered"
      ) {
        HStack(spacing: LorvexDesign.Spacing.s) {
          Text(value ?? String(
            localized: "habits.sheet.field.milestone_goal_placeholder", defaultValue: "Optional number",
            table: "Localizable",
            bundle: LorvexL10n.bundle))
            .font(LorvexDesign.Typography.primaryText)
            .foregroundStyle(value == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .frame(maxWidth: 120, alignment: .leading)
          if value != nil {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
          }
        }
        Text(hint)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }
    }

    @MainActor
    private static func pickerGallery() -> some View {
      let streakHint = String(
        localized: "habits.sheet.field.milestone_goal_hint_streak",
        defaultValue: "Streak length in days, like 30. The habit keeps going.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
      let countHint = String(
        localized: "habits.sheet.field.milestone_goal_hint_count",
        defaultValue: "Total completions, like 50. The habit keeps going.",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
      return VStack(alignment: .leading, spacing: 22) {
        Text("Create / edit — milestone-goal picker").font(.title3.weight(.semibold))
        VStack(alignment: .leading, spacing: 6) {
          Text("Goal set (streak cadence)").font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          DraftSheetPanel(accessibilityIdentifier: "dump.set") { milestoneField(value: "30", hint: streakHint) }
        }
        VStack(alignment: .leading, spacing: 6) {
          Text("Cleared (count cadence)").font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          DraftSheetPanel(accessibilityIdentifier: "dump.none") { milestoneField(value: nil, hint: countHint) }
        }
      }
      .environment(\.colorScheme, .light)
      .padding(24)
      .frame(width: 520, alignment: .leading)
      .background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor @ViewBuilder
    private static func celebrationGallery() -> some View {
      let celebration = HabitMilestoneCelebration(
        habitName: "Morning meditation", milestone: 14, metric: "streak", frequencyType: "daily",
        tint: Color(lorvexHex: "#5E5CE6") ?? .indigo)
      VStack(spacing: 20) {
        Text("Milestone celebration").font(.title3.weight(.semibold))
        HabitMilestoneCelebrationCard(celebration: celebration, reduceMotion: false, flat: true)
      }
      .environment(\.colorScheme, .light)
      .padding(24)
      .frame(width: 600, height: 300)
      .background(
        LinearGradient(
          colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
          startPoint: .top, endPoint: .bottom))
    }
  }
#endif
