import CoreGraphics
import Testing

@testable import LorvexApple

@Test
func windowPlacementCentersFullyOffscreenFrame() {
  let screen = CGRect(x: 0, y: 0, width: 1512, height: 900)
  let frame = CGRect(x: -116, y: -941, width: 1320, height: 760)

  let clamped = LorvexWindowPlacement.clampedFrame(
    for: frame,
    visibleFrames: [screen],
    minimumSize: CGSize(width: 980, height: 640)
  )

  #expect(clamped.minX >= screen.minX)
  #expect(clamped.minY >= screen.minY)
  #expect(clamped.maxX <= screen.maxX)
  #expect(clamped.maxY <= screen.maxY)
  #expect(clamped.width == 1320)
  #expect(clamped.height == 760)
}

@Test
func windowPlacementPreservesUsablyVisibleFrame() {
  let screen = CGRect(x: 0, y: 0, width: 1512, height: 900)
  let frame = CGRect(x: 120, y: 80, width: 1280, height: 760)

  let clamped = LorvexWindowPlacement.clampedFrame(
    for: frame,
    visibleFrames: [screen],
    minimumSize: CGSize(width: 980, height: 640)
  )

  #expect(clamped == frame)
}

@Test
func windowPlacementClampsBarelyVisibleFrameInsideScreen() {
  let screen = CGRect(x: 0, y: 0, width: 1512, height: 900)
  let frame = CGRect(x: 1430, y: 40, width: 980, height: 640)

  let clamped = LorvexWindowPlacement.clampedFrame(
    for: frame,
    visibleFrames: [screen],
    minimumSize: CGSize(width: 980, height: 640)
  )

  #expect(clamped.minX >= screen.minX)
  #expect(clamped.maxX <= screen.maxX)
  #expect(clamped.minY == frame.minY)
}

@Test
func windowPlacementClampsPartiallyOffscreenPrimaryChromeInsideScreen() {
  let screen = CGRect(x: 0, y: 0, width: 1512, height: 900)
  let frame = CGRect(x: -220, y: 80, width: 1320, height: 760)

  let clamped = LorvexWindowPlacement.clampedFrame(
    for: frame,
    visibleFrames: [screen],
    minimumSize: CGSize(width: 980, height: 640)
  )

  #expect(clamped.minX >= screen.minX)
  #expect(clamped.maxX <= screen.maxX)
  #expect(clamped.minY == frame.minY)
  #expect(clamped.width == frame.width)
}

@Test
func windowPlacementClampsSmallSourceListOverhangInsideScreen() {
  let screen = CGRect(x: 0, y: 0, width: 1512, height: 900)
  let frame = CGRect(x: -18, y: 80, width: 1320, height: 760)

  let clamped = LorvexWindowPlacement.clampedFrame(
    for: frame,
    visibleFrames: [screen],
    minimumSize: CGSize(width: 980, height: 640)
  )

  #expect(clamped.minX >= screen.minX)
  #expect(clamped.maxX <= screen.maxX)
  #expect(clamped.minY == frame.minY)
}
