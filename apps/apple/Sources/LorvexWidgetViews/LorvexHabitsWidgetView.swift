import AppIntents
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI

/// Displays today's habit completion status in systemSmall and systemMedium families.
public struct HabitsWidgetView: View {
  public let habits: [WidgetSnapshot.HabitSummary]
  public let family: WidgetFamilyKind
  public let staleAgeLabel: String?

  public init(habits: [WidgetSnapshot.HabitSummary], family: WidgetFamilyKind, staleAgeLabel: String? = nil) {
    self.habits = habits
    self.family = family
    self.staleAgeLabel = staleAgeLabel
  }

  private var rowLimit: Int { HabitsWidgetLayout.rowLimit(for: family) }

  private var completedCount: Int { habits.filter(\.isDoneToday).count }

  private var metrics: LorvexWidgetViewMetrics { .metrics(for: family) }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      habitList
      Spacer(minLength: 0)
      footer
    }
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
  }

  private var titleFont: Font {
    family == .systemSmall ? .headline : .title3.weight(.semibold)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: "repeat")
        .font(titleFont)
        .foregroundStyle(LorvexDesign.Palette.accent)
        .accessibilityHidden(true)
      Text("widget.habits.title", bundle: WidgetL10n.bundle)
        .font(titleFont)
        .lineLimit(1)
      Spacer(minLength: 8)
      Text("\(completedCount)/\(habits.count)")
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var habitList: some View {
    if habits.isEmpty {
      Text("widget.empty.no_habits", bundle: WidgetL10n.bundle)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(habits.prefix(rowLimit), id: \.id) { habit in
          HabitRowView(habit: habit)
        }
      }
    }
  }

  @ViewBuilder
  private var footer: some View {
    let remaining = habits.count - completedCount
    let hidden = HabitsWidgetLayout.hiddenHabitCount(total: habits.count, family: family)
    HStack(spacing: 8) {
      if hidden > 0 {
        // Overflow beyond the visible rows is the more actionable fact here —
        // the completion ratio is already visible in the header's "X/Y".
        Text(String(
          localized: "widget.small.more",
          defaultValue: "+\(hidden) more",
          table: "Localizable",
          bundle: WidgetL10n.bundle))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else if remaining == 0 && !habits.isEmpty {
        Label(
          String(
            localized: "widget.habits.all_done",
            defaultValue: "All habits done today",
            table: "Localizable",
            bundle: WidgetL10n.bundle),
          systemImage: "checkmark.seal.fill")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else {
        Text(String(
          localized: "widget.remaining",
          defaultValue: "\(remaining) remaining",
          table: "Localizable",
          bundle: WidgetL10n.bundle))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 6)
      if let staleAgeLabel {
        WidgetStaleAgeLabel(staleAgeLabel)
      }
    }
  }
}

/// Row budget for the Habits widget's visible list, and how many habits are
/// dropped from view beyond that budget. Mirrors `TodayWidgetLayout`'s
/// row-limit/overflow split so the footer can surface an explicit "+N more"
/// affordance instead of silently dropping rows.
public enum HabitsWidgetLayout {
  public static func rowLimit(for family: WidgetFamilyKind) -> Int {
    family == .systemMedium ? 5 : 3
  }

  public static func hiddenHabitCount(total: Int, family: WidgetFamilyKind) -> Int {
    max(0, total - rowLimit(for: family))
  }
}

// MARK: - Habit row

struct HabitRowView: View {
  let habit: WidgetSnapshot.HabitSummary

  /// 0–1 fraction of today's target met (a binary habit is simply 0 or 1).
  private var progress: Double {
    guard habit.target > 0 else { return habit.completedToday > 0 ? 1 : 0 }
    return min(1, Double(habit.completedToday) / Double(habit.target))
  }

  var body: some View {
    HStack(spacing: 8) {
      ringControl
      info
    }
  }

  /// The progress ring — full + green check when today's target is met, a partial
  /// accent arc otherwise. It reads as status (and shows multi-count progress like
  /// 2/3), not a checkbox.
  private var ring: some View {
    ZStack {
      Circle()
        .stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
      Circle()
        .trim(from: 0, to: progress)
        .stroke(
          habit.isDoneToday ? LorvexDesign.Palette.done : LorvexDesign.Palette.accent,
          style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .rotationEffect(.degrees(-90))
      if habit.isDoneToday {
        Image(systemName: "checkmark")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(LorvexDesign.Palette.done)
      }
    }
    .frame(width: 18, height: 18)
  }

  /// Until the target is met the ring is a real complete button (logs one
  /// completion in-process via `WidgetCompleteHabitIntent`); once met it's just
  /// the status ring.
  @ViewBuilder
  private var ringControl: some View {
    if habit.isDoneToday {
      ring.accessibilityHidden(true)
    } else {
      Button(intent: WidgetCompleteHabitIntent(habitID: habit.id, name: habit.name)) {
        ring
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        String(
          localized: "widget.habits.complete.a11y",
          defaultValue: "Complete \(habit.name)",
          table: "Localizable",
          bundle: WidgetL10n.bundle))
    }
  }

  private var info: some View {
    HStack(spacing: 8) {
      if let icon = habit.icon, !icon.isEmpty {
        // Habit icons are SF Symbol names (from the icon picker), so render the
        // symbol — `Text(icon)` printed the literal "book.fill".
        Image(systemName: icon)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      Text(habit.name)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        // A habit name is user-authored content, and the small family renders on
        // StandBy (visible on a locked device); redact it when the device locks,
        // matching how task titles are treated on the same surface.
        .privacySensitive()
      Spacer(minLength: 0)
      Text("\(habit.completedToday)/\(habit.target)")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    // Announce the info as one unit ("Meditate, 1 of 2") instead of fragments.
    .accessibilityElement(children: .combine)
    .accessibilityLabel(habitProgressAccessibilityLabel)
  }

  private var habitProgressAccessibilityLabel: String {
    String(
      localized: "widget.habits.row.progress.a11y",
      defaultValue: "\(habit.name), \(habit.completedToday) of \(habit.target)",
      table: "Localizable",
      bundle: WidgetL10n.bundle)
  }
}
