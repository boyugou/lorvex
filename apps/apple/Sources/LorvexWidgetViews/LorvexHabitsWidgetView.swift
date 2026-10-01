import AppIntents
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI

/// Today's habits in the systemSmall and systemMedium families: a header with
/// the done/total count, one row per habit, and a footer. Small shows up to
/// three habits in one column. Medium shows up to six in two balanced columns:
/// its 158pt height holds three rows under the header, and its width holds two
/// columns of names. A larger text size fits fewer rows per column, so the
/// widget shows as many as fit rather than clipping, and the footer's "+N
/// more" counts the rest. The footer appears only when it adds something —
/// that count, that every habit is done, or the stale-snapshot age — since the
/// header already carries the done/total count.
public struct HabitsWidgetView: View {
  public let habits: [WidgetSnapshot.HabitSummary]
  public let family: WidgetFamilyKind
  public let staleAgeLabel: String?

  public init(habits: [WidgetSnapshot.HabitSummary], family: WidgetFamilyKind, staleAgeLabel: String? = nil) {
    self.habits = habits
    self.family = family
    self.staleAgeLabel = staleAgeLabel
  }

  private var completedCount: Int { habits.filter(\.isDoneToday).count }

  private var isAllDone: Bool { !habits.isEmpty && completedCount == habits.count }

  private var metrics: LorvexWidgetViewMetrics { .metrics(for: family) }

  /// Medium has height to spare under its three rows, so its rings (the
  /// complete buttons) and row gaps are a little larger than small's.
  private var ringDiameter: CGFloat { family == .systemMedium ? 20 : 18 }

  private var rowSpacing: CGFloat { family == .systemMedium ? 8 : 6 }

  public var body: some View {
    ViewThatFits(in: .vertical) {
      ForEach(Array(stride(from: HabitsWidgetLayout.maxRows, through: 1, by: -1)), id: \.self) { rows in
        content(rows: rows)
      }
    }
    .padding(.horizontal, metrics.horizontalPadding)
    .padding(.vertical, metrics.verticalPadding)
  }

  /// The widget with `rows` rows per column. Gaps are explicit paddings, so
  /// the zero-height spacer adds none to the natural height `ViewThatFits`
  /// measures.
  private func content(rows: Int) -> some View {
    let hidden = HabitsWidgetLayout.hiddenHabitCount(total: habits.count, family: family, rows: rows)
    return VStack(alignment: .leading, spacing: 0) {
      header
      habitList(rows: rows)
        .padding(.top, 8)
      Spacer(minLength: 0)
      if hidden > 0 || isAllDone || staleAgeLabel != nil {
        footer(hidden: hidden)
          .padding(.top, 6)
      }
    }
  }

  /// The header drops its symbol before the title would truncate, which a
  /// large text size in small's width otherwise does.
  private var header: some View {
    ViewThatFits(in: .horizontal) {
      headerRow(showsSymbol: true)
      headerRow(showsSymbol: false)
    }
  }

