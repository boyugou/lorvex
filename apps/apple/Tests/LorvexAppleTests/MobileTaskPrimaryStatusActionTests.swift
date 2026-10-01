import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@Suite("Mobile task detail primary status action")
struct MobileTaskPrimaryStatusActionTests {
  @Test("active tasks complete, resolved tasks reopen, parked tasks move to open")
  func mapsEveryStatusToOneAction() {
    #expect(MobileTaskPrimaryStatusAction(status: .open) == .complete)
    #expect(MobileTaskPrimaryStatusAction(status: .inProgress) == .complete)
    #expect(MobileTaskPrimaryStatusAction(status: .completed) == .reopen)
    #expect(MobileTaskPrimaryStatusAction(status: .cancelled) == .reopen)
    #expect(MobileTaskPrimaryStatusAction(status: .someday) == .moveToOpen)
  }

  @Test("only completing is tinted done; both reopening actions drive the reopen transition")
  func presentationFollowsTheAction() {
    #expect(MobileTaskPrimaryStatusAction.complete.tint == LorvexDesign.Palette.done)
    #expect(MobileTaskPrimaryStatusAction.reopen.tint == nil)
    #expect(MobileTaskPrimaryStatusAction.moveToOpen.tint == nil)
    #expect(!MobileTaskPrimaryStatusAction.complete.performsReopen)
    #expect(MobileTaskPrimaryStatusAction.reopen.performsReopen)
    #expect(MobileTaskPrimaryStatusAction.moveToOpen.performsReopen)
    #expect(MobileTaskPrimaryStatusAction.complete.accessibilityIdentifier == "task.detail.complete")
    #expect(MobileTaskPrimaryStatusAction.reopen.accessibilityIdentifier == "task.detail.reopen")
    #expect(
      MobileTaskPrimaryStatusAction.moveToOpen.accessibilityIdentifier == "task.detail.moveToOpen")
  }

  @Test("the detail folds empty composers behind add rows and lists reminder presets as rows")
  func detailFoldsComposers() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let detail = try String(
      contentsOf: root.appending(path: "Sources/LorvexMobile/MobileTaskDetailContent.swift"),
      encoding: .utf8)
    let composers = try String(
      contentsOf: root.appending(path: "Sources/LorvexMobile/MobileTaskComposerRows.swift"),
      encoding: .utf8)
    let actions = try String(
      contentsOf: root.appending(path: "Sources/LorvexMobile/MobileTaskActionViews.swift"),
      encoding: .utf8)
    let detailView = try String(
      contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreTaskDetailView.swift"),
      encoding: .utf8)

    // Each composer renders only while its flag is set; otherwise an "Add …" row stands in.
    #expect(detail.contains("if isComposingChecklistItem {"))
    #expect(detail.contains("if isComposingReminder {"))
    #expect(detail.contains("\"checklist.add\""))
    #expect(detail.contains("\"reminder.add\""))
    // Reminder presets are rows that add in one tap, never a scroller that
    // clips at the row's trailing edge; the composer's Cancel rides the header.
    #expect(composers.contains("ForEach(availablePresets(now: LorvexPreviewClock.now(in: .current))"))
    #expect(!composers.contains("ScrollView(.horizontal"))
    #expect(detail.contains("\"task.detail.reminders.cancel\""))
    // The status transition lives in the toolbar, not in the action rows; only a
    // parked task keeps a Complete tile there.
    #expect(detailView.contains("MobileTaskPrimaryStatusAction(status: task.status)"))
    #expect(!actions.contains("\"action.reopen\""))
    #expect(actions.contains("case .someday: [.complete, .deferTask, .cancel]"))
  }
}
