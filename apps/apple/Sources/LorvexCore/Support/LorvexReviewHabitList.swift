import SwiftUI

/// What checking a habit in does to the day it is checked in on: a habit kept
/// once a day toggles, and one counted several times a day adds one until it
/// meets its count, after which checking in does nothing, so a tap never wipes
/// a day's tally. The menu bar panel and both day reviews share the rule.
public enum LorvexHabitCheckIn: Equatable, Sendable {
  case complete
  case uncomplete
  case addOne
  case none

  /// The check-in for `habit`, read against its completions on the day the
  /// habit was loaded for.
  public static func action(for habit: LorvexHabit) -> LorvexHabitCheckIn {
    let target = max(habit.targetCount, 1)
    let isMet = habit.completionsToday >= target
    if target > 1 { return isMet ? .none : .addOne }
    return isMet ? .uncomplete : .complete
  }
}

/// A habit's check-in ring: a neutral track, the day's progress in `tint`, and
/// a check once the day's count is met. Until then a ring that is the habit's
/// only mark, as in a habit grid, carries the habit's `symbol` at its center.
///
/// A habit kept several times a day can draw its ring as `segments` arcs, one
/// per check-in, so the count reads without a number: two of three arcs
/// filled is two of three done. Two to twelve segments are drawn apart; any
/// other count draws one continuous ring.
///
/// The stroke and the center glyphs grow with `diameter`, so the same ring
/// reads at a row's size and at a grid tile's.
public struct LorvexHabitCheckRing: View {
  public var fraction: Double
  public var tint: Color
  public var diameter: CGFloat
  public var symbol: String?
  public var segments: Int

  public init(
    fraction: Double, tint: Color, diameter: CGFloat = 18, symbol: String? = nil, segments: Int = 1
  ) {
    self.fraction = fraction
    self.tint = tint
    self.diameter = diameter
    self.symbol = symbol
    self.segments = segments
  }

  /// 2pt on a row's ring, about a tenth of the diameter on a larger one.
  private var lineWidth: CGFloat { max(2, (diameter * 0.1).rounded()) }

  /// A row's ring keeps the caption-sized check; a tile's check scales with it.
  private var checkFont: Font {
    diameter < 24
      ? LorvexDesign.Typography.tertiaryText.weight(.bold)
      : .system(size: diameter * 0.42, weight: .bold)  // lorvex-design-token: allow
  }

  private var segmentCount: Int { (2...12).contains(segments) ? segments : 1 }

  private var filledSegments: Int {
    Int((min(max(fraction, 0), 1) * Double(segmentCount)).rounded())
  }

  /// The gap between two segments as a share of the circumference: a little
  /// less than the stroke is wide, so the gaps read as cuts at any diameter.
  private var segmentGap: CGFloat {
    min(0.3 / CGFloat(segmentCount), lineWidth * 0.9 / (.pi * diameter))
  }

  public var body: some View {
    ZStack {
      if segmentCount > 1 {
        ForEach(0..<segmentCount, id: \.self) { index in
          LorvexProgressArc(
            from: Double(index) / Double(segmentCount) + segmentGap / 2,
            to: Double(index + 1) / Double(segmentCount) - segmentGap / 2,
            style: index < filledSegments ? AnyShapeStyle(tint) : AnyShapeStyle(.tertiary),
            lineWidth: lineWidth, lineCap: .butt)
        }
      } else {
        Circle().stroke(.tertiary, lineWidth: lineWidth)
        LorvexProgressArc(fraction: fraction, style: tint, lineWidth: lineWidth)
      }
      if fraction >= 1 {
        Image(systemName: "checkmark")
          .font(checkFont)
          .imageScale(diameter < 24 ? .small : .medium)
          .foregroundStyle(tint)
      } else if let symbol {
        Image(systemName: symbol)
          .font(.system(size: diameter * 0.4, weight: .semibold))  // lorvex-design-token: allow
          .foregroundStyle(tint)
      }
    }
    .frame(width: diameter, height: diameter)
    .contentShape(Circle())
    .animation(.snappy(duration: 0.2), value: fraction)
  }
}

/// A habit as a habit grid draws it: its check-in ring, carrying the habit's
/// symbol until the day's count is met, over its name. The ring takes the
/// habit's identity color, and the done color with a check once met, when the
/// name quiets to secondary.
public struct LorvexHabitRingTile: View {
  private let name: String
  private let symbol: String?
  private let fraction: Double
  private let tint: Color
  private let diameter: CGFloat
  private let nameFont: Font
  private let nameLines: Int
  private let detail: String?
  private let segments: Int

