import Foundation
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWidgetViews

// Behavior of the Lock Screen accessory families (Today + Habits): what the
// circular glance says, redaction of user-authored content, and that every
// accessory family constructs its body without a crash in both the empty and
// populated states.

// MARK: - Today circular: what the ring says

private func lead(
  isRunning: Bool = false, minutesLeft: Int? = nil, progress: Double = 0
) -> WidgetLeadRender {
  WidgetLeadRender(
    id: "task-1", title: "Ship the widget polish", line: nil, shortLine: nil,
    progress: progress, isRunning: isRunning, minutesLeft: minutesLeft, isOverdue: false,
    urlString: "lorvex://task/task-1")
}

private func circularModel(
  state: WidgetRenderState = .content, lead: WidgetLeadRender?, upcoming: Int = 0
) -> WidgetRenderModel {
  WidgetRenderModel(
    family: .accessoryCircular, state: state, headline: "Today", subheadline: "",
    statusText: "Updated now", lead: lead, upcomingCount: upcoming)
}

@Test
func todayCircularShowsACheckmarkWhenNothingIsLeft() {
  // No lead: the checkmark, not a "0" ring that a glance could misread as
  // "0% done" — however many tasks got completed today.
  #expect(circularModel(lead: nil).circularContent == .empty)
  #expect(circularModel(state: .empty, lead: nil).circularContent == .empty)
}

@Test
func todayCircularCountsDownARunningTime() {
  #expect(
    circularModel(lead: lead(isRunning: true, minutesLeft: 12, progress: 0.7), upcoming: 2)
      .circularContent == .running(minutesLeft: 12))
}

@Test
func todayCircularShowsTheTasksLeftWhenNoTimeRuns() {
  #expect(circularModel(lead: lead(), upcoming: 0).circularContent == .remaining(1))
  #expect(circularModel(lead: lead(), upcoming: 3).circularContent == .remaining(4))
}

@Test
func todayCircularClassifiesFallbackAsUnavailableNotEmpty() {
  // A `.fallback` render state would otherwise classify as `.empty` and show
  // the "All clear" checkmark — reassuring the user that all is well when the
  // snapshot actually failed to load. Fallback must win over the content.
  #expect(circularModel(state: .fallback, lead: nil).circularContent == .unavailable)
  #expect(
    circularModel(state: .fallback, lead: lead(isRunning: true, minutesLeft: 5), upcoming: 1)
      .circularContent == .unavailable)
}

@MainActor
@Test
func todayFallbackFamiliesRenderUnavailableNotAllClear() {
  // The small, inline, and circular Today families each construct their body for
  // a `.fallback` model without trapping. A broken snapshot reaches these with
  // counts of 0; the honest-fallback branch must handle it distinctly from the
  // genuine empty "All clear".
  let model = fallbackAccessoryModel(.systemSmall)
  _ = SmallSystemWidgetView(model: model).body
  _ = AccessoryInlineWidgetView(model: fallbackAccessoryModel(.accessoryInline)).body
  _ = AccessoryCircularWidgetView(model: fallbackAccessoryModel(.accessoryCircular)).body
}

@Test
func todayFallbackBranchesAreDistinctFromAllClear() throws {
  // Guard against a regression that drops the fallback branch and lets a broken
  // snapshot fall through to the "All clear" empty treatment. The small and
  // inline views branch on `model.state == .fallback`; the circular view draws
  // the render model's `.unavailable` content.
  for file in [
    "LorvexWidgetSmallView.swift",
    "LorvexWidgetAccessoryInlineView.swift",
  ] {
    #expect(
      try widgetViewsSource(file).contains(".fallback"),
      "\(file) must branch on the fallback render state")
  }
  #expect(try widgetViewsSource("LorvexWidgetAccessoryCircularView.swift").contains(".unavailable"))
}

// MARK: - Accessory view bodies construct in both states

