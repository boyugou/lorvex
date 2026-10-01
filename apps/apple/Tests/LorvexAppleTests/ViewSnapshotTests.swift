import Foundation
import LorvexCore
import SwiftUI
import Testing

@testable import LorvexApple

// MARK: - Render helper

/// Renders a SwiftUI view to PNG data using ImageRenderer.
///
/// Returns nil when the renderer cannot produce a CGImage (e.g. unsupported
/// platform configuration). Callers should assert the result is non-nil and
/// has a byte count consistent with a real rasterised image (> 1 KB).
@MainActor
func renderSnapshot<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 844)) -> Data? {
  let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
  renderer.scale = 1
  guard let cgImage = renderer.cgImage else { return nil }
  guard let colorSpace = cgImage.colorSpace else { return nil }
  let ctx = CGContext(
    data: nil,
    width: cgImage.width,
    height: cgImage.height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )
  ctx?.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
  guard let finalImage = ctx?.makeImage() else { return nil }
  let mutableData = NSMutableData()
  guard
    let dest = CGImageDestinationCreateWithData(
      mutableData, "public.png" as CFString, 1, nil)
  else { return nil }
  CGImageDestinationAddImage(dest, finalImage, nil)
  guard CGImageDestinationFinalize(dest) else { return nil }
  return mutableData as Data
}

// MARK: - Desktop view snapshot tests

@Suite("Desktop view snapshot tests")
@MainActor
struct ViewSnapshotTests {

  private func makeStore() async throws -> AppStore {
    AppStore(core: try await makeSeededInMemoryCore())
  }

  @Test
  func todayViewRendersWithPreviewStore() async throws {
    let store = try await makeStore()
    let data = renderSnapshot(TodayView(store: store), size: CGSize(width: 600, height: 800))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func habitsWorkspaceViewRendersTrackerCards() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    store.habits = try await core.loadHabits(date: "2026-05-23")

    let data = renderSnapshot(HabitsWorkspaceView(store: store), size: CGSize(width: 720, height: 700))

    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func tasksViewRendersOpenTasks() async throws {
    let store = try await makeStore()
    let data = renderSnapshot(TasksView(store: store), size: CGSize(width: 600, height: 700))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func tasksViewRendersWithSearchText() async throws {
    let store = try await makeStore()
    store.searchText = "offsite"
    let data = renderSnapshot(TasksView(store: store), size: CGSize(width: 600, height: 700))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func taskDetailViewRendersWithSelectedTask() async throws {
    let store = try await makeStore()
    store.selectedTaskID = LorvexPreviewSeedID.agendaTask
    let data = renderSnapshot(TaskDetailView(store: store), size: CGSize(width: 500, height: 800))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func taskDetailViewRendersEmptyStateWithNoSelection() async throws {
    let store = try await makeStore()
    store.selectedTaskID = nil
    let data = renderSnapshot(TaskDetailView(store: store), size: CGSize(width: 500, height: 800))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func lorvexEmptyStatePanelRendersActionAndChips() {
    let data = renderSnapshot(
      LorvexEmptyStatePanel(
        title: "No Results",
        message: "Nothing matched the current filters.",
        systemImage: "magnifyingglass",
        tint: .accentColor,
        chips: [
          LorvexEmptyStateChip(title: "query", systemImage: "text.magnifyingglass", tint: .accentColor),
          LorvexEmptyStateChip(title: "P1", systemImage: "flag", tint: .red),
        ]
      ) {
        Button("Clear") {}
          .buttonStyle(.bordered)
      },
      size: CGSize(width: 560, height: 360)
    )

    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func menuBarStatusViewRendersWithPreviewStore() async throws {
    let store = try await makeStore()
    let data = renderSnapshot(MenuBarStatusView(store: store), size: CGSize(width: 280, height: 400))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func sidebarViewRendersWithPreviewStore() async throws {
    let store = try await makeStore()
    let data = renderSnapshot(SidebarView(store: store), size: CGSize(width: 318, height: 700))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func weekReviewPageRendersTheWeek() {
    let review = WeeklyReviewSnapshot(
      windowTitle: "Last 7 days",
      completedThisWeek: 4,
      createdThisWeek: 7,
      overdueOpen: 1,
      deferredOpen: 2,
      someday: 3,
      estimateCoverageRatio: 0.75,
      topCompleted: [
        ReviewTaskSummary(
          id: "done-1", title: "Ship native review pane", status: "completed", deferCount: 0)
      ],
      frequentlyDeferred: [
        ReviewTaskSummary(id: "defer-1", title: "Calendar recurrence", status: "open", deferCount: 3)
      ],
      overdueTasks: [
        ReviewTaskSummary(
          id: "late-1", title: "Renew passport", status: "open", deferCount: 0,
          dueDate: "2026-05-18")
      ],
      topSomeday: [
        ReviewTaskSummary(id: "someday-1", title: "Learn a new framework", status: "someday", deferCount: 0)
      ]
    )

    let reviews = [
      DailyReviewEntry(
        date: "2026-05-21", summary: "Shipped the evidence panel.", mood: 4, energyLevel: 3,
        wins: nil, blockers: nil, learnings: nil,
        timezone: nil, updatedAt: nil, linkedTaskIDs: [], linkedListIDs: [])
    ]
    let words = WeeklyReviewPage.words(review)
    #expect(words.decision?.taskID == "defer-1")
    #expect(words.sentence.hasPrefix("You finished 4 tasks."))

    let data = renderSnapshot(
      LorvexWeekReviewPage(
        dateLine: review.windowTitle, review: review, days: reviews, words: words,
        openDay: { _ in }, openTask: { _ in }, decide: { _ in }),
      size: CGSize(width: 640, height: 720)
    )

    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test
  func readOnlyDailyReviewRendersSavedFields() {
    let review = DailyReviewEntry(
      date: "2026-09-18", summary: "A slow start, then the sync fix landed.", mood: 4, energyLevel: 2,
      wins: "Closed the watchdog bug.", blockers: nil, learnings: "Pair the drain with the push.",
      timezone: nil, updatedAt: nil, linkedTaskIDs: [], linkedListIDs: [])
    let data = renderSnapshot(
      DailyReviewReadOnlyView(review: review).padding(24), size: CGSize(width: 640, height: 520))
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }
}
