import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexMobile
@testable import LorvexWatch

// A task that waits on an unfinished task cannot be started: the phone refuses
// the start. The widgets and the watch read "Blocked" for such a task, and the
// watch offers no Start for it. These pin the mark through the widget snapshot
// and the watch replica, the watch's row line, and the watch store.

private let waitingID = "00000000-0000-4000-8000-0000000000b1"
private let freeID = "00000000-0000-4000-8000-0000000000b2"

private func task(
  _ id: String, status: LorvexTask.Status = .open, due: String? = nil, minutes: Int? = nil
) -> LorvexTask {
  LorvexTask(
    id: id, title: id, notes: "", priority: .p2, status: status,
    dueDate: due.flatMap(LorvexDateFormatters.ymdUTC.date(from:)),
    plannedDate: nil, plannedTime: nil, estimatedMinutes: minutes, tags: [])
}

@Test("a snapshot task carries the blocked mark only while it is blocked")
func snapshotTaskCarriesTheBlockedMark() throws {
  func encoded(_ task: WidgetSnapshot.TodayTask) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any] ?? [:]
  }
  let blocked = WidgetSnapshot.TodayTask(
    id: waitingID, title: "Waiting", status: "open", dueDate: nil, priority: nil, listID: nil,
    estimatedMinutes: nil, isBlocked: true)
  let free = WidgetSnapshot.TodayTask(
    id: freeID, title: "Free", status: "open", dueDate: nil, priority: nil, listID: nil,
    estimatedMinutes: nil)

  #expect(try encoded(blocked)["blocked"] as? Bool == true)
  let roundTrip = try JSONDecoder().decode(
    WidgetSnapshot.TodayTask.self, from: JSONEncoder().encode(blocked))
  #expect(roundTrip.isBlocked)
  // A task that waits on nothing encodes without the key, and a payload
  // without the key reads as waiting on nothing, so a reader or a writer that
  // does not know the key exchanges the same tasks.
  #expect(try encoded(free)["blocked"] == nil)
  let withoutKey = #"{"id":"c","title":"t","status":"open"}"#
  #expect(
    try JSONDecoder().decode(WidgetSnapshot.TodayTask.self, from: Data(withoutKey.utf8)).isBlocked
      == false)
}

@Test("the widget snapshot marks Today's blocked tasks and the watch replica keeps the mark")
func projectionsCarryTheBlockedMark() throws {
  let today = TodaySnapshot(
    summary: "", tasks: [task(waitingID), task(freeID)], blockedTaskIDs: [waitingID],
    localChangeSequence: 0)
  let snapshot = WidgetSnapshotProjector().snapshot(
    logicalDay: "2026-09-22", today: today, timezone: "UTC")
  #expect(snapshot.tasks.map(\.isBlocked) == [true, false])

  let replica = try JSONDecoder().decode(
    WidgetSnapshot.self, from: WatchReplicaSnapshotProjector().encodedSnapshot(from: snapshot))
  #expect(replica.tasks.map(\.isBlocked) == [true, false])
}

@Test("the line under a watch row reads Blocked after a missed deadline and before Started")
func watchLineReadsBlocked() {
  func line(_ task: LorvexTask, time: Range<Int>? = nil) -> LorvexWatchTaskLine? {
    LorvexWatchTaskLine.make(
      task: task, time: time, nowMinutes: 610, logicalDay: "2026-09-22", isBlocked: true)
  }
  #expect(
    line(task("w", minutes: 30))
      == LorvexWatchTaskLine(text: LorvexWatchCalmCopy.blocked, tone: .plain),
    "Blocked reads before the estimate")
  #expect(line(task("s", status: .inProgress))?.text == LorvexWatchCalmCopy.blocked)
  #expect(line(task("o", due: "2026-09-21"))?.tone == .overdue, "a missed deadline reads first")
  #expect(line(task("t"), time: 600..<660)?.tone == .running, "a running time reads first")
}

@MainActor
@Test("the watch store reads Today's blocked tasks from the core")
func watchStoreReadsBlockedTasksFromTheCore() async throws {
  // The seeded "Book the offsite venue" waits on "Draft the team offsite agenda".
  let core = try await makeSeededInMemoryCore()
  let store = LorvexWatchStore(core: core)
  await store.refresh()
  #expect(store.blockedTaskIDs.contains(LorvexPreviewSeedID.venueTask))

  _ = try await core.completeTask(id: LorvexPreviewSeedID.agendaTask)
  await store.refresh()
  #expect(!store.blockedTaskIDs.contains(LorvexPreviewSeedID.venueTask))
}
