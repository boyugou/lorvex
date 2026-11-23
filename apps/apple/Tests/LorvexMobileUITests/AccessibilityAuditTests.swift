import XCTest

/// Runs XCTest's accessibility audit on the app's screens over the DEBUG
/// sample day and prints one line per finding. The test reports and never
/// fails on a finding: which findings are real is a judgement made by reading
/// them beside the screenshot of the screen they came from.
///
/// `script/ios_sim_accessibility_audit.sh` runs it and collects the lines.
/// Each starts with `AXAUDIT|<screen>|`, then either
/// `<kind>|<element type>|<label>|<identifier>|<x>,<y> <width>x<height>|<description>`
/// for a finding, `window|<width>x<height>` for the app window's size in
/// points, `done|<count>` after a screen, or `error|<message>` when the
/// audit itself could not run. Three environment variables of the test
/// runner steer it: `LORVEX_AUDIT_SCREENS` (comma-separated screen names;
/// all when unset), `LORVEX_AUDIT_OUT` (a directory that receives one
/// screenshot per screen), and `LORVEX_AUDIT_TEXT_SIZE` (a
/// `UIContentSizeCategory` name the app launches with).
final class AccessibilityAuditTests: XCTestCase {
  private struct Screen {
    let name: String
    let url: String
    var arguments: [String] = []
  }

  private static let screens: [Screen] = [
    Screen(name: "today", url: "lorvex://tab/today"),
    Screen(name: "tasks", url: "lorvex://tab/tasks"),
    Screen(name: "calendar", url: "lorvex://tab/calendar"),
    Screen(name: "calendar-week", url: "lorvex://tab/calendar/week"),
    Screen(name: "calendar-month", url: "lorvex://tab/calendar/month"),
    Screen(name: "habits", url: "lorvex://tab/habits"),
    Screen(name: "review", url: "lorvex://tab/review"),
    Screen(name: "review-week", url: "lorvex://tab/review/week"),
    Screen(name: "task-detail", url: "lorvex://firsttask"),
    Screen(name: "task-edit", url: "lorvex://firsttask/edit"),
    Screen(name: "habit-detail", url: "lorvex://firsthabit"),
    Screen(name: "capture", url: "lorvex://sheet/capture"),
    Screen(name: "event-detail", url: "lorvex://sheet/eventdetail"),
    Screen(name: "lists", url: "lorvex://dest/lists"),
    Screen(name: "memory", url: "lorvex://dest/memory"),
    Screen(name: "settings", url: "lorvex://dest/settings"),
    Screen(
      name: "settings-end", url: "lorvex://dest/settings",
      arguments: ["-lorvexScrollSettingsToEnd"]),
  ]

  private static let kinds: [(XCUIAccessibilityAuditType, String)] = [
    (.contrast, "contrast"),
    (.elementDetection, "elementDetection"),
    (.hitRegion, "hitRegion"),
    (.sufficientElementDescription, "description"),
    (.dynamicType, "dynamicType"),
    (.textClipped, "textClipped"),
    (.trait, "trait"),
  ]

  @MainActor func testAuditScreens() throws {
    continueAfterFailure = true
    // An empty value means the same as an unset one.
    func setting(_ name: String) -> String? {
      ProcessInfo.processInfo.environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }
    let wanted = setting("LORVEX_AUDIT_SCREENS").map {
      Set($0.split(separator: ",").map(String.init))
    }
    let screens = Self.screens.filter { wanted?.contains($0.name) ?? true }
    XCTAssertFalse(screens.isEmpty, "LORVEX_AUDIT_SCREENS names no known screen")
    for screen in screens {
      audit(
        screen, textSize: setting("LORVEX_AUDIT_TEXT_SIZE"),
        screenshots: setting("LORVEX_AUDIT_OUT"))
    }
  }

  @MainActor
  private func audit(_ screen: Screen, textSize: String?, screenshots: String?) {
    let app = XCUIApplication()
    app.launchArguments =
      [
        "-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        "-lorvexSeedSampleData", "-lorvexOpenURL", screen.url, "-lorvexPreviewNow", "11:20",
      ] + screen.arguments
      + (textSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
    app.launch()
    guard app.wait(for: .runningForeground, timeout: 20) else {
      print("AXAUDIT|\(screen.name)|error|the app did not reach the foreground")
      return
    }
    // The route opens after the first data load, and its scroll hooks settle
    // a few runloop turns later.
    Thread.sleep(forTimeInterval: screen.arguments.isEmpty ? 5 : 8)
    if let screenshots {
      let file = URL(fileURLWithPath: screenshots).appendingPathComponent("\(screen.name).png")
      try? XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
    }
    let window = app.windows.firstMatch.frame
    print("AXAUDIT|\(screen.name)|window|\(Int(window.width))x\(Int(window.height))")

    var count = 0
    do {
      try app.performAccessibilityAudit(for: .all) { issue in
        count += 1
        print("AXAUDIT|\(screen.name)|\(Self.line(for: issue))")
        return true
      }
      print("AXAUDIT|\(screen.name)|done|\(count)")
    } catch {
      print("AXAUDIT|\(screen.name)|error|\(Self.oneLine(String(describing: error)))")
    }
    app.terminate()
  }

  @MainActor
  private static func line(for issue: XCUIAccessibilityAuditIssue) -> String {
    let kind =
      kinds.filter { issue.auditType.contains($0.0) }.map(\.1).joined(separator: "+")
    var element = "-|-|-|-"
    if let target = issue.element {
      if target.exists {
        let frame = target.frame
        element = [
          String(describing: target.elementType.rawValue),
          oneLine(target.label),
          oneLine(target.identifier),
          "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))",
        ].joined(separator: "|")
      } else {
        // The audit names an element the app no longer resolves; its query's
        // description is the only trace of it.
        element = "-|\(oneLine(target.description))|-|-"
      }
    }
    let description = oneLine(issue.compactDescription + " — " + issue.detailedDescription)
    return "\(kind.isEmpty ? "other" : kind)|\(element)|\(description)"
  }

  private static func oneLine(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
  }
}
