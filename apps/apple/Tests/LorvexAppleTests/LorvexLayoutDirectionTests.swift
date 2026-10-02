import AppKit
import LorvexCore
import SwiftUI
import Testing

/// Controls that point somewhere follow the reading direction: a fold chevron
/// and the paging shortcuts mirror in a right-to-left layout, and a progress
/// ring fills the way the text runs.
@Suite("Right-to-left layout")
@MainActor
struct LorvexLayoutDirectionTests {
  @Test("Paging shortcuts follow the chevrons, mirrored in a right-to-left layout")
  func pagingShortcutsFollowTheChevrons() {
    #expect(LorvexStepDirection.backward.arrowKey(in: .leftToRight).character == KeyEquivalent.leftArrow.character)
    #expect(LorvexStepDirection.forward.arrowKey(in: .leftToRight).character == KeyEquivalent.rightArrow.character)
    #expect(LorvexStepDirection.backward.arrowKey(in: .rightToLeft).character == KeyEquivalent.rightArrow.character)
    #expect(LorvexStepDirection.forward.arrowKey(in: .rightToLeft).character == KeyEquivalent.leftArrow.character)
  }

  @Test("A folded chevron points along the reading direction; an open one points down in both")
  func foldChevronFollowsTheReadingDirection() throws {
    let left = try render(Image(systemName: "chevron.left"))
    let right = try render(Image(systemName: "chevron.right"))
    let down = try render(Image(systemName: "chevron.down"))
    let up = try render(Image(systemName: "chevron.up"))
    func closest(_ chevron: LorvexDisclosureChevron, _ direction: LayoutDirection) throws -> String {
      let pixels = try render(chevron, direction)
      let candidates = [("left", left), ("right", right), ("down", down), ("up", up)]
      return candidates.min { distance(pixels, $0.1) < distance(pixels, $1.1) }!.0
    }
    #expect(try closest(LorvexDisclosureChevron(isExpanded: false), .leftToRight) == "right")
    #expect(try closest(LorvexDisclosureChevron(isExpanded: false), .rightToLeft) == "left")
    #expect(try closest(LorvexDisclosureChevron(isExpanded: true), .leftToRight) == "down")
    #expect(try closest(LorvexDisclosureChevron(isExpanded: true), .rightToLeft) == "down")
  }

  @Test("A progress arc starts at twelve o'clock and fills with the reading direction")
  func progressArcFillsWithTheReadingDirection() throws {
    // A fifth of the ring stays inside the quadrant it starts in.
    let arc = LorvexProgressArc(fraction: 0.2, style: Color.black, lineWidth: 6)
    #expect(try quadrants(render(arc, .leftToRight)) == [.upperRight])
    #expect(try quadrants(render(arc, .rightToLeft)) == [.upperLeft])
    // A segment from six o'clock on, as a segmented ring draws it.
    let segment = LorvexProgressArc(from: 0.5, to: 0.7, style: Color.black, lineWidth: 6, lineCap: .butt)
    #expect(try quadrants(render(segment, .leftToRight)) == [.lowerLeft])
    #expect(try quadrants(render(segment, .rightToLeft)) == [.lowerRight])
  }

  private enum Quadrant: Hashable {
    case upperLeft, upperRight, lowerLeft, lowerRight
  }

  /// The quadrants a drawing covers, leaving out a band along the center
  /// lines where a round line cap spills across.
  private func quadrants(_ pixels: [Int]) -> Set<Quadrant> {
    let side = Self.side
    let half = side / 2
    let band = 4
    var covered: Set<Quadrant> = []
    for y in 0..<side where abs(y - half) > band {
      for x in 0..<side where abs(x - half) > band && pixels[y * side + x] > 128 {
        covered.insert(
          y < half ? (x < half ? .upperLeft : .upperRight) : (x < half ? .lowerLeft : .lowerRight))
      }
    }
    return covered
  }

  private static let side = 48

  /// The glyph's coverage on a fixed square, one alpha value per pixel.
  private func render(_ view: some View, _ direction: LayoutDirection = .leftToRight) throws -> [Int] {
    let renderer = ImageRenderer(
      content: view.font(.system(size: 30))
        .frame(width: CGFloat(Self.side), height: CGFloat(Self.side))
        .environment(\.layoutDirection, direction))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    let bitmap = NSBitmapImageRep(cgImage: image)
    var pixels: [Int] = []
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        pixels.append(Int(((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded()))
      }
    }
    return pixels
  }

  /// The smallest summed difference between two coverages over small shifts,
  /// so a glyph drawn a pixel off center still matches its direction.
  private func distance(_ a: [Int], _ b: [Int]) -> Int {
    let side = Self.side
    var best = Int.max
    for dx in -2...2 {
      for dy in -2...2 {
        var total = 0
        for y in 0..<side {
          for x in 0..<side {
            let sx = x + dx
            let sy = y + dy
            let shifted = (0..<side).contains(sx) && (0..<side).contains(sy) ? a[sy * side + sx] : 0
            total += abs(shifted - b[y * side + x])
          }
        }
        best = min(best, total)
      }
    }
    return best
  }
}
