import Foundation
import LorvexCore
@testable import LorvexWidgetExtension
import LorvexWidgetKitSupport
import Testing
import WidgetKit

@Test
func widgetConfigurationBuildsSnapshotURLInsideLorvexDirectory() {
  let configuration = LorvexWidgetConfiguration(
    appGroupID: "group.com.lorvex.apple",
    snapshotFileName: "custom-widget.json"
  )
  let containerURL = URL(fileURLWithPath: "/tmp/group.com.lorvex.apple", isDirectory: true)

  let url = configuration.snapshotURL(in: containerURL)

  #expect(url.path == "/tmp/group.com.lorvex.apple/Lorvex/custom-widget.json")
}

@Test
func widgetConfigurationDefaultsUseStorageAndRoutingMetadata() {
  let configuration = LorvexWidgetConfiguration()

  #expect(configuration.kind == LorvexProductMetadata.widgetKind)
  #expect(configuration.appGroupID == nil)
  #expect(configuration.snapshotFileName == WidgetSnapshotLoader.defaultSnapshotFileName)
}

@Test
@MainActor
func additionalWidgetKindsUseSharedProductMetadata() {
  #expect(LorvexTodayWidget.kind == LorvexProductMetadata.todayWidgetKind)
  #expect(LorvexProgressWidget.kind == LorvexProductMetadata.progressWidgetKind)
  #expect(LorvexHabitsWidget.kind == LorvexProductMetadata.habitsWidgetKind)
}

@Test
func widgetConfigurationReadsAppGroupOnlyFromExplicitInfoPlistKey() {
  #expect(LorvexWidgetConfiguration.appGroupInfoPlistKey == "LorvexWidgetAppGroupID")
  #expect(LorvexWidgetConfiguration.defaultAppGroupID() == nil)
}

/// The widget reader resolves its App Group from the `LorvexWidgetAppGroupID`
/// Info.plist key, while the host writer publishes the snapshot under the Swift
/// constant `LorvexProductMetadata.appGroupIdentifier`. They must name the same
/// group or the widget silently reads an empty container while the app keeps
/// writing. This gate fails the build if the two sources of truth diverge.
@Test
func widgetInfoPlistAppGroupMatchesSharedProductMetadata() throws {
  let plistURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // …/Tests/LorvexAppleTests
    .deletingLastPathComponent()  // …/Tests
    .deletingLastPathComponent()  // …/apple
    .appendingPathComponent("Config")
    .appendingPathComponent("LorvexWidgetExtension-Info.plist")

  let data = try Data(contentsOf: plistURL)
  let plist = try #require(
    try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  let declaredAppGroup = plist[LorvexWidgetConfiguration.appGroupInfoPlistKey] as? String

  #expect(declaredAppGroup == LorvexProductMetadata.appGroupIdentifier)
}

@Test
func widgetProviderMapsSystemFamiliesToRenderFamilies() {
  #expect(LorvexFocusWidgetProvider.familyKind(for: .systemSmall) == .systemSmall)
  #expect(LorvexFocusWidgetProvider.familyKind(for: .systemMedium) == .systemMedium)
  #expect(LorvexFocusWidgetProvider.familyKind(for: .systemLarge) == .systemLarge)
  #if os(iOS)
    #expect(LorvexFocusWidgetProvider.familyKind(for: .systemExtraLarge) == .systemLarge)
    #expect(LorvexFocusWidgetProvider.familyKind(for: .accessoryInline) == .accessoryInline)
    #expect(
      LorvexFocusWidgetProvider.familyKind(for: .accessoryRectangular) == .accessoryRectangular
    )
  #endif
}

@Test
func extraLargeFamilyMapsToLargeButIsNoLongerExposed() throws {
  // systemExtraLarge has no dedicated layout (it collapsed to the systemLarge
  // design floating in a much larger frame), so neither widget advertises it in
  // `supportedFamilies` — but `familyKind` still maps it to systemLarge if the OS
  // ever requests it.
  #expect(LorvexFocusWidgetProvider.familyKind(for: .systemExtraLarge) == .systemLarge)
  let todaySource = try widgetExtensionSourceFile("LorvexTodayWidget.swift")
  #expect(todaySource.contains("case .systemLarge, .systemExtraLarge: .systemLarge"))
}

