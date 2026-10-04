import SwiftUI

// The shared parts of the calm page grammar (docs/design/DESIGN_SYSTEM.md §8):
// the ring, the decision well, the next row, the page label, the day strip, the
// sky wash, and the sun arc. They are presentational: callers pass localized
// strings and actions, so macOS, iPhone, and iPad compose the same parts with
// their own copy tables.

extension LorvexDesign.Typography {
  // The assistant's serif voice is `SerifVoice`, set through
  // `Text(_:serifVoice:)` so each script gets its face.
  /// The title of the lead task in a glance panel (the macOS menu bar), one
  /// step above the rows under it.
  #if os(macOS)
    public static let leadTitle = Font.system(.title2).weight(.semibold)
  #else
    public static let leadTitle = Font.system(.title3).weight(.semibold)
  #endif
  /// A quiet section label on the page ground ("Schedule", "Proposed Schedule").
  public static let pageLabel = Font.system(.subheadline).weight(.semibold)
  /// The title that opens a working page (Today's date), in the system face.
  #if os(macOS)
    public static let pageTitle = Font.system(.largeTitle).weight(.bold)
  #else
    public static let pageTitle = Font.system(.title).weight(.bold)
  #endif
  /// The assistant's briefing on a working page. The system face rather than
  /// the serif italic keeps a long paragraph, and Chinese text, easy to read.
  public static let briefing = Font.system(.body)
  /// The label over a list of tasks on a working page ("Done").
  public static let listSection = Font.system(.headline)
}

// MARK: - Ring

/// A task's circle grown into a timer: the arc fills as its time runs, and the
/// circle is also the task's completion control. Done fills it green with a
/// white check. An open ring carries a faint check as the hint that tapping
/// finishes the task; `showsCheckHint: false` leaves a small ring plain, where
/// that faint check would read as already done.
public struct LorvexTaskRing: View {
  public var progress: Double
  public var isDone: Bool
  public var diameter: CGFloat
  public var showsCheckHint: Bool
  @Environment(\.colorScheme) private var colorScheme

  public init(progress: Double, isDone: Bool, diameter: CGFloat, showsCheckHint: Bool = true) {
    self.progress = progress
    self.isDone = isDone
    self.diameter = diameter
    self.showsCheckHint = showsCheckHint
  }

  private var lineWidth: CGFloat { max(2.5, diameter / 20) }

  public var body: some View {
    ZStack {
      Circle()
        .stroke(
          LorvexDesign.Palette.accent.opacity(LorvexDesign.Palette.trackOpacity(for: colorScheme)),
          lineWidth: lineWidth)
      LorvexProgressArc(
        fraction: isDone ? 1 : progress,
        style: isDone ? LorvexDesign.Palette.done : LorvexDesign.Palette.accent,
        lineWidth: lineWidth)
      if isDone {
        Circle().fill(LorvexDesign.Palette.done).padding(lineWidth / 2)
      }
      if isDone || showsCheckHint {
        Image(systemName: "checkmark")
          .font(.system(size: diameter * 0.32, weight: .bold))  // lorvex-design-token: allow
          .foregroundStyle(isDone ? AnyShapeStyle(.white) : AnyShapeStyle(LorvexDesign.Palette.accent.opacity(0.6)))
      }
    }
    .frame(width: diameter, height: diameter)
    .reduceMotionAnimation(.spring(response: 0.35, dampingFraction: 0.8), value: isDone)
    .reduceMotionAnimation(.easeInOut(duration: 0.4), value: progress)
  }
}

// MARK: - Page label

/// A quiet label that leads a group on the page ground, with an optional
/// trailing note ("1 of 3"). It is quiet by size and weight against the rows
/// under it, and legible in the secondary style: a label names what follows,
/// and the tertiary style reads under 2:1 on the ground, as faint as disabled
/// text.
public struct LorvexPageLabel: View {
  public var title: String
  public var trailing: String?