@MainActor
@Test
func accessoryFamilyBodiesConstructForEmptyAndContentModels() {
  // Exercise each accessory view's own body (not just the dispatcher) in both
  // the empty and populated states, so an empty-state branch that traps at
  // runtime — e.g. a degenerate gauge range — is caught here.
  for model in [emptyAccessoryModel(.accessoryInline), contentAccessoryModel(.accessoryInline)] {
    _ = AccessoryInlineWidgetView(model: model).body
  }
  for model in [
    emptyAccessoryModel(.accessoryRectangular), contentAccessoryModel(.accessoryRectangular),
  ] {
    _ = AccessoryRectangularWidgetView(model: model).body
  }
  for model in [emptyAccessoryModel(.accessoryCircular), contentAccessoryModel(.accessoryCircular)]
  {
    _ = AccessoryCircularWidgetView(model: model).body
  }
}

@MainActor
@Test
func habitsCircularBodyConstructsWhenEmptyAndPopulated() {
  _ = HabitsAccessoryCircularView(habits: []).body
  _ =
    HabitsAccessoryCircularView(habits: [
      .init(id: "h1", name: "Meditate", icon: "figure.mind.and.body", completedToday: 1, target: 1)
    ]).body
}

// MARK: - Privacy redaction guards (Lock Screen / StandBy)

// User-authored content (task titles, habit names) rendered on a surface that can
// appear on a locked device must carry `.privacySensitive()` so the system
// redacts it when the device locks. These guard against a regression that drops
// the modifier and silently leaks content onto the Lock Screen / StandBy.
@Test
func habitNameIsRedactionAwareOnStandBy() throws {
  let source = try widgetViewsSource("LorvexHabitsWidgetView.swift")
  #expect(source.contains("Text(habit.name)"))
  #expect(source.contains(".privacySensitive()"))
}

@Test
func todayAccessoryTitlesAreRedactionAware() throws {
  // Inline shows the top task's title; rectangular shows task-row titles. Both
  // are private and must redact on a locked Lock Screen.
  #expect(
    try widgetViewsSource("LorvexWidgetAccessoryInlineView.swift").contains(".privacySensitive()"))
  #expect(
    try widgetViewsSource("LorvexWidgetAccessoryRectangularView.swift").contains(
      ".privacySensitive()"))
}

@Test
func inlineEmptyStateIsNonSensitiveAndLegible() throws {
  // The empty inline shows a non-sensitive "All clear" that stays legible when
  // locked, rather than redacting a benign line to a placeholder bar.
  let source = try widgetViewsSource("LorvexWidgetAccessoryInlineView.swift")
  #expect(source.contains("model.lead == nil"))
  #expect(source.contains("widget.small.all_clear"))
}

// MARK: - Fixtures

private func emptyAccessoryModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
  WidgetRenderModel(
    family: family,
    state: .empty,
    headline: "Today",
    subheadline: "Nothing left today.",
    statusText: "Updated now",
    completedCount: 0
  )
}

private func contentAccessoryModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
  WidgetRenderModel(
    family: family,
    state: .content,
    headline: family == .accessoryInline ? "Ship the widget polish" : "Today",
    subheadline: "",
    statusText: "Updated now",
    completedCount: 1,
    lead: lead(isRunning: true, minutesLeft: 12, progress: 0.7),
    taskRows: [
      WidgetTaskRenderRow(
        id: "task-2", title: "Write the release note", metadata: "11:00 AM",
        urlString: "lorvex://task/task-2")
    ],
    upcomingCount: 1
  )
}

private func fallbackAccessoryModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
  // Mirrors what `WidgetRenderModelBuilder` emits for a `.fallback` entry: the
  // honest "unavailable" copy with no lead and every count at 0.
  WidgetRenderModel(
    family: family,
    state: .fallback,
    headline: "Lorvex",
    subheadline: "Widget data is not available.",
    statusText: "Open Lorvex to refresh",
    completedCount: 0
  )
}

private func widgetViewsSource(_ fileName: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url = root.appendingPathComponent("Sources/LorvexWidgetViews/\(fileName)")
  return try String(contentsOf: url, encoding: .utf8)
}