@Test
func widgetStaleStateDoesNotUseOverlayBadge() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let sourceRoot = root
    .appendingPathComponent("Sources")
    .appendingPathComponent("LorvexWidgetExtension")
  let swiftFiles = try FileManager.default.contentsOfDirectory(
    at: sourceRoot,
    includingPropertiesForKeys: nil
  )
  .filter { $0.pathExtension == "swift" }

  #expect(!swiftFiles.isEmpty)
  for file in swiftFiles {
    let source = try String(contentsOf: file, encoding: .utf8)
    #expect(!source.contains("lorvexStaleBadge"), "\(file.lastPathComponent) should render stale age in layout")
  }
}

@Test
func widgetTimelineAdapterProducesRefreshPolicyAndRenderModel() throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-adapter-tests-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 1, overdueCount: 0, dueTodayCount: 1),
    briefing: "Review focus",
    focusTasks: [
      .init(
        id: "task-widget",
        title: "Ship widget adapter",
        status: "open",
        dueDate: "2026-05-22",
        priority: 1,
        listID: nil,
        estimatedMinutes: 20
      )
    ]
  )
  try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: [.atomic])

  let now = Date(timeIntervalSince1970: 1_779_465_900)
  let support = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL),
    now: { now }
  )
  let adapter = LorvexWidgetTimelineAdapter(support: support)

  let timeline = adapter.timeline(family: .systemSmall)

  #expect(timeline.entries.count == 1)
  #expect(timeline.entries.first?.date == now)
  #expect(timeline.entries.first?.model.taskRows.map(\.id) == ["task-widget"])
}

@Test
func widgetStaticPlaceholderUsesRefreshPolicyCadence() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let timelineEntry = LorvexWidgetTimelineAdapter.staticPlaceholderTimelineEntry(
    refreshPolicy: WidgetTimelineRefreshPolicy(
      freshIntervalSeconds: 300,
      warningIntervalSeconds: 600,
      staleIntervalSeconds: 900
    ),
    now: now
  )
  let entry = LorvexWidgetTimelineAdapter.staticPlaceholder(
    family: .systemSmall,
    refreshPolicy: WidgetTimelineRefreshPolicy(
      freshIntervalSeconds: 300,
      warningIntervalSeconds: 600,
      staleIntervalSeconds: 900
    ),
    now: now
  )

  #expect(timelineEntry.refreshAfter == now.addingTimeInterval(900))
  #expect(entry.date == now)
  #expect(entry.model.state == .empty)
  #expect(entry.model.statusText == "Lorvex is ready.")
  #expect(entry.isPlaceholder == true)
}

@Test
func widgetGalleryPreviewUsesRepresentativeUnredactedContent() throws {
  let now = Date(timeIntervalSince1970: 1_779_465_600)

  let focus = LorvexWidgetTimelineAdapter.staticPreview(family: .systemMedium, now: now)
  #expect(focus.date == now)
  #expect(focus.isPlaceholder == false)
  #expect(focus.model.taskRows.map(\.id) == ["widget-preview-focus"])
  #expect(focus.model.state == .content)

  let raw = LorvexSnapshotTimelineAdapter.staticPreview(viewMode: .focus, now: now)
  let snapshot = try #require(raw.snapshot)
  #expect(raw.date == now)
  #expect(raw.isPlaceholder == false)
  #expect(raw.todayWidgetViewMode == .focus)
  #expect(snapshot.focusTasks.first?.status == LorvexTask.Status.inProgress.rawValue)
  #expect(snapshot.todayTasks.count == 1)
  #expect(snapshot.habits.count == 1)
  #expect(snapshot.stats.completedTodayCount == 2)

  let filtered = LorvexSnapshotTimelineAdapter.staticPreview(
    viewMode: .today,
    listID: "preview-list",
    now: now
  )
  #expect(filtered.snapshot?.focusTasks.first?.listID == "preview-list")
  #expect(filtered.snapshot?.todayTasks.first?.listID == "preview-list")
  #expect(filtered.snapshot?.listStats.first?.id == "preview-list")
}

@Test
func widgetProvidersSelectGalleryPreviewWithoutReadingAppGroupState() throws {
  let configuration = LorvexWidgetConfiguration()

  let focus = LorvexFocusWidgetProvider(configuration: configuration)
    .makeSnapshotEntry(family: .systemSmall, isPreview: true)
  #expect(focus.isPlaceholder == false)
  #expect(focus.model.taskRows.map(\.id) == ["widget-preview-focus"])

  let raw = LorvexSnapshotTimelineProvider(configuration: configuration)
    .makeSnapshotEntry(isPreview: true)
  #expect(raw.isPlaceholder == false)
  #expect(raw.snapshot?.habits.count == 1)

  let today = LorvexTodayWidgetTimelineProvider(configuration: configuration)
    .makeSnapshotEntry(viewMode: .today, isPreview: true)
  #expect(today.isPlaceholder == false)
  #expect(today.snapshot?.todayTasks.count == 1)

  // The non-preview path still reports missing App Group state honestly.
  #expect(LorvexSnapshotTimelineProvider(configuration: configuration)
    .makeSnapshotEntry(isPreview: false).snapshot == nil)
}

