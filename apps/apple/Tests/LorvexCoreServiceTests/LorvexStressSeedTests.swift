#if DEBUG
  import Foundation
  import Testing

  @testable import LorvexCore

  /// The stress seed holds each task, list, and habit the macOS tour opens by
  /// name, so a rename in the seed cannot silently drop a tour stop.
  @Suite("Stress seed")
  struct LorvexStressSeedTests {
    @Test("seeds the content the macOS tour opens by name")
    func seedsTheTourAnchors() async throws {
      let service = try SwiftLorvexCoreService.inMemory()
      await LorvexStressSeed.apply(
        to: service, today: "2026-10-03", timezone: "America/Los_Angeles")

      let titles = try await service.loadTasksForDataExport().map(\.title)
      for (stop, prefix) in LorvexStressSeed.inspectorTasks {
        #expect(
          titles.contains { $0.hasPrefix(prefix) },
          "\(stop) needs a task whose title starts “\(prefix)”")
      }
      let lists = try await service.loadLists().lists.map(\.name)
      #expect(lists.contains { $0.hasPrefix(LorvexStressSeed.longListNamePrefix) })
      let habits = try await service.loadHabits(date: "2026-10-03").habits.map(\.name)
      #expect(habits.contains { $0.hasPrefix(LorvexStressSeed.longHabitNamePrefix) })
    }
  }
#endif
