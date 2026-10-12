import SwiftUI

/// The arcs of a check-in ring that counts several check-ins: `segments` arcs
/// drawn apart, one per check-in, the first `fraction` of them in `tint` and the
/// rest in the neutral track style, so the count reads without a number: two of
/// three arcs filled is two of three done. Every habit ring that can count a
/// day's check-ins draws them with this view (the Today and review rings, the
/// Habits cards, the iPhone's rows), so a habit kept eight times a day reads the
/// same on every surface.
///
/// Two to twelve segments are drawn apart (``isSegmented(_:)``); any other count
/// is one continuous ring, which the caller draws itself. The gap between two
/// segments is a little less than the stroke is wide, so the gaps read as cuts at
/// any diameter, and segment ends are butt, not round.
public struct LorvexRingSegments: View {
  public var segments: Int
  public var fraction: Double
  public var tint: AnyShapeStyle
  public var lineWidth: CGFloat
  public var diameter: CGFloat

  /// Whether a ring counting `segments` check-ins is drawn as separate arcs.
  public static func isSegmented(_ segments: Int) -> Bool { (2...12).contains(segments) }

  public init(
    segments: Int, fraction: Double, tint: AnyShapeStyle, lineWidth: CGFloat, diameter: CGFloat
  ) {
    self.segments = segments
    self.fraction = fraction
    self.tint = tint
    self.lineWidth = lineWidth
    self.diameter = diameter
  }

  /// How many of the segments the fraction fills.
  public var filledSegments: Int {
    Int((min(max(fraction, 0), 1) * Double(segments)).rounded())
  }

  /// The gap between two segments as a share of the circumference.
  private var segmentGap: CGFloat {
    min(0.3 / CGFloat(segments), lineWidth * 0.9 / (.pi * diameter))
  }

  public var body: some View {
    ForEach(0..<segments, id: \.self) { index in
      LorvexProgressArc(
        from: Double(index) / Double(segments) + segmentGap / 2,
        to: Double(index + 1) / Double(segments) - segmentGap / 2,
        style: index < filledSegments ? tint : AnyShapeStyle(.tertiary),
        lineWidth: lineWidth, lineCap: .butt)
    }
  }
}

extension LorvexHabit {
  /// How many check-ins the habit's ring counts: its per-day target for a habit
  /// kept several times a day, whatever its cadence (``HabitPeriodProgress``
  /// counts such a habit by the day), otherwise 1, one continuous ring. A ring
  /// that stands for a week or a month (a habit kept a number of times a week)
  /// counts days, not check-ins, and is not segmented.
  public var ringSegments: Int { max(targetCount, 1) }
}
