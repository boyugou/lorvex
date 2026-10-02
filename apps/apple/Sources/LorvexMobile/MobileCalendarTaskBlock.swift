import LorvexCore
import SwiftUI
#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// A timed task on the phone's day grid: the task's time on its planned day,
/// drawn on the time axis in the accent tint. It borrows the task row's
/// vocabulary rather than the event block's — a leading ring that completes
/// the task and the calendar task surface (`lorvexCalendarTaskSurface`, a
/// hollow dashed outline) instead of an event's solid fill and rail — so a
/// hold on the calendar and an intention for the day never read alike. The
/// block opens its task, where the time is changed or cleared. A compact
/// block (``LorvexDesign/CalendarMetrics/compactLaneWidth``) drops the ring,
/// which would leave no room for the title and is too small to aim at; its
/// context menu still completes the task.
extension MobileCalendarDayColumn {
  func taskBlock(
    _ block: CalendarGridTaskBlock, day: CalendarGridDay, columnWidth: CGFloat
  ) -> some View {
    let laneBand = max(
      columnWidth - LorvexDesign.CalendarMetrics.laneTrailingInset(columnWidth: columnWidth), 1)
    let laneWidth = laneBand / CGFloat(block.laneCount)
    let y = CGFloat(block.startMin) / 60 * hourHeight
    // The drawn end carries the model's minimum height; see `eventBlock`.
    let height = CGFloat(block.drawnEndMin - block.startMin) / 60 * hourHeight
    let isTight = height < LorvexDesign.CalendarMetrics.tightBlockHeight
    let isCompact = laneWidth < LorvexDesign.CalendarMetrics.compactLaneWidth
    let isRunning = isRunningNow(block, day) && !block.isDone
    let toggleLabel = MobileTaskActionCopy.completionToggle(isDone: block.isDone)
    return Group {
      if isCompact {
        MobileCalendarCompactBlockTitle(block.task.title, isDone: block.isDone)
          .padding(.leading, 1)
          .padding(.vertical, isTight ? 0 : 3)
      } else {
        LorvexCalendarBlockText(
          title: block.task.title,
          start: lorvexClockTimeLabel(minutes: block.startMin),
          range: lorvexClockRangeLabel(startMinutes: block.startMin, endMinutes: block.endMin),
          isDone: block.isDone,
          verticalPadding: 3,
          accessorySpacing: 2
        ) {
          MobileCalendarTaskRing(
            isDone: block.isDone, font: LorvexDesign.Typography.secondaryText, width: 20
          ) {
            onToggleTask(block.task)
          }
        }
      }
    }
    .padding(.leading, 2)
    .padding(.trailing, isCompact ? 2 : 5)
    .frame(width: max(laneWidth - 2, 10), height: height, alignment: .topLeading)
    .clipped()
    .lorvexCalendarTaskSurface(
      isDone: block.isDone,
      isEmphasized: isRunning,
      cornerRadius: LorvexDesign.Radius.s,
      hidesContentBeneath: true)
    .contentShape(Rectangle())
    .zIndex(1)
    .offset(x: CGFloat(block.lane) * laneWidth, y: y)
    .onTapGesture { onTapTask(block.task) }
    .contextMenu {
      Button {
        onTapTask(block.task)
      } label: {
        Label(MobileCalendarTaskCopy.open, systemImage: "arrow.up.forward.square")
      }
      Button {
        onToggleTask(block.task)
      } label: {
        Label(toggleLabel, systemImage: MobileCalendarTaskCopy.toggleSystemImage(isDone: block.isDone))
      }
    }
    // One VoiceOver element per block: the label names the task and its slot,
    // the default action opens it, and the ring's completion is a named action
    // rather than a second 24pt element to hunt for inside the block.
    .accessibilityElement(children: .ignore)
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(taskBlockAccessibilityLabel(block))
    .accessibilityAction { onTapTask(block.task) }
    .accessibilityAction(named: Text(toggleLabel)) { onToggleTask(block.task) }
    .accessibilityIdentifier("mobileCalendar.taskBlock")
  }

  private func taskBlockAccessibilityLabel(_ block: CalendarGridTaskBlock) -> String {
    String(
      format: String(
        localized: "calendar.task_block.a11y",
        defaultValue: "Task %@, %@ to %@",
        table: "Localizable",
        bundle: MobileL10n.bundle),
      block.task.title,
      lorvexClockTimeLabel(minutes: block.startMin),
      lorvexClockTimeLabel(minutes: block.endMin))
  }
}

/// The title of a compact grid block: small, wrapping onto as many lines as
/// the block is tall, then truncated, with no time beside it. A finished
/// task's title is struck through and secondary.
///
/// Lines break between words: when the title's longest word is wider than
/// the block ("Roadmap" in a phone week's 40pt lane), the face shrinks just
/// enough for that word to fit one line, down to
/// ``MobileCalendarCompactTitleFit/minimumScale``, rather than splitting the
/// word across lines.
struct MobileCalendarCompactBlockTitle: View {
  private let title: String
  private let isDone: Bool
  @State private var width: CGFloat = 0
  /// ``LorvexDesign/CalendarMetrics/compactBlockText``'s size, scaled with
  /// the text.
  @ScaledMetric(relativeTo: .caption2) private var baseSize: CGFloat = 11

  init(_ title: String, isDone: Bool = false) {
    self.title = title
    self.isDone = isDone
  }

  var body: some View {
    Text(userContent: title)
      // Scaled with the text through baseSize, then fitted to the block.
      .font(.system(size: fittedSize, weight: .medium).width(.condensed))  // lorvex-design-token: allow
      .strikethrough(isDone)
      .foregroundStyle(isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      .lineLimit(nil)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
  }

  private var fittedSize: CGFloat {
    baseSize * MobileCalendarCompactTitleFit.scale(title: title, size: baseSize, width: width)
  }
}

/// How far a compact block's title face shrinks so its longest word fits the
/// block's width on one line.
enum MobileCalendarCompactTitleFit {
  /// The smallest scale a title takes; a word still too wide at this size
  /// breaks as it would have.
  static let minimumScale: CGFloat = 0.8

  /// Points of the block's width the measurement leaves to the text
  /// layout's own line padding and rounding, so a word measured to fit does
  /// fit.
  static let layoutAllowance: CGFloat = 2

  /// 1 while the longest word of `title` fits `width` at `size`, otherwise
  /// the scale that makes it fit, no smaller than ``minimumScale``. An
  /// unmeasured (zero) width keeps the full size.
  static func scale(title: String, size: CGFloat, width: CGFloat) -> CGFloat {
    guard width > 0 else { return 1 }
    let room = width - layoutAllowance
    let widest = title.split(whereSeparator: \.isWhitespace)
      .map { wordWidth(String($0), size: size) }
      .max() ?? 0
    guard widest > room else { return 1 }
    return max(minimumScale, room / widest)
  }

  private static func wordWidth(_ word: String, size: CGFloat) -> CGFloat {
    #if canImport(UIKit)
      let font = UIFont.systemFont(ofSize: size, weight: .medium, width: .condensed)
    #else
      let font = NSFont.systemFont(ofSize: size, weight: .medium, width: .condensed)
    #endif
    return ceil((word as NSString).size(withAttributes: [.font: font]).width)
  }
}
