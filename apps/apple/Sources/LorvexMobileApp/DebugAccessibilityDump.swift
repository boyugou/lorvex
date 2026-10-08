#if DEBUG && os(iOS)
  import UIKit

  /// Dev/QA only: when `-lorvexDumpAX` is passed, prints one `AXDUMP` line for
  /// every accessibility element VoiceOver can reach on screen, a dozen seconds
  /// after launch, then `AXDUMP done`. Each line carries the nesting depth, the
  /// frame in screen points, the traits, label, value, identifier, and custom
  /// action names.
  ///
  /// The walk follows the container protocol VoiceOver uses, so it shows what
  /// an XCUITest element tree does not: the views inside an element built with
  /// `.accessibilityElement(children: .ignore)` stay hidden here, as they do to
  /// VoiceOver. It does not model modal presentation, and a UIKit-backed list
  /// appears in subview order rather than reading order.
  ///
  /// SwiftUI builds its accessibility tree only while accessibility is
  /// enabled, which the simulator does not do by default. Turn it on with
  /// `xcrun simctl spawn <udid> defaults write com.apple.Accessibility
  /// ApplicationAccessibilityEnabled -bool true`, and delete the key afterwards.
  /// Redirected output is block-buffered, so the dump flushes before it ends.
  @MainActor
  enum DebugAccessibilityDump {
    private static let settleSeconds = 12.0

    static func dumpIfRequested() async {
      guard CommandLine.arguments.contains("-lorvexDumpAX") else { return }
      try? await Task.sleep(for: .seconds(settleSeconds))
      for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        for window in scene.windows where !window.isHidden {
          var lines: [String] = []
          visit(window, depth: 0, into: &lines)
          for line in lines { print("AXDUMP \(line)") }
        }
      }
      print("AXDUMP done")
      fflush(stdout)
    }

    private static func visit(_ node: NSObject, depth: Int, into lines: inout [String]) {
      if depth > 90 { return }
      if node.isAccessibilityElement {
        lines.append(describe(node, depth: depth))
        return
      }
      if let view = node as? UIView, view.isHidden || view.alpha < 0.01 || view.accessibilityElementsHidden {
        return
      }
      if let elements = node.accessibilityElements, !elements.isEmpty {
        for case let child as NSObject in elements { visit(child, depth: depth + 1, into: &lines) }
        return
      }
      let count = node.accessibilityElementCount()
      if count != NSNotFound, count > 0 {
        for index in 0..<count {
          if let child = node.accessibilityElement(at: index) as? NSObject {
            visit(child, depth: depth + 1, into: &lines)
          }
        }
        return
      }
      if let view = node as? UIView {
        for subview in view.subviews { visit(subview, depth: depth + 1, into: &lines) }
      }
    }

    private static func describe(_ node: NSObject, depth: Int) -> String {
      let traits = node.accessibilityTraits
      let table: [(UIAccessibilityTraits, String)] = [
        (.button, "button"), (.link, "link"), (.image, "image"), (.selected, "selected"),
        (.staticText, "text"), (.header, "header"), (.notEnabled, "disabled"),
        (.adjustable, "adjustable"), (.searchField, "search"), (.summaryElement, "summary"),
      ]
      let names = table.filter { traits.contains($0.0) }.map(\.1)
      let frame = node.accessibilityFrame
      let label = (node.accessibilityLabel ?? "").replacingOccurrences(of: "\n", with: "⏎")
      let value = (node.accessibilityValue ?? "").replacingOccurrences(of: "\n", with: "⏎")
      let identifier = (node as? UIAccessibilityIdentification)?.accessibilityIdentifier ?? ""
      let actions = (node.accessibilityCustomActions ?? []).map(\.name).joined(separator: "|")
      return
        "E \(depth) [\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))] "
        + "traits=\(names.joined(separator: ",")) label='\(label)' value='\(value)' "
        + "id='\(identifier)' actions='\(actions)'"
    }
  }
#endif