  public init(_ title: String, trailing: String? = nil) {
    self.title = title
    self.trailing = trailing
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
      Spacer(minLength: LorvexDesign.Spacing.s)
      if let trailing {
        Text(trailing).fontWeight(.regular).monospacedDigit()
      }
    }
    .font(LorvexDesign.Typography.pageLabel)
    .foregroundStyle(.secondary)
    .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - Decision well

/// A question waiting for the user, with one verb: a bold title, a line of
/// reason in the system face, and a capsule button that answers it. The button
/// sits beside the words where the reason fits on one line, and under them
/// where it would not (an iPhone), so the reason is never squeezed into a
/// narrow column. Without an action the well states the fact alone.
public struct LorvexDecisionWell: View {
  public var title: String
  public var message: String
  public var actionTitle: String?
  public var actionIdentifier: String
  public var action: (() -> Void)?

  public init(
    title: String, message: String, actionTitle: String,
    actionIdentifier: String = "today.decision.action", action: @escaping () -> Void
  ) {
    self.title = title
    self.message = message
    self.actionTitle = actionTitle
    self.actionIdentifier = actionIdentifier
    self.action = action
  }

  /// A well that states a fact and offers no action, for a decision the page
  /// can describe but not make for the user.
  public init(title: String, message: String) {
    self.title = title
    self.message = message
    self.actionTitle = nil
    self.actionIdentifier = "today.decision.action"
    self.action = nil
  }

  public var body: some View {
    Group {
      if let actionTitle, let action {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: LorvexDesign.Spacing.m) {
            words
              .frame(maxWidth: .infinity, alignment: .leading)
            button(actionTitle, action: action)
          }
          VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
            words
              .frame(maxWidth: .infinity, alignment: .leading)
            button(actionTitle, action: action)
          }
        }
      } else {
        words
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.vertical, LorvexDesign.Spacing.m - 2)
    .padding(.leading, LorvexDesign.Spacing.cardPadding)
    .padding(.trailing, LorvexDesign.Spacing.m - 2)
    .background(
      LorvexDesign.Palette.insetFill,
      in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.card, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.decision")
  }

  private var words: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xxs) {
      Text(title)
        .font(LorvexDesign.Typography.primaryEmphasis)
        .fixedSize(horizontal: false, vertical: true)
      Text(message)
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func button(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .tint(LorvexDesign.Palette.accent)
      .accessibilityIdentifier(actionIdentifier)
  }
}

// MARK: - Day strip

/// The day at a glance, drawn to scale: meetings in grey, planned work in a
/// light accent, the running block in full accent, finished work in green, time
/// past the workday in red, and a red mark at the clock.
public struct LorvexDayStrip: View {
  public enum Kind: Sendable { case meeting, task, current, done, overrun }
  public struct Segment: Identifiable, Sendable {
    public var id: Int { start * 10_000 + end }
    public var kind: Kind
    public var start: Int
    public var end: Int
    public init(kind: Kind, start: Int, end: Int) {
      self.kind = kind
      self.start = start
      self.end = end
    }
  }

  public var segments: [Segment]
  public var nowMinutes: Int?
  public var range: ClosedRange<Int>

  public init(segments: [Segment], nowMinutes: Int?, range: ClosedRange<Int> = (8 * 60)...(19 * 60)) {
    self.segments = segments
    self.nowMinutes = nowMinutes
    self.range = range
  }

  private func fill(_ kind: Kind) -> Color {
    switch kind {
    case .meeting: return Color.secondary.opacity(0.35)
    case .task: return LorvexDesign.Palette.accent.opacity(0.45)
    case .current: return LorvexDesign.Palette.accent
    case .done: return LorvexDesign.Palette.done.opacity(0.55)
    case .overrun: return LorvexDesign.Palette.overdue
    }
  }

  public var body: some View {
    GeometryReader { proxy in
      let span = CGFloat(range.upperBound - range.lowerBound)
      let x: (Int) -> CGFloat = { minutes in
        CGFloat(min(max(minutes, range.lowerBound), range.upperBound) - range.lowerBound) / span * proxy.size.width
      }
      ZStack(alignment: .leading) {
        Capsule().fill(LorvexDesign.Palette.insetFill.opacity(2))
        ForEach(segments) { segment in
          Capsule()
            .fill(fill(segment.kind))
            .frame(width: max(x(segment.end) - x(segment.start), 3), height: proxy.size.height)
            .offset(x: x(segment.start))
        }
      }
      // The now line overhangs the strip without growing the stack, which
      // would otherwise stretch every capsule to the line's height.
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
      .overlay(alignment: .leading) {
        if let nowMinutes, range.contains(nowMinutes) {
          Capsule()
            .fill(LorvexDesign.Palette.nowIndicator)
            .frame(width: 2, height: proxy.size.height + 10)
            .offset(x: x(nowMinutes) - 1)
        }
      }
    }
    .frame(height: 8)
    .accessibilityHidden(true)
  }
}

