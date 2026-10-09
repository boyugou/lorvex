import AppIntents
import LorvexCore
import LorvexWidgetIntents
import LorvexWidgetKitSupport
import SwiftUI

/// Today's habits in the systemSmall and systemMedium families, as a grid of
/// rings like the habits on the phone's Today: each habit is its ring, in the
/// habit's color and carrying its symbol, over its name
/// (``LorvexHabitRingTile``). A habit kept several times a day draws one arc
/// per check-in. Tapping the ring of a habit not yet done checks it in without
/// opening the app; a done habit's ring is green with a check. A habit set
/// aside for today draws its ring as dots around a skip mark and quiets its
/// name; a tap still checks it in, which lifts the skip.
///
/// A header names the widget and counts the habits done today, over those the
/// day asks about: a habit set aside is in neither count. Small's grid
/// has two columns, medium's four, and both hold two rows, which share the
/// height under the header. Where two rows of full-size rings do not fit (a
/// smaller widget, a larger text size, a script whose line height is taller
/// than the Latin one) the rings shrink to 85% and then to 70%, and where even
/// those do not fit the grid keeps one row. With more habits than tiles, the last
/// tile counts the rest and the habits not yet done take the tiles first, so
/// what is left to do stays in view (a habit set aside is not left to do);
/// otherwise the habits keep their order.
///
/// The view draws inside WidgetKit's content margins and adds none of its own.
public struct HabitsWidgetView: View {
  public let habits: [WidgetSnapshot.HabitSummary]
  public let family: WidgetFamilyKind
  public let staleAgeLabel: String?

  public init(habits: [WidgetSnapshot.HabitSummary], family: WidgetFamilyKind, staleAgeLabel: String? = nil) {
    self.habits = habits
    self.family = family
    self.staleAgeLabel = staleAgeLabel
  }

  private var progress: (done: Int, total: Int) { HabitsWidgetLayout.progress(habits) }

  private var isAllDone: Bool { progress.total > 0 && progress.done == progress.total }

  private var columnCount: Int { HabitsWidgetLayout.columnCount(family: family) }

  /// The ring's diameter, growing with the text size so a ring stays the
  /// tile's mark next to a larger name.
  @ScaledMetric(relativeTo: .caption) private var ringDiameter: CGFloat = 30

