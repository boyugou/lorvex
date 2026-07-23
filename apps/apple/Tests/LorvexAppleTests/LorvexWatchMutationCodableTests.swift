import Foundation
import LorvexCore
import Testing

// MARK: - Codable round-trips

@Suite("LorvexWatchMutation Codable")
struct LorvexWatchMutationCodableTests {
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  private func roundTrip(_ mutation: LorvexWatchMutation) throws -> LorvexWatchMutation {
    let data = try encoder.encode(mutation)
    return try decoder.decode(LorvexWatchMutation.self, from: data)
  }

  @Test("completeTask round-trips")
  func completeTask() throws {
    let id = LorvexTask.ID("task-1")
    #expect(try roundTrip(.completeTask(id: id)) == .completeTask(id: id))
  }

  @Test("cancelTask round-trips")
  func cancelTask() throws {
    let id = LorvexTask.ID("task-2")
    #expect(try roundTrip(.cancelTask(id: id)) == .cancelTask(id: id))
  }

  @Test("deferTaskToTomorrow round-trips")
  func deferTaskToTomorrow() throws {
    let id = LorvexTask.ID("task-3")
    #expect(
      try roundTrip(.deferTaskToTomorrow(id: id, plannedDate: "2026-05-25"))
        == .deferTaskToTomorrow(id: id, plannedDate: "2026-05-25"))
  }

  @Test("removeFromFocus round-trips")
  func removeFromFocus() throws {
    let id = LorvexTask.ID("task-4")
    #expect(
      try roundTrip(.removeFromFocus(id: id, date: "2026-05-24"))
        == .removeFromFocus(id: id, date: "2026-05-24"))
  }

  @Test("captureTask round-trips")
  func captureTask() throws {
    #expect(try roundTrip(.captureTask(title: "Buy milk")) == .captureTask(title: "Buy milk"))
  }

  @Test("completeHabit round-trips")
  func completeHabit() throws {
    #expect(
      try roundTrip(.completeHabit(id: "habit-1", date: "2026-05-24"))
        == .completeHabit(id: "habit-1", date: "2026-05-24"))
  }
}