@Test
func widgetSnapshotAndTimelineEntriesAreNotPlaceholders() throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-adapter-not-placeholder-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  let snapshot = WidgetSnapshot(
    generatedAt: "2026-05-22T16:00:00Z",
    timezone: "UTC",
    stats: .init(focusCount: 0, overdueCount: 0, dueTodayCount: 0),
    briefing: nil,
    focusTasks: []
  )
  try JSONEncoder().encode(snapshot).write(to: snapshotURL, options: [.atomic])

  let support = WidgetTimelineProviderSupport(configuration: .init(snapshotURL: snapshotURL))
  let adapter = LorvexWidgetTimelineAdapter(support: support)

  #expect(adapter.snapshot(family: .systemSmall).isPlaceholder == false)
  #expect(adapter.timeline(family: .systemSmall).entries.first?.isPlaceholder == false)
}

@Test
func widgetTimelineAdapterPropagatesFallbackStatusToRenderModel() throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-widget-adapter-fallback-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  try "{ invalid json".write(to: snapshotURL, atomically: true, encoding: .utf8)

  let now = Date(timeIntervalSince1970: 1_779_465_900)
  let support = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL),
    now: { now }
  )
  let adapter = LorvexWidgetTimelineAdapter(support: support)

  let entry = adapter.snapshot(family: .systemSmall)

  #expect(entry.date == now)
  #expect(entry.model.state == .fallback)
  #expect(entry.model.statusText == "Snapshot data damaged")
  #expect(entry.model.urlString == "lorvex://open/today")
}

@Test
func snapshotTimelineAdapterPropagatesFallbackStatusAndViewConfiguration() throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-snapshot-adapter-fallback-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  try "{ invalid json".write(to: snapshotURL, atomically: true, encoding: .utf8)

  let now = Date(timeIntervalSince1970: 1_779_465_900)
  let support = WidgetTimelineProviderSupport(
    configuration: .init(snapshotURL: snapshotURL),
    now: { now }
  )
  let adapter = LorvexSnapshotTimelineAdapter(support: support)

  let entry = adapter.snapshot(viewMode: .focus, listID: "list-work")

  #expect(entry.date == now)
  #expect(entry.snapshot == nil)
  #expect(entry.statusText == "Snapshot data damaged")
  #expect(entry.todayWidgetViewMode == .focus)
  #expect(entry.todayWidgetListID == "list-work")
  #expect(entry.isPlaceholder == false)
}

@Test
func snapshotTimelineAdapterUsesRefreshPolicyFromSharedSupport() throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lorvex-snapshot-adapter-refresh-\(UUID().uuidString)", isDirectory: true)
  let snapshotURL = tempDirectory.appendingPathComponent(WidgetSnapshotLoader.defaultSnapshotFileName)
  defer { try? FileManager.default.removeItem(at: tempDirectory) }
  try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

  let now = Date(timeIntervalSince1970: 1_779_465_900)
  let support = WidgetTimelineProviderSupport(
    configuration: .init(
      snapshotURL: snapshotURL,
      refreshPolicy: WidgetTimelineRefreshPolicy(
        freshIntervalSeconds: 300,
        warningIntervalSeconds: 600,
        staleIntervalSeconds: 900
      )
    ),
    now: { now }
  )
  let adapter = LorvexSnapshotTimelineAdapter(support: support)

  let timeline = adapter.timeline(viewMode: .today)

  #expect(timeline.entries.count == 1)
  #expect(timeline.entries.first?.date == now)
  #expect(timeline.entries.first?.statusText == "Open Lorvex to refresh")
  #expect(timeline.policy == .after(now.addingTimeInterval(900)))
}

@Test
func snapshotTimelineAdapterStaticPlaceholderIsMarkedAsPlaceholder() {
  let now = Date(timeIntervalSince1970: 1_779_465_900)
  let entry = LorvexSnapshotTimelineAdapter.staticPlaceholder(viewMode: .focus, now: now)

  #expect(entry.date == now)
  #expect(entry.isPlaceholder == true)
  #expect(entry.todayWidgetViewMode == .focus)
}

