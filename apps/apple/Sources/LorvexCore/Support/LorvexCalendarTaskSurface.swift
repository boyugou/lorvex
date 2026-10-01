import SwiftUI

extension View {
  /// The surface a task wears on a calendar, on every platform and in every
  /// form: a timed block, an all-day pill, a month chip. A faint wash of the
  /// accent tint sits inside a hollow dashed outline, where an event wears its
  /// calendar's solid fill and a leading rail, so time the user set aside for
  /// their own work never reads like a meeting.
  ///
  /// - Parameters:
  ///   - isDone: A finished task fades its wash and outline; it stays on the
  ///     calendar as the day's record without competing with open work.
  ///   - isEmphasized: A task running now or selected firms the outline into a
  ///     solid line over a stronger wash.
  ///   - cornerRadius: The corner radius of the surface's rounded rectangle.
  ///   - lineWidth: The outline's width.
  ///   - hidesContentBeneath: Lays the wash over an opaque base of the
  ///     surrounding background, so a time grid's hour lines and now line pass
  ///     under the surface instead of through its text.
  public func lorvexCalendarTaskSurface(
    isDone: Bool,
    isEmphasized: Bool = false,
    cornerRadius: CGFloat,
    lineWidth: CGFloat = 1,
    hidesContentBeneath: Bool = false
  ) -> some View {
    let color = LorvexDesign.Palette.accent
    let shape = RoundedRectangle(cornerRadius: cornerRadius)
    let fillOpacity: Double = isDone ? 0.04 : (isEmphasized ? 0.16 : 0.08)
    let strokeOpacity: Double = isDone ? 0.35 : (isEmphasized ? 1 : 0.6)
    return
      background {
        if hidesContentBeneath {
          shape.fill(.background)
        }
        shape.fill(color.opacity(fillOpacity))
      }
      .overlay {
        shape.strokeBorder(
          color.opacity(strokeOpacity),
          style: StrokeStyle(lineWidth: lineWidth, dash: isEmphasized ? [] : [3, 2]))
      }
  }
}