// MARK: - Sky wash

/// The page's time-of-day tint, fading from the top. Morning before 11, day
/// until 17, evening after.
public struct LorvexSkyWash: View {
  public var nowMinutes: Int?
  @Environment(\.colorScheme) private var colorScheme

  public init(nowMinutes: Int?) { self.nowMinutes = nowMinutes }

  private var tint: Color {
    guard let nowMinutes else { return LorvexDesign.Palette.Sky.day }
    if nowMinutes < 11 * 60 { return LorvexDesign.Palette.Sky.morning }
    if nowMinutes < 17 * 60 { return LorvexDesign.Palette.Sky.day }
    return LorvexDesign.Palette.Sky.evening
  }

  public var body: some View {
    LinearGradient(
      colors: [tint.opacity(colorScheme == .dark ? 0.10 : 0.17), tint.opacity(0)],
      startPoint: .top, endPoint: .bottom
    )
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

// MARK: - Sun arc

/// Where the day is, drawn as the sun's path from 7 AM to 7 PM. Today draws it
/// in the list's place when nothing needs doing.
public struct LorvexSunArc: View {
  public var nowMinutes: Int
  public var startLabel: String
  public var endLabel: String
  public var range: ClosedRange<Int>

  public init(
    nowMinutes: Int, startLabel: String, endLabel: String,
    range: ClosedRange<Int> = (7 * 60)...(19 * 60)
  ) {
    self.nowMinutes = nowMinutes
    self.startLabel = startLabel
    self.endLabel = endLabel
    self.range = range
  }

  public var body: some View {
    VStack(spacing: LorvexDesign.Spacing.xs) {
      Canvas { context, size in
        let fraction = min(
          max(Double(nowMinutes - range.lowerBound) / Double(range.upperBound - range.lowerBound), 0), 1)
        let base = size.height - 2
        let rx = size.width / 2 - 8
        let ry = size.height - 12
        let center = CGPoint(x: size.width / 2, y: base)
        func point(_ f: Double) -> CGPoint {
          let angle = Double.pi * (1 - f)
          return CGPoint(x: center.x + rx * cos(angle), y: base - ry * sin(angle))
        }
        var full = Path()
        var done = Path()
        for step in 0...80 {
          let f = Double(step) / 80
          if step == 0 { full.move(to: point(f)) } else { full.addLine(to: point(f)) }
        }
        let doneSteps = Int(fraction * 80)
        for step in 0...max(doneSteps, 1) {
          let f = min(Double(step) / 80, fraction)
          if step == 0 { done.move(to: point(f)) } else { done.addLine(to: point(f)) }
        }
        context.stroke(
          full, with: .color(.secondary.opacity(0.35)),
          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
        context.stroke(
          done, with: .color(LorvexDesign.Palette.Sky.sun.opacity(0.55)),
          style: StrokeStyle(lineWidth: 2, lineCap: .round))
        var horizon = Path()
        horizon.move(to: CGPoint(x: 0, y: base))
        horizon.addLine(to: CGPoint(x: size.width, y: base))
        context.stroke(horizon, with: .color(LorvexDesign.Palette.separator), lineWidth: 1)
        let sun = point(fraction)
        context.fill(
          Path(ellipseIn: CGRect(x: sun.x - 11, y: sun.y - 11, width: 22, height: 22)),
          with: .color(LorvexDesign.Palette.Sky.sun.opacity(0.16)))
        context.fill(
          Path(ellipseIn: CGRect(x: sun.x - 5.5, y: sun.y - 5.5, width: 11, height: 11)),
          with: .color(LorvexDesign.Palette.Sky.sun))
      }
      HStack {
        Text(startLabel)
        Spacer()
        Text(endLabel)
      }
      .font(LorvexDesign.Typography.tertiaryText)
      .foregroundStyle(.secondary)
    }
    .accessibilityHidden(true)
  }
}