@Test
func snapshotTimelineAdapterBuildsFallbackWhenSnapshotURLIsUnavailable() {
  let now = Date(timeIntervalSince1970: 1_779_465_900)
  let result = LorvexSnapshotTimelineAdapter.staticMissingSnapshotURLResult(
    viewMode: .today,
    refreshPolicy: WidgetTimelineRefreshPolicy(
      freshIntervalSeconds: 300,
      warningIntervalSeconds: 600,
      staleIntervalSeconds: 900
    ),
    now: now
  )

  #expect(result.entry.date == now)
  #expect(result.refreshAfter == now.addingTimeInterval(900))
  #expect(result.entry.snapshot == nil)
  #expect(result.entry.statusText == "Open Lorvex to refresh")
  // A missing App Group container is a persistent error, not a transient
  // loading state, so it renders its distinct fallback view as real content
  // rather than a placeholder skeleton.
  #expect(result.entry.isPlaceholder == false)
  guard case .fallback(let fallback) = result.entry.state else {
    Issue.record("Expected missing snapshot URL to produce fallback entry")
    return
  }
  #expect(fallback.reason == .missingFile)
}

@Test
func todayWidgetProviderBuildsFallbackWhenSnapshotURLIsUnavailable() {
  let provider = LorvexTodayWidgetTimelineProvider(configuration: LorvexWidgetConfiguration())

  let result = provider.makeTimelineEntry(viewMode: .focus, listID: "list-work")

  #expect(result.entry.snapshot == nil)
  #expect(result.entry.statusText == "Open Lorvex to refresh")
  #expect(result.entry.todayWidgetViewMode == .focus)
  #expect(result.entry.todayWidgetListID == "list-work")
  #expect(result.refreshAfter > result.entry.date)
  guard case .fallback(let fallback) = result.entry.state else {
    Issue.record("Expected missing Today widget snapshot URL to produce fallback entry")
    return
  }
  #expect(fallback.reason == .missingFile)
}

@Test
func focusWidgetEntryExposesSmartStackRelevanceForFocusTasks() {
  let now = Date(timeIntervalSince1970: 1_779_465_600)
  let entry = LorvexWidgetEntry(
    date: now,
    model: WidgetRenderModel(
      family: .systemSmall,
      state: .content,
      headline: "Today",
      subheadline: "Focus queue",
      statusText: "Updated now",
      focusCountText: "2 Focus",
      focusCount: 2,
      attentionCountText: nil,
      taskRows: [
        WidgetTaskRenderRow(
          id: "task-1",
          title: "First",
          metadata: nil,
          priorityLabel: "P1"
        )
      ],
      urlString: "lorvex://open/today"
    )
  )

  #expect(entry.relevance?.score == 40)
}

@Test
func smartStackRelevanceDecaysAtEndOfLocalDay() {
  let calendar = Calendar.current
  let date = Date(timeIntervalSince1970: 1_719_662_400)  // a fixed mid-day instant
  let relevance = WidgetSmartStackRelevancePolicy.relevance(taskCount: 2, date: date)

  let startOfDay = calendar.startOfDay(for: date)
  let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfDay)
  #expect(relevance?.score == 40)
  #expect(relevance?.duration == nextMidnight?.timeIntervalSince(date))
  #expect((relevance?.duration ?? 0) > 0)
}

@Test
func smartStackRelevanceUsesConfiguredProductTimezone() {
  let date = Date(timeIntervalSince1970: 1_719_725_400)  // 2024-06-30T05:30:00Z
  var productCalendar = Calendar(identifier: .gregorian)
  productCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
  let relevance = WidgetSmartStackRelevancePolicy.relevance(
    taskCount: 2,
    date: date,
    timezoneName: "America/Los_Angeles")

  let startOfDay = productCalendar.startOfDay(for: date)
  let nextMidnight = productCalendar.date(byAdding: .day, value: 1, to: startOfDay)
  #expect(relevance?.duration == nextMidnight?.timeIntervalSince(date))
}

@Test
func smartStackRelevanceIsNilWithoutTasks() {
  #expect(WidgetSmartStackRelevancePolicy.relevance(taskCount: 0, date: Date()) == nil)
}

@Test
func smartStackRelevanceMappingForwardsDurationToTimelineEntry() {
  let mapped = WidgetSmartStackRelevance(score: 50, duration: 3600).timelineEntryRelevance
  #expect(mapped.score == 50)
  #expect(mapped.duration == 3600)
}

private func widgetExtensionSourceFile(_ filename: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url = root
    .appendingPathComponent("Sources")
    .appendingPathComponent("LorvexWidgetExtension")
    .appendingPathComponent(filename)
  return try String(contentsOf: url, encoding: .utf8)
}
