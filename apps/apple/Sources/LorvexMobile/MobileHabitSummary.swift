import LorvexCore
import SwiftUI

/// A habit's identity and standing, shared by the habit rows: its icon tile,
/// its name, a caption, and the milestone line when the habit has a reading
/// to show.
///
/// The caption names the habit's cue, the moment the habit belongs to, as the
/// macOS habit card does, and leads with today's count only for a habit that
/// takes more than one check-in a day ("2/3 today · After meals"). A
/// one-check-in habit's count would restate the row's completion ring, which
/// already reads done or not and carries the count for VoiceOver.
///
/// The name takes up to two lines, like a task title, and the caption and
/// milestone lines wrap rather than truncate, so at accessibility text sizes
/// the summary grows taller but never wider than the width its row offers —
/// the row's trailing completion ring always stays on screen.
struct MobileHabitSummary: View {
  let habit: LorvexHabit

  var body: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      MobileIconTile(symbol: habit.tileSymbol, tint: habit.tileTint, size: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(habit.name)
          .font(.body)
          .lineLimit(2)
        if let caption = Self.caption(for: habit) {
          Text(caption)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if let milestone = habit.milestone, habit.showsMilestoneStrip {
          MobileHabitMilestoneProgressView(
            milestone: milestone, frequencyType: habit.frequencyType, tint: habit.tileTint,
            accessibilityIDSuffix: habit.id)
        }
      }
    }
  }

  /// The line under the name: today's count for a habit that takes more than
  /// one check-in a day, then its cue; nil when the habit has neither.
  nonisolated static func caption(for habit: LorvexHabit) -> String? {
    let count = habit.targetCount > 1 ? habit.todayProgressText : nil
    let cue = habit.cue.flatMap { $0.isEmpty ? nil : $0 }
    let parts = [count, cue].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}
