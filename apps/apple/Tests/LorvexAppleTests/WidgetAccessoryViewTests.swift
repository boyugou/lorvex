import Foundation
import LorvexWidgetKitSupport
import Testing

@testable import LorvexWidgetViews

// Behavior of the Lock Screen accessory families (Focus + Habits): the
// unavailable/empty/remaining boundary of the circular view, redaction of user-authored
// content, and that every accessory family constructs its body without a crash
// in both the empty and populated states.

// MARK: - Focus circular: unavailable vs empty vs remaining classification

@Test
func focusCircularIsEmptyWhenNothingTracked() {
  // No focus tasks and nothing completed: the empty glyph, not a "0" ring that a
  // glance could misread as "0% done".
  #expect(AccessoryCircularWidgetView.content(focusCount: 0) == .empty)
}

@Test
func focusCircularShowsOnlyTheRemainingFocusCount() {
  #expect(AccessoryCircularWidgetView.content(focusCount: 1) == .remaining(1))
  #expect(AccessoryCircularWidgetView.content(focusCount: 4) == .remaining(4))
}

@Test
func focusCircularDoesNotTreatGlobalCompletionsAsFocusProgress() {
  // The view no longer accepts a completed-today input: unrelated completed
  // tasks cannot turn an empty focus plan into a full progress ring.
  #expect(AccessoryCircularWidgetView.content(focusCount: 0) == .empty)
}

@Test
func focusCircularClampsNegativeInputs() {
  #expect(AccessoryCircularWidgetView.content(focusCount: -2) == .empty)
}

@Test
func focusCircularClassifiesFallbackAsUnavailableNotEmpty() {
  // A `.fallback` render state coerces every count to 0, which would otherwise
  // classify as `.empty` and show the "no focus set" glyph — reassuring the user
  // that all is well when the snapshot actually failed to load. Fallback must win
  // over the counts and render the distinct unavailable glyph.
  #expect(
    AccessoryCircularWidgetView.content(state: .fallback, focusCount: 0)
      == .unavailable)
  #expect(
    AccessoryCircularWidgetView.content(state: .fallback, focusCount: 2)
      == .unavailable)
  // A genuine empty (fresh snapshot, nothing tracked) stays `.empty`.
  #expect(
    AccessoryCircularWidgetView.content(state: .empty, focusCount: 0) == .empty)
}

@MainActor
@Test
func focusFallbackFamiliesRenderUnavailableNotAllClear() {
  // The small, inline, and circular Focus families each construct their body for
  // a `.fallback` model without trapping. A broken snapshot reaches these with
  // counts of 0; the honest-fallback branch must handle it distinctly from the
  // genuine empty "All clear".
  let model = fallbackAccessoryModel(.systemSmall)
  _ = SmallSystemWidgetView(model: model).body
  _ = AccessoryInlineWidgetView(model: fallbackAccessoryModel(.accessoryInline)).body
  _ = AccessoryCircularWidgetView(model: fallbackAccessoryModel(.accessoryCircular)).body
}

@Test
func focusFallbackBranchesAreDistinctFromAllClear() throws {
  // Guard against a regression that drops the fallback branch and lets a broken
  // snapshot fall through to the "All clear" empty treatment. Each view must
  // branch on `model.state == .fallback`.
  for file in [
    "LorvexWidgetSmallView.swift",
    "LorvexWidgetAccessoryInlineView.swift",
    "LorvexWidgetAccessoryCircularView.swift",
  ] {
    #expect(
      try widgetViewsSource(file).contains(".fallback"),
      "\(file) must branch on the fallback render state")
  }
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
func focusAccessoryTitlesAreRedactionAware() throws {
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
  #expect(source.contains("model.focusCount == 0"))
  #expect(source.contains("widget.small.all_clear"))
}

// MARK: - Fixtures

private func emptyAccessoryModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
  WidgetRenderModel(
    family: family,
    state: .empty,
    headline: "Focus",
    subheadline: "No focus tasks yet.",
    statusText: "Updated now",
    focusCountText: "0 in focus",
    focusCount: 0,
    completedCount: 0,
    attentionCountText: nil,
    taskRows: []
  )
}

private func contentAccessoryModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
  WidgetRenderModel(
    family: family,
    state: .content,
    headline: family == .accessoryInline ? "Ship the widget polish" : "Focus",
    subheadline: "Focus on the next useful step.",
    statusText: "Updated now",
    focusCountText: "2 in focus",
    focusCount: 2,
    completedCount: 1,
    attentionCountText: "1 due",
    taskRows: [
      WidgetTaskRenderRow(
        id: "task-1", title: "Ship the widget polish", metadata: "25m",
        priorityLabel: "Priority 1", priorityTier: 1, urlString: "lorvex://task/task-1")
    ]
  )
}

private func fallbackAccessoryModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
  // Mirrors what `WidgetRenderModelBuilder` emits for a `.fallback` entry: the
  // honest "unavailable" copy with every count coerced to 0.
  WidgetRenderModel(
    family: family,
    state: .fallback,
    headline: "Lorvex",
    subheadline: "Widget data is not available.",
    statusText: "Open Lorvex to refresh",
    focusCountText: "0 in focus",
    focusCount: 0,
    completedCount: 0,
    attentionCountText: nil,
    taskRows: []
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
