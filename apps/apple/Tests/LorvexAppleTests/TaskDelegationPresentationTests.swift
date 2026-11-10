import LorvexCore
import Testing

@testable import LorvexMobile

/// Pins what a task says about its hand-off to the assistant
/// (``LorvexTaskDelegationMarker``) and which hand-off actions its menus offer
/// (``LorvexTaskDelegationAction``): both only while the task is open work
/// outside the Trash, the marker neutral while the assistant holds the task and
/// in the accent once it replied, and Hand to Assistant offered again beside
/// Take Back for a task the assistant handed back.
@Suite("Task hand-off presentation")
struct TaskDelegationPresentationTests {
  private static func task(
    status: LorvexTask.Status = .open, delegation: LorvexTaskDelegation.State?,
    archivedAt: String? = nil
  ) -> LorvexTask {
    LorvexTask(
      id: "task", title: "Reply to Maya", notes: "", priority: .p2, status: status, dueDate: nil,
      estimatedMinutes: nil, tags: [], archivedAt: archivedAt,
      delegation: delegation.map { LorvexTaskDelegation(state: $0) })
  }

  @Test("a task that is the person's own shows no marker")
  func ownTaskShowsNoMarker() {
    #expect(LorvexTaskDelegationMarker(task: Self.task(delegation: nil)) == nil)
  }

  @Test("a task the assistant holds reads With assistant, in the neutral style")
  func heldTaskIsNeutral() throws {
    for status in [LorvexTask.Status.open, .inProgress] {
      let marker = try #require(
        LorvexTaskDelegationMarker(task: Self.task(status: status, delegation: .assistant)))
      #expect(marker == .withAssistant)
      #expect(!marker.asksForAttention)
      #expect(marker.tint == LorvexDesign.Palette.neutral)
    }
  }

  @Test("a task the assistant handed back reads Assistant replied, in the accent")
  func returnedTaskTakesTheAccent() throws {
    for status in [LorvexTask.Status.open, .inProgress] {
      let marker = try #require(
        LorvexTaskDelegationMarker(task: Self.task(status: status, delegation: .returned)))
      #expect(marker == .assistantReplied)
      #expect(marker.asksForAttention)
      #expect(marker.tint == LorvexDesign.Palette.accent)
    }
  }

  @Test("a done, cancelled, parked, or trashed task shows no marker, whatever its hand-off")
  func settledTasksShowNoMarker() {
    for state in LorvexTaskDelegation.State.allCases {
      for status in [LorvexTask.Status.completed, .cancelled, .someday] {
        #expect(LorvexTaskDelegationMarker(task: Self.task(status: status, delegation: state)) == nil)
      }
      let trashed = Self.task(delegation: state, archivedAt: "2026-11-10T09:00:00Z")
      #expect(LorvexTaskDelegationMarker(task: trashed) == nil)
    }
  }

  @Test("both markers lead with the sparkles glyph")
  func markerGlyph() {
    #expect(LorvexTaskDelegationMarker.systemImage == "sparkles")
  }

  @Test("a task of the person's own offers Hand to Assistant alone")
  func ownTaskOffersHandOver() {
    #expect(LorvexTaskDelegationAction.available(for: Self.task(delegation: nil)) == [.handToAssistant])
    #expect(
      LorvexTaskDelegationAction.available(for: Self.task(status: .inProgress, delegation: nil))
        == [.handToAssistant])
  }

  @Test("a task the assistant holds offers Take Back alone")
  func heldTaskOffersTakeBack() {
    #expect(LorvexTaskDelegationAction.available(for: Self.task(delegation: .assistant)) == [.takeBack])
  }

  @Test("a task the assistant handed back offers Hand to Assistant again, then Take Back")
  func returnedTaskOffersBoth() {
    #expect(
      LorvexTaskDelegationAction.available(for: Self.task(delegation: .returned))
        == [.handToAssistant, .takeBack])
  }

  @Test("a done, cancelled, parked, or trashed task offers neither action")
  func settledTasksOfferNothing() {
    for state in [nil] + LorvexTaskDelegation.State.allCases.map(Optional.some) {
      for status in [LorvexTask.Status.completed, .cancelled, .someday] {
        #expect(LorvexTaskDelegationAction.available(for: Self.task(status: status, delegation: state)).isEmpty)
      }
      let trashed = Self.task(delegation: state, archivedAt: "2026-11-10T09:00:00Z")
      #expect(LorvexTaskDelegationAction.available(for: trashed).isEmpty)
    }
  }

  @Test("the actions carry the sparkles and the backward U-turn glyphs")
  func actionGlyphs() {
    #expect(LorvexTaskDelegationAction.handToAssistant.systemImage == "sparkles")
    #expect(LorvexTaskDelegationAction.takeBack.systemImage == "arrow.uturn.backward")
  }

  @Test("VoiceOver hears the marker's words on an iPhone row, and nothing for an own task")
  func mobileSpokenLabelNamesTheHandOff() {
    let replied = Self.task(delegation: .returned)
    #expect(MobileTaskRowContent.delegationDetails(for: replied) == ["Assistant replied"])
    #expect(MobileTaskRowContent.delegationDetails(for: Self.task(delegation: .assistant)) == ["With assistant"])
    #expect(MobileTaskRowContent.delegationDetails(for: Self.task(delegation: nil)).isEmpty)
    let label = MobileTaskWorkspaceSelectableRow.spokenLabel(
      for: replied, timeLabel: nil, isBlocked: false, searchMatch: nil, timeZone: .gmt)
    #expect(label.contains("Assistant replied"))
  }
}
