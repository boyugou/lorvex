import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile
@testable import LorvexWidgetKitSupport

/// A task handed to the assistant carries its hand-off marker onto the
/// widgets, as the app's rows do: a quiet sparkles glyph while the assistant
/// holds the task, and "Replied" in the accent once it handed the task back,
/// since the reply waits on the person.
@Suite("Widget hand-off marker")
struct WidgetDelegationMarkerTests {
  private static func encoded(_ task: WidgetSnapshot.TodayTask) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any] ?? [:]
  }

  private static func todayTask(
    _ id: String, delegation: LorvexTaskDelegationMarker? = nil, minutes: Int? = nil,
    start: String? = nil, end: String? = nil
  ) -> WidgetSnapshot.TodayTask {
    WidgetSnapshot.TodayTask(
      id: id, title: id, status: "open", dueDate: nil, priority: 2, listID: nil,
      estimatedMinutes: minutes, scheduledStart: start, scheduledEnd: end,
      delegation: delegation)
  }

  @Test("the marker is a key the snapshot carries only for a handed-off task")
  func encoding() throws {
    #expect(try Self.encoded(Self.todayTask("a", delegation: .withAssistant))["delegation"] as? String == "assistant")
    #expect(try Self.encoded(Self.todayTask("r", delegation: .assistantReplied))["delegation"] as? String == "returned")
    // The person's own task carries no key, and a reader that does not know
    // the key, or a value it does not know, reads the person's own task.
    #expect(try Self.encoded(Self.todayTask("o"))["delegation"] == nil)
    for json in [
      #"{"id":"c","title":"t","status":"open"}"#,
      #"{"id":"c","title":"t","status":"open","delegation":"someone_else"}"#,
    ] {
      let task = try JSONDecoder().decode(WidgetSnapshot.TodayTask.self, from: Data(json.utf8))
      #expect(task.delegationMarker == nil)
    }
    for marker in [LorvexTaskDelegationMarker.withAssistant, .assistantReplied] {
      let roundTrip = try JSONDecoder().decode(
        WidgetSnapshot.TodayTask.self,
        from: JSONEncoder().encode(Self.todayTask("t", delegation: marker)))
      #expect(roundTrip.delegationMarker == marker)
    }
  }

  @Test("a hand-off made in the database reaches the widget snapshot but not the watch")
  func handOffReachesTheWidget() async throws {
    let clock = seedMorningWallClock()
    let core = try await makeSeededInMemoryCore(wallClock: clock)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
    let day = WidgetSnapshotProjector.localDateOnlyString(from: clock(), calendar: calendar)
    let task = try await core.createTask(TaskCreateDraft(title: "Book flights", dueDate: clock()))

    func projected() async throws -> WidgetSnapshot {
      let source = try await core.loadWidgetSnapshotSource(date: day)
      return try await WidgetSnapshotPublisher(destination: .init(snapshotURL: nil, reload: {}))
        .publish(source: source)
    }
    func marker() async throws -> LorvexTaskDelegationMarker?? {
      try await projected().tasks.first { $0.id == task.id }.map(\.delegationMarker)
    }

    #expect(try await marker() == .some(nil))
    _ = try await core.delegateTask(id: task.id, request: nil)
    #expect(try await marker() == .withAssistant)
    _ = try await core.returnDelegatedTask(id: task.id, result: "Two options saved in the notes.")
    #expect(try await marker() == .assistantReplied)

    let replica = try JSONDecoder().decode(
      WidgetSnapshot.self,
      from: WatchReplicaSnapshotProjector().encodedSnapshot(from: try await projected()))
    let onWatch = try #require(replica.tasks.first { $0.id == task.id })
    #expect(onWatch.delegationMarker == nil, "the watch draws no marker, so its replica carries none")

    _ = try await core.clearTaskDelegation(id: task.id)
    #expect(try await marker() == .some(nil))
  }

  @Test("a row reads Replied once the assistant handed the task back, unless its time runs")
  func rowMetadata() throws {
    let snapshot = WidgetSnapshot(
      generatedAt: "2026-06-30T12:00:00Z", timezone: "UTC", logicalDay: "2026-06-30",
      stats: .init(todayCount: 4, overdueCount: 0, dueTodayCount: 0),
      briefing: nil,
      tasks: [
        Self.todayTask("replied", delegation: .assistantReplied, minutes: 30, start: "14:00", end: "14:30"),
        Self.todayTask("holding", delegation: .withAssistant, minutes: 45),
        Self.todayTask("running", delegation: .assistantReplied, start: "09:30", end: "10:30"),
        Self.todayTask("own", minutes: 20),
      ])
    // 10:00 UTC: "running" leads while its time runs, so the clock is set
    // past it to read every task as a row.
    func rows(at clock: String) -> [String: WidgetTaskRenderRow] {
      let date = LorvexDateFormatters.iso8601.date(from: "2026-06-30T\(clock):00Z") ?? Date()
      let model = WidgetRenderModelBuilder().model(
        entry: .init(
          date: date, state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
          refreshAfter: date),
        family: .systemLarge, statusText: "")
      var rows = Dictionary(uniqueKeysWithValues: model.taskRows.map { ($0.id, $0) })
      if let lead = model.lead {
        rows[lead.id] = WidgetTaskRenderRow(
          id: lead.id, title: lead.title, metadata: lead.line, delegation: lead.delegation)
      }
      return rows
    }

    let afternoon = rows(at: "15:00")
    let replied = try #require(afternoon["replied"])
    #expect(replied.metadata == "Replied", "the reply reads before the task's time")
    #expect(replied.tone == .replied)
    #expect(replied.delegation == .assistantReplied)
    let holding = try #require(afternoon["holding"])
    #expect(holding.metadata == LorvexDurationFormat.minutes(45), "a task the assistant holds keeps its line")
    #expect(holding.tone == .plain)
    #expect(holding.delegation == .withAssistant)
    #expect(try #require(afternoon["own"]).delegation == nil)

    // While a handed-back task's time runs, it leads, its line says until
    // when, and the glyph beside the line carries the reply.
    let morning = rows(at: "10:00")
    let running = try #require(morning["running"])
    #expect(running.metadata?.hasPrefix("Until") == true)
    #expect(running.delegation == .assistantReplied)
  }
}
