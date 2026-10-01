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
/// a check once the day's count is met.
public struct LorvexHabitCheckRing: View {
  public var fraction: Double
  public var tint: Color
  public var diameter: CGFloat

  public init(fraction: Double, tint: Color, diameter: CGFloat = 18) {
    self.fraction = fraction
    self.tint = tint
    self.diameter = diameter
  }

  public var body: some View {
    ZStack {
      Circle().stroke(.tertiary, lineWidth: 2)
      Circle()
        .trim(from: 0, to: fraction)
        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
      if fraction >= 1 {
        Image(systemName: "checkmark")
          .font(LorvexDesign.Typography.tertiaryText.weight(.bold))
          .imageScale(.small)
          .foregroundStyle(tint)
      }
    }
    .frame(width: diameter, height: diameter)
    .contentShape(Circle())
    .animation(.snappy(duration: 0.2), value: fraction)
  }
}

/// The habits on a day review, as they stood on the reviewed day: each row is
/// the habit's ring, which checks it in on that day (``LorvexHabitCheckIn``),
/// its name, and its count when it is counted more than once a day. A review
/// that can no longer be written shows the rings without taking taps.
///
/// The list's identifier names the section; each row's identifier appends the
/// habit id.
public struct LorvexReviewHabitList: View {
  private let label: String
  private let habits: [LorvexHabit]
  private let checkInLabel: String
  private let identifier: String
  private let isEnabled: Bool
  private let checkIn: (LorvexHabit) async -> Void

  @State private var checkingIDs: Set<String> = []
  @ScaledMetric(relativeTo: .body) private var ringDiameter: CGFloat = 15

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
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
      LorvexPageLabel(label)
      ForEach(habits) { habit in
        row(habit)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private func row(_ habit: LorvexHabit) -> some View {
    let target = max(habit.targetCount, 1)
    let isMet = habit.completionsToday >= target
    let action = LorvexHabitCheckIn.action(for: habit)
    return Button {
      Task { await perform(habit) }
    } label: {
      HStack(spacing: LorvexDesign.Spacing.s) {
        LorvexHabitCheckRing(
          fraction: min(Double(habit.completionsToday) / Double(target), 1),
          tint: isMet ? LorvexDesign.Palette.done : LorvexHabitPalette.baseColor(for: habit),
          diameter: min(ringDiameter, 30))
        Text(habit.name)
          .font(LorvexDesign.Typography.primaryText)
          .foregroundStyle(isMet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
          .multilineTextAlignment(.leading)
          .lineLimit(2)
        Spacer(minLength: LorvexDesign.Spacing.s)
        if target > 1 {
          Text("\(habit.completionsToday)/\(target)")
            .font(LorvexDesign.Typography.tertiaryText)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      .padding(.vertical, LorvexDesign.Spacing.xxs)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled || action == .none || checkingIDs.contains(habit.id))
    .help(checkInLabel)
    .accessibilityLabel(habit.name)
    .accessibilityValue(target > 1 ? "\(habit.completionsToday)/\(target)" : "")
    .accessibilityAddTraits(isMet ? .isSelected : [])
    .accessibilityIdentifier("\(identifier).\(habit.id)")
  }

  private func perform(_ habit: LorvexHabit) async {
    guard !checkingIDs.contains(habit.id) else { return }
    checkingIDs.insert(habit.id)
    await checkIn(habit)
    checkingIDs.remove(habit.id)
  }
}