  public var body: some View {
    // Explicit candidates, largest first; the first that fits is drawn.
    ViewThatFits(in: .vertical) {
      content(rows: HabitsWidgetLayout.maxRows, ringDiameter: ringDiameter)
      content(rows: HabitsWidgetLayout.maxRows, ringDiameter: (ringDiameter * 0.85).rounded())
      content(rows: HabitsWidgetLayout.maxRows, ringDiameter: (ringDiameter * 0.7).rounded())
      content(rows: 1, ringDiameter: ringDiameter)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func content(rows: Int, ringDiameter: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      if habits.isEmpty {
        Text("widget.empty.no_habits", bundle: WidgetL10n.bundle)
          .font(WidgetType.meta)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        grid(rows: rows, ringDiameter: ringDiameter)
      }
    }
  }

  /// The widget's name and how many habits are done today, with the seal
  /// once all are; at a text size where the line cannot hold all three, the
  /// seal gives way, since the count already says it, before the name is cut.
  private var header: some View {
    ViewThatFits(in: .horizontal) {
      headerRow(showsSeal: true)
      headerRow(showsSeal: false)
    }
  }

  private func headerRow(showsSeal: Bool) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text("widget.habits.title", bundle: WidgetL10n.bundle)
        .font(WidgetType.label)
        .foregroundStyle(LorvexDesign.Palette.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .widgetAccentable()
      Spacer(minLength: 6)
      if let staleAgeLabel {
        WidgetStaleAgeLabel(staleAgeLabel)
      }
      if showsSeal, isAllDone {
        Image(systemName: "checkmark.seal.fill")
          .font(WidgetType.foot)
          .foregroundStyle(LorvexDesign.Palette.done)
          .accessibilityLabel(
            String(
              localized: "widget.habits.all_done", defaultValue: "All habits done today",
              table: "Localizable", bundle: WidgetL10n.bundle))
      }
      if progress.total > 0 {
        Text("\(progress.done)/\(progress.total)")
          .font(WidgetType.meta)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }

  /// The tiles in rows of `columnCount`, each column an equal share of the
  /// width and each row an equal share of the height left under the header;
  /// a short last row keeps its tiles at the leading edge.
  ///
  /// Static branches rather than `ForEach`, which the grid's two rows of at
  /// most four tiles (``HabitsWidgetLayout``) allow: the grid is a
  /// `ViewThatFits` candidate, and SwiftUI may evaluate a candidate it does
  /// not draw off the main thread, where a `ForEach` content closure trips
  /// Swift 6's isolation check.
  private func grid(rows: Int, ringDiameter: CGFloat) -> some View {
    let tiles = HabitsWidgetLayout.tiles(habits, capacity: rows * columnCount)
    return VStack(alignment: .leading, spacing: 8) {
      gridRow(0, tiles: tiles, ringDiameter: ringDiameter)
      if tiles.count > columnCount {
        gridRow(1, tiles: tiles, ringDiameter: ringDiameter)
      }
    }
    .frame(maxHeight: .infinity)
  }

  private func gridRow(
    _ row: Int, tiles: [HabitsWidgetLayout.Tile], ringDiameter: CGFloat
  ) -> some View {
    let first = row * columnCount
    return HStack(alignment: .top, spacing: 6) {
      cell(first, tiles: tiles, ringDiameter: ringDiameter)
      cell(first + 1, tiles: tiles, ringDiameter: ringDiameter)
      if columnCount > 2 {
        cell(first + 2, tiles: tiles, ringDiameter: ringDiameter)
        cell(first + 3, tiles: tiles, ringDiameter: ringDiameter)
      }
    }
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private func cell(
    _ index: Int, tiles: [HabitsWidgetLayout.Tile], ringDiameter: CGFloat
  ) -> some View {
    if index < tiles.count {
      tileView(tiles[index], ringDiameter: ringDiameter)
    } else {
      Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
    }
  }

  @ViewBuilder
  private func tileView(_ tile: HabitsWidgetLayout.Tile, ringDiameter: CGFloat) -> some View {
    switch tile {
    case .habit(let habit):
      HabitTileView(habit: habit, ringDiameter: ringDiameter)
    case .more(let count):
      VStack(spacing: LorvexDesign.Spacing.xs) {
        Image(systemName: "ellipsis")
          .font(.system(size: ringDiameter * 0.4, weight: .semibold))  // lorvex-design-token: allow
          .foregroundStyle(.secondary)
          .frame(width: ringDiameter, height: ringDiameter)
          .background(Circle().stroke(.tertiary, lineWidth: max(2, (ringDiameter * 0.1).rounded())))
        Text(
          String(
            localized: "widget.small.more", defaultValue: "+\(count) more", table: "Localizable",
            bundle: WidgetL10n.bundle)
        )
        .font(WidgetType.tile)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }
}

/// How the Habits widget lays its habits out: the columns each family's grid
/// has, and which habits fill the tiles a number of rows holds. The grid is
/// at most two rows of at most four tiles; the view draws exactly that shape.
public enum HabitsWidgetLayout {
  /// Rows at the default text size; a larger size may fit fewer.
  public static let maxRows = 2

  public static func columnCount(family: WidgetFamilyKind) -> Int {
    family == .systemMedium ? 4 : 2
  }

  /// A tile of the grid: a habit, or the count of habits left out.
  public enum Tile: Equatable {
    case habit(WidgetSnapshot.HabitSummary)
    case more(Int)
  }

  /// The habits met today over the habits the day asks about. A habit set aside
  /// for today is neither done nor owed, so it is in neither count.
  public static func progress(_ habits: [WidgetSnapshot.HabitSummary]) -> (done: Int, total: Int) {
    let asked = habits.filter { !$0.isSkipped }
    return (asked.filter(\.isDoneToday).count, asked.count)
  }

  /// The tiles `capacity` holds. Every habit when they fit, in order;
  /// otherwise the last tile counts the habits left out, and the habits still
  /// open today (not done, not set aside) take the other tiles first, each
  /// group in order.
  public static func tiles(_ habits: [WidgetSnapshot.HabitSummary], capacity: Int) -> [Tile] {
    guard habits.count > capacity else { return habits.map(Tile.habit) }
    guard capacity > 1 else { return [.more(habits.count)] }
    let ordered = habits.filter(\.isOpenToday) + habits.filter { !$0.isOpenToday }
    let shown = ordered.prefix(capacity - 1)
    return shown.map(Tile.habit) + [.more(habits.count - shown.count)]
  }
}

/// One habit's tile: its ring over its name, a button that checks the habit in
/// (``WidgetCompleteHabitIntent``) until today's count is met. A habit kept
/// several times a day draws one arc of its ring per check-in; VoiceOver reads
/// the count.
struct HabitTileView: View {
  let habit: WidgetSnapshot.HabitSummary
  let ringDiameter: CGFloat

  private var tile: some View {
    LorvexHabitRingTile(
      name: habit.name,
      symbol: LorvexSymbol.name(for: habit.icon, fallback: "repeat"),
      fraction: Double(habit.completedToday) / Double(habit.target),
      tint: LorvexHabitPalette.baseColor(id: habit.id, color: habit.color),
      diameter: ringDiameter,
      nameFont: WidgetType.tile,
      nameLines: 1,
      segments: habit.target,
      isSkipped: habit.isSkipped)
      // A habit name is the user's content, and the widget shows on StandBy,
      // visible on a locked device: redact the tile when the device locks.
      .privacySensitive()
  }

  var body: some View {
    if habit.isDoneToday {
      tile
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressLabel)
    } else {
      Button(intent: WidgetCompleteHabitIntent(habitID: habit.id, name: habit.name)) {
        tile.contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        String(
          localized: "widget.habits.complete.a11y", defaultValue: "Complete \(habit.name)",
          table: "Localizable", bundle: WidgetL10n.bundle))
      .accessibilityValue(habit.isSkipped ? HabitSkippedLabel.text : progressLabel)
    }
  }

  private var progressLabel: String {
    String(
      localized: "widget.habits.row.progress.a11y",
      defaultValue: "\(habit.name), \(habit.completedToday) of \(habit.target)",
      table: "Localizable", bundle: WidgetL10n.bundle)
  }
}

/// The words VoiceOver reads for a habit set aside for today.
enum HabitSkippedLabel {
  static var text: String {
    String(
      localized: "widget.habits.skipped.a11y", defaultValue: "Skipped today",
      table: "Localizable", bundle: WidgetL10n.bundle)
  }
}