  private func headerRow(showsSymbol: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      if showsSymbol {
        Image(systemName: "repeat")
          .font(.headline)
          .foregroundStyle(LorvexDesign.Palette.accent)
          .accessibilityHidden(true)
      }
      Text("widget.habits.title", bundle: WidgetL10n.bundle)
        .font(.headline)
        .lineLimit(1)
      Spacer(minLength: 8)
      if !habits.isEmpty {
        Text("\(completedCount)/\(habits.count)")
          .font(.caption.weight(.medium))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func habitList(rows: Int) -> some View {
    if habits.isEmpty {
      Text("widget.empty.no_habits", bundle: WidgetL10n.bundle)
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      let shown = Array(habits.prefix(HabitsWidgetLayout.shownCount(total: habits.count, family: family, rows: rows)))
      let columns = HabitsWidgetLayout.columns(shown, family: family, rows: rows)
      // The small family's column is too narrow for a symbol beside the ring:
      // it would cut "Read 30 minutes" to "Read 30 minu…". The ring already
      // says the state, so there the name takes the width.
      let showsSymbols = family != .systemSmall
      let reservesSymbolSlot = showsSymbols && shown.contains { !($0.icon ?? "").isEmpty }
      HStack(alignment: .top, spacing: 12) {
        ForEach(columns.indices, id: \.self) { index in
          VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(columns[index], id: \.id) { habit in
              HabitRowView(
                habit: habit, ringDiameter: ringDiameter, showsSymbol: showsSymbols,
                reservesSymbolSlot: reservesSymbolSlot)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  private func footer(hidden: Int) -> some View {
    HStack(spacing: 8) {
      if hidden > 0 {
        Text(String(
          localized: "widget.small.more",
          defaultValue: "+\(hidden) more",
          table: "Localizable",
          bundle: WidgetL10n.bundle))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      } else if isAllDone {
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
      }
      Spacer(minLength: 6)
      if let staleAgeLabel {
        WidgetStaleAgeLabel(staleAgeLabel)
      }
    }
  }
}

/// How many habits the Habits widget shows for a number of rows per column,
/// how many that leaves out (the footer's "+N more"), and how the shown
/// habits split into columns.
public enum HabitsWidgetLayout {
  /// Rows per column at the default text size; a larger size may fit fewer.
  public static let maxRows = 3

  /// Habits shown with `rows` rows per column: one column on small, and on
  /// medium two once there are more habits than one column holds.
  public static func shownCount(total: Int, family: WidgetFamilyKind, rows: Int = maxRows) -> Int {
    let columnCount = family == .systemMedium && total > rows ? 2 : 1
    return min(total, rows * columnCount)
  }

  public static func hiddenHabitCount(total: Int, family: WidgetFamilyKind, rows: Int = maxRows) -> Int {
    total - shownCount(total: total, family: family, rows: rows)
  }

  /// The shown habits as columns, each filled top to bottom. Medium splits
  /// habits that overflow one column of `rows` into two balanced columns, the
  /// left one taking the extra habit of an odd count (4 → 2 + 2, 5 → 3 + 2);
  /// fewer keep one full-width column so their names are not squeezed for
  /// nothing. Small is always one column.
  public static func columns<Item>(_ shown: [Item], family: WidgetFamilyKind, rows: Int = maxRows) -> [[Item]] {
    guard family == .systemMedium, shown.count > rows else { return [shown] }
    let leftCount = (shown.count + 1) / 2
    return [Array(shown.prefix(leftCount)), Array(shown.dropFirst(leftCount))]
  }
}

// MARK: - Habit row

/// One habit: the progress ring (the complete button until today's target is
/// met), the habit's symbol in a fixed slot, its name, and — for a habit
/// counted more than once a day — its count. A once-a-day habit shows no
/// "0/1" or "1/1", since its ring already says whether it is done.
struct HabitRowView: View {
  let habit: WidgetSnapshot.HabitSummary
  let ringDiameter: CGFloat
  /// Whether the habit's symbol sits between the ring and the name.
  var showsSymbol: Bool = true
  /// Keeps the symbol slot when this habit has no symbol but another shown
  /// habit does, so every name starts at the same x.
  let reservesSymbolSlot: Bool
  /// The symbol slot's width, growing with the caption symbols it holds.
  @ScaledMetric(relativeTo: .caption) var symbolSlotWidth: CGFloat = 16

  /// 0–1 fraction of today's target met (a binary habit is simply 0 or 1).
  private var progress: Double {
    guard habit.target > 0 else { return habit.completedToday > 0 ? 1 : 0 }
    return min(1, Double(habit.completedToday) / Double(habit.target))
  }

  var body: some View {
    HStack(spacing: 6) {
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
          .font(.system(size: ringDiameter * 0.45, weight: .bold))  // lorvex-design-token: allow
          .foregroundStyle(LorvexDesign.Palette.done)
      }
    }
    .frame(width: ringDiameter, height: ringDiameter)
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
    HStack(spacing: 6) {
      symbolSlot
      Text(habit.name)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
        // A habit name is user-authored content, and the small family renders on
        // StandBy (visible on a locked device); redact it when the device locks,
        // matching how task titles are treated on the same surface.
        .privacySensitive()
      Spacer(minLength: 0)
      if habit.target > 1 {
        Text("\(habit.completedToday)/\(habit.target)")
          .font(.caption2)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    // Announce the info as one unit ("Meditate, 1 of 2") instead of fragments.
    .accessibilityElement(children: .combine)
    .accessibilityLabel(habitProgressAccessibilityLabel)
  }

  /// Habit icons are SF Symbol names from the icon picker. Symbols differ in
  /// width, so each sits centered in a fixed slot rather than pushing its name.
  @ViewBuilder
  private var symbolSlot: some View {
    if showsSymbol, let icon = habit.icon, !icon.isEmpty {
      Image(systemName: icon)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: symbolSlotWidth)
        .accessibilityHidden(true)
    } else if reservesSymbolSlot {
      Color.clear
        .frame(width: symbolSlotWidth, height: 1)
        .accessibilityHidden(true)
    }
  }

  private var habitProgressAccessibilityLabel: String {
    String(
      localized: "widget.habits.row.progress.a11y",
      defaultValue: "\(habit.name), \(habit.completedToday) of \(habit.target)",
      table: "Localizable",
      bundle: WidgetL10n.bundle)
  }
}
