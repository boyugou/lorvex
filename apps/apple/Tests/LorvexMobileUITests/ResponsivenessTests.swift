import XCTest

/// Measures how the iPhone app launches, scrolls, and moves between screens,
/// over the DEBUG sample day with the stress content added (about 50 tasks,
/// long titles, a crowded calendar, a year of habit history).
///
/// `testLaunch` reports XCTest's launch metric: the time from launch until
/// the app answers input, printed as a `measured [<metric>, <unit>] average: …`
/// line. Every other test launches the app with
/// `-lorvexFrameProbe <scenario>:<test name>`, and the app performs that
/// interaction itself and counts how late its main thread delivered frames
/// (`DebugInteractionDriver`, `DebugFrameProbe`), writing the totals to a file
/// in its data container. The test only waits: an element lookup snapshots the
/// app's accessibility tree on its main thread, which the count would take for
/// the app's own stutter. XCTest's scroll metric reports no hitch numbers in
/// the simulator, which is why the app counts them itself.
///
/// `script/ios_sim_responsiveness.sh` runs the suite and collects both. The
/// tests assert nothing about the numbers: they report.
final class ResponsivenessTests: XCTestCase {
  @MainActor
  private func app(opening url: String, probe: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      [
        "-setupCompleted", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        "-lorvexSeedSampleData", "-lorvexSeedStressData", "-lorvexOpenURL", url,
        "-lorvexPreviewNow", "11:20",
      ] + (probe.map { ["-lorvexFrameProbe", $0] } ?? [])
    return app
  }

  @MainActor
  func testLaunch() {
    let app = app(opening: "lorvex://tab/today")
    // The first launch seeds an empty store; the measured ones find it full.
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    Thread.sleep(forTimeInterval: 6)
    app.terminate()
    let options = XCTMeasureOptions()
    options.iterationCount = 5
    measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
      app.launch()
    }
    app.terminate()
  }

  @MainActor func testScrollToday() { run("scroll", "lorvex://tab/today", #function) }
  @MainActor func testScrollTasksAll() { run("scroll", "lorvex://taskscope/all", #function) }
  @MainActor func testScrollTasksCompleted() {
    run("scroll", "lorvex://taskscope/completed", #function)
  }
  @MainActor func testScrollCalendarDay() { run("scroll", "lorvex://tab/calendar", #function) }
  @MainActor func testScrollCalendarMonth() {
    run("scroll", "lorvex://tab/calendar/month", #function)
  }
  @MainActor func testScrollHabits() { run("scroll", "lorvex://tab/habits", #function) }
  @MainActor func testScrollHabitDetail() { run("scroll", "lorvex://firsthabit", #function) }
  @MainActor func testScrollTaskDetail() { run("scroll", "lorvex://firsttask", #function) }
  @MainActor func testScrollReviewWeek() { run("scroll", "lorvex://tab/review/week", #function) }
  @MainActor func testScrollSettings() { run("scroll", "lorvex://dest/settings", #function) }
  @MainActor func testSwitchTabs() { run("tabs", "lorvex://tab/today", #function) }
  @MainActor func testOpenTaskDetail() { run("taskDetail", "lorvex://tab/today", #function) }
  @MainActor func testOpenCapture() { run("capture", "lorvex://tab/today", #function) }

  /// Launches the app on `url` with `scenario`, waits long enough for the
  /// seed (on the first launch), the route, the app's three-second settle, and
  /// the longest scenario, then ends the app.
  @MainActor
  private func run(_ scenario: String, _ url: String, _ function: String) {
    let label = function.replacingOccurrences(of: "()", with: "")
    let app = app(opening: url, probe: "\(scenario):\(label)")
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    Thread.sleep(forTimeInterval: 36)
    app.terminate()
  }
}
