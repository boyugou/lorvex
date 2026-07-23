import AppKit

enum LorvexWindowPlacement {
  private static let edgePadding: CGFloat = 24
  private static let minimumVisibleWidth: CGFloat = 160
  private static let minimumVisibleHeight: CGFloat = 120
  private static let minimumVisibleRatio: CGFloat = 0.82

  @MainActor
  static func bringUsableWindowForwardOrRecover() -> Bool {
    clampVisibleWindowsToScreens()
    guard let window = NSApp.windows.first(where: isUsableVisibleWindow) else {
      return false
    }
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    return true
  }

  @MainActor
  static func clampVisibleWindowsToScreens() {
    let visibleFrames = NSScreen.screens.map(\.visibleFrame)
    guard !visibleFrames.isEmpty else { return }

    for window in NSApp.windows where window.isVisible && !window.isMiniaturized {
      let frame = clampedFrame(
        for: window.frame,
        visibleFrames: visibleFrames,
        minimumSize: window.minSize
      )
      if !frame.equalTo(window.frame) {
        window.setFrame(frame, display: false)
      }
    }
  }

  static func clampedFrame(
    for frame: CGRect,
    visibleFrames: [CGRect],
    minimumSize: CGSize
  ) -> CGRect {
    guard let target = targetVisibleFrame(for: frame, visibleFrames: visibleFrames) else {
      return frame
    }
    if isUsablyVisible(frame, in: visibleFrames) {
      return frame
    }

    let width = min(max(frame.width, minimumSize.width), target.width - edgePadding * 2)
    let height = min(max(frame.height, minimumSize.height), target.height - edgePadding * 2)
    let size = CGSize(width: max(1, width), height: max(1, height))

    if frame.intersects(target) {
      return CGRect(
        x: clamp(frame.minX, min: target.minX + edgePadding, max: target.maxX - size.width - edgePadding),
        y: clamp(frame.minY, min: target.minY + edgePadding, max: target.maxY - size.height - edgePadding),
        width: size.width,
        height: size.height
      )
    }

    return CGRect(
      x: target.midX - size.width / 2,
      y: target.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  static func isUsablyVisible(_ frame: CGRect, in visibleFrames: [CGRect]) -> Bool {
    visibleFrames.contains { visibleFrame in
      let intersection = frame.intersection(visibleFrame)
      let widthThreshold = max(minimumVisibleWidth, frame.width * minimumVisibleRatio)
      let heightThreshold = max(minimumVisibleHeight, frame.height * minimumVisibleRatio)
      return frame.minX >= visibleFrame.minX
        && frame.maxX <= visibleFrame.maxX
        && frame.minY >= visibleFrame.minY
        && frame.maxY <= visibleFrame.maxY
        && intersection.width >= widthThreshold
        && intersection.height >= heightThreshold
    }
  }

  @MainActor
  private static func isUsableVisibleWindow(_ window: NSWindow) -> Bool {
    window.isVisible
      && !window.isMiniaturized
      && isUsablyVisible(window.frame, in: NSScreen.screens.map(\.visibleFrame))
  }

  private static func targetVisibleFrame(
    for frame: CGRect,
    visibleFrames: [CGRect]
  ) -> CGRect? {
    guard !visibleFrames.isEmpty else { return nil }
    if let intersecting = visibleFrames.max(by: {
      frame.intersection($0).area < frame.intersection($1).area
    }), frame.intersects(intersecting) {
      return intersecting
    }
    return visibleFrames.max(by: { $0.area < $1.area })
  }

  private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
    if maxValue < minValue { return minValue }
    return min(max(value, minValue), maxValue)
  }
}

private extension CGRect {
  var area: CGFloat {
    guard !isNull, !isInfinite else { return 0 }
    return max(0, width) * max(0, height)
  }
}