  /// `fraction` is the day's count over its target, `tint` the habit's
  /// identity color (``LorvexHabitPalette``), and `symbol` a resolved SF
  /// Symbol name (``LorvexSymbol``). `segments` is the day's target, so a
  /// habit kept several times a day draws one arc per check-in
  /// (``LorvexHabitCheckRing``). `detail`, when set, is a quiet line under the
  /// name, such as that habit's count in numbers.
  public init(
    name: String, symbol: String?, fraction: Double, tint: Color, diameter: CGFloat,
    nameFont: Font = LorvexDesign.Typography.tertiaryText, nameLines: Int = 2,
    detail: String? = nil, segments: Int = 1
  ) {
    self.name = name
    self.symbol = symbol
    self.fraction = min(max(fraction, 0), 1)
    self.tint = tint
    self.diameter = diameter
    self.nameFont = nameFont
    self.nameLines = nameLines
    self.detail = detail
    self.segments = segments
  }

  private var isMet: Bool { fraction >= 1 }

  public var body: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      LorvexHabitCheckRing(
        fraction: fraction, tint: isMet ? LorvexDesign.Palette.done : tint, diameter: diameter,
        symbol: symbol, segments: segments)
      VStack(spacing: 0) {
        Text(userContent: name)
          .font(nameFont)
          .foregroundStyle(isMet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .lineLimit(nameLines)
          // Every name in a grid keeps the one font, so the names read as one
          // row of labels; a long name tightens its letters, then truncates.
          .allowsTightening(true)
        if let detail {
          Text(detail)
            .font(nameFont)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, alignment: .top)
  }
}

/// The habits on a day review, as they stood on the reviewed day, in a grid:
/// each habit is its ring over its name (``LorvexHabitRingTile``), and a tap
/// checks it in on that day (``LorvexHabitCheckIn``). A habit counted more
/// than once a day shows its count under its name. As many columns as the
/// width holds take the habits in order, so a review keeps them where they
/// are from day to day. A review that can no longer be written shows the
/// rings without taking taps.
///
/// A tap shows its result at once: the tile draws the count the check-in will
/// leave while the write and the reload that follows it run, then the
/// reloaded habits take over, so a failed write falls back to what is stored.
///
/// The grid's identifier names the section; each tile's identifier appends
/// the habit id.
public struct LorvexReviewHabitList: View {
  private let label: String
  private let habits: [LorvexHabit]
  private let checkInLabel: String
  private let identifier: String
  private let isEnabled: Bool
  private let checkIn: (LorvexHabit) async -> Void

  /// The count each in-flight check-in will leave, by habit id, drawn until
  /// the check-in returns.
  @State private var pendingCounts: [String: Int] = [:]
  @ScaledMetric(relativeTo: .body) private var ringDiameter: CGFloat = 34
  @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 84

  public init(
    label: String, habits: [LorvexHabit], checkInLabel: String, identifier: String,
    isEnabled: Bool = true, checkIn: @escaping (LorvexHabit) async -> Void
  ) {
    self.label = label
    self.habits = habits
    self.checkInLabel = checkInLabel
    self.identifier = identifier
    self.isEnabled = isEnabled
    self.checkIn = checkIn
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      LorvexPageLabel(label)
      LazyVGrid(
        columns: [
          GridItem(
            .adaptive(minimum: columnWidth, maximum: columnWidth * 1.4),
            spacing: LorvexDesign.Spacing.s, alignment: .top)
        ],
        alignment: .leading, spacing: LorvexDesign.Spacing.m
      ) {
        ForEach(habits) { habit in
          tile(habit)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private func tile(_ stored: LorvexHabit) -> some View {
    var habit = stored
    if let pending = pendingCounts[stored.id] { habit.completionsToday = pending }
    let target = max(habit.targetCount, 1)
    let isMet = habit.completionsToday >= target
    let action = LorvexHabitCheckIn.action(for: habit)
    return Button {
      Task { await perform(stored) }
    } label: {
      LorvexHabitRingTile(
        name: habit.name,
        symbol: LorvexSymbol.name(for: habit.icon, fallback: "repeat"),
        fraction: Double(habit.completionsToday) / Double(target),
        tint: LorvexHabitPalette.baseColor(for: habit),
        diameter: min(ringDiameter, 48),
        detail: target > 1 ? "\(habit.completionsToday.formatted())/\(target.formatted())" : nil,
        segments: target)
        .padding(.vertical, LorvexDesign.Spacing.xxs)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled || action == .none)
    .help(checkInLabel)
    .accessibilityLabel(habit.name)
    .accessibilityValue(target > 1 ? "\(habit.completionsToday)/\(target)" : "")
    .accessibilityAddTraits(isMet ? .isSelected : [])
    .accessibilityIdentifier("\(identifier).\(habit.id)")
  }

  private func perform(_ habit: LorvexHabit) async {
    guard pendingCounts[habit.id] == nil else { return }
    let count: Int
    switch LorvexHabitCheckIn.action(for: habit) {
    case .complete: count = max(habit.targetCount, 1)
    case .uncomplete: count = 0
    case .addOne: count = habit.completionsToday + 1
    case .none: return
    }
    withAnimation(.snappy(duration: 0.18)) { pendingCounts[habit.id] = count }
    await checkIn(habit)
    pendingCounts[habit.id] = nil
  }
}
